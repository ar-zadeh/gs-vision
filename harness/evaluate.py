"""Explicit run-manifest evaluation; all model and human values retain provenance."""
from __future__ import annotations

import json
import hashlib
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm

from harness.human_data import (CELLS, QUANTILES, group_summary, participant_summary,
                               load_split, digest)
from harness.analyze import fit_exgaussian


def model_frame(paths, mirror=False):
    frames = []
    for path in paths:
        path = Path(path)
        if mirror:
            frame = pd.DataFrame(json.loads(path.read_text()))
            frame["rt_ms"] = frame.rt * 1000
            frame["search_ms"] = frame.search_time * 1000
        else:
            frame = pd.read_csv(path)
        frames.append(frame)
    df = pd.concat(frames, ignore_index=True)
    if "practice" in df:
        df = df.loc[df.practice.fillna(0).astype(int) == 0].copy()
    df["correct"] = df.correct.fillna(0).astype(bool)
    df["timed_out"] = df.timed_out.fillna(0).astype(bool)
    df["error"] = (~df.correct & ~df.timed_out).astype(int)
    df["participant_key"] = df.task + ":model:" + df.subject_seed.astype(str)
    df["rt_eligible"] = df.rt_ms.between(200, np.where(df.task == "spatial", 8000, 4000))
    df["positive_rt_eligible"] = df.rt_ms > 0
    return df


def summary(df):
    out = group_summary(participant_summary(df))
    extra = df.groupby(CELLS).agg(timeouts=("timed_out", "sum"),
                                  fixation_count=("n_fixations", "mean"),
                                  search_mean_ms=("search_ms", "mean")).reset_index()
    return out.merge(extra, on=CELLS, validate="one_to_one")


def compare(human, model):
    cells = human.merge(model, on=CELLS, suffixes=("_human", "_model"), validate="one_to_one")
    if len(cells) != len(human):
        raise ValueError("Missing required model cells")
    cells["mean_error_ms"] = cells.mean_model - cells.mean_human
    cells["median_error_ms"] = cells.median_model - cells.median_human
    cells["error_diff_points"] = 100 * (cells.error_rate_model - cells.error_rate_human)
    cells["quantile_rmse_ms"] = np.sqrt(np.mean(np.stack([
        cells[f"q{int(q*100)}_model"] - cells[f"q{int(q*100)}_human"] for q in QUANTILES]) ** 2, axis=0))
    slopes = []
    for (task, present), group in cells.groupby(["task", "target_present"]):
        rec = dict(task=task, target_present=present)
        for side in ("human", "model"):
            slope, intercept = np.polyfit(group.set_size, group[f"mean_{side}"], 1)
            rec[f"slope_{side}"] = slope
            rec[f"intercept_{side}"] = intercept
        rec["slope_error"] = rec["slope_model"] - rec["slope_human"]
        rec["intercept_error"] = rec["intercept_model"] - rec["intercept_human"]
        rec["slope_pass"] = abs(rec["slope_error"]) <= 5
        slopes.append(rec)
    return cells, pd.DataFrame(slopes)


def parity(lisp, python):
    """Bonferroni family of 24 search means; quantiles and eye metrics descriptive."""
    means = []
    for key, left in lisp.groupby(CELLS):
        right = python.loc[np.logical_and.reduce([python[c] == v for c, v in zip(CELLS, key)])]
        if right.empty:
            raise ValueError(f"Missing mirror cell {key}")
        rec = dict(zip(CELLS, key))
        rec["n_lisp"], rec["n_mirror"] = len(left), len(right)
        rec["difference_ms"] = left.search_ms.mean() - right.search_ms.mean()
        rec["mc_se_ms"] = np.hypot(left.search_ms.sem(), right.search_ms.sem())
        rec["z"] = rec["difference_ms"] / rec["mc_se_ms"]
        rec["error_difference_points"] = 100 * (left.error.mean() - right.error.mean())
        rec["fixation_count_difference"] = left.n_fixations.mean() - right.n_fixations.mean()
        for q in QUANTILES:
            rec[f"search_q{int(100*q)}_difference"] = left.search_ms.quantile(q) - right.search_ms.quantile(q)
        means.append(rec)
    result = pd.DataFrame(means)
    threshold = norm.ppf(1 - .05 / (2 * len(result)))
    result["bonferroni_threshold"] = threshold
    result["exceeds_family_threshold"] = result.z.abs() > threshold
    return result


def eye_summary(fixations, trials):
    from harness.tasks import px2deg
    fx = fixations.merge(trials[["subject_seed", "task", "trial"]],
                         on=["subject_seed", "task", "trial"], validate="many_to_one")
    rows = []
    for task, group in fx.groupby("task"):
        amps, refix = [], []
        for _, trial in group.groupby(["subject_seed", "trial"]):
            xy = trial.sort_values("idx")[["x", "y"]].to_numpy()
            amps.extend(px2deg(float(d)) for d in np.linalg.norm(np.diff(xy, axis=0), axis=1))
            for i in range(1, len(xy)):
                refix.append(any(px2deg(float(np.linalg.norm(xy[i]-v))) < 1 for v in xy[:i]))
        t = trials[trials.task == task]
        rows.append(dict(task=task, mean_duration_ms=group.dur.mean(), mean_amplitude_deg=np.mean(amps) if amps else np.nan,
                         mean_count=t.n_fixations.mean(), refixation_rate=np.mean(refix) if refix else 0,
                         rejected_per_fixation=t.n_rejected.sum() / t.n_fixations.sum(),
                         window="search request to visual result; execution excluded"))
    return pd.DataFrame(rows)


def evaluate_manifest(path, out, final_test=False):
    path, out = Path(path).resolve(), Path(out).resolve()
    manifest = json.loads(path.read_text())
    base = path.parent
    resolve = lambda p: (base / p).resolve()
    human_dir = resolve(manifest["human"])
    if final_test:
        frozen = json.loads(resolve(manifest["frozen"]).read_text())
        if frozen["model_selection_status"] != "frozen_before_test":
            raise ValueError("Final test requires frozen model selection")
        if frozen["runs_hash"] != digest(manifest["runs"]):
            raise ValueError("Run definitions changed after freeze")
    out.mkdir(parents=True, exist_ok=True)
    splits = ("train", "validation", "test") if final_test else ("train", "validation")
    humans, human_info = {}, None
    for split in splits:
        df, human_info = load_split(human_dir, split)
        humans[split] = group_summary(participant_summary(df))
        humans[split].to_csv(out / f"human_{split}.csv", index=False)
        group_summary(participant_summary(df, sensitivity=True)).to_csv(out / f"human_{split}_positive.csv", index=False)
        human_ex = []
        for keys, group in df.groupby(["participant_key"] + CELLS):
            mu, sigma, tau = fit_exgaussian(group.loc[group.correct & group.rt_eligible, "rt_ms"].to_numpy())
            human_ex.append(dict(zip(["participant_key"] + CELLS, keys)) | dict(mu=mu,sigma=sigma,tau=tau))
        pd.DataFrame(human_ex).to_csv(out / f"human_{split}_exgaussian.csv", index=False)
    record = dict(manifest=str(path), human=human_info, runs=[], test_evaluated=final_test,
                  evaluated_utc=datetime.now(timezone.utc).isoformat())
    for entry in manifest["runs"]:
        run = entry["id"]
        from harness.parameters import validate, lisp_values, readback_matches
        from harness.run_batch import param_hash
        expected = lisp_values(validate(entry["parameters"]["params"]))
        input_hashes = {}
        for file in entry["trials"]:
            trial_path = resolve(file)
            metadata_path = trial_path.with_name(trial_path.name.replace("_trials.csv", "_manifest.json"))
            if entry.get("reuse_shared_simulation"):
                metadata_path = metadata_path.with_name(metadata_path.name.replace(run, "shared", 1))
            metadata = json.loads(metadata_path.read_text())
            actual = metadata["effective"]
            if not readback_matches(actual, expected):
                raise ValueError(f"Run parameter readback disagrees with manifest: {file}")
            if param_hash(actual) != metadata["effective_hash"]:
                raise ValueError(f"Run effective hash corrupted: {file}")
            trial_hashes = pd.read_csv(trial_path, usecols=["param_hash"]).param_hash.unique()
            if list(trial_hashes) != [metadata["effective_hash"]]:
                raise ValueError(f"Trial configuration identity differs: {file}")
            input_hashes[file] = hashlib.sha256(trial_path.read_bytes()).hexdigest()
        trials = model_frame([resolve(p) for p in entry["trials"]])
        current = summary(trials)
        current.to_csv(out / f"{run}_model.csv", index=False)
        row = dict(id=run, role=entry["role"], comparisons={}, source_hashes=input_hashes)
        for split, human in humans.items():
            human = human[human.task.isin(trials.task.unique())]
            cells, slopes = compare(human, current)
            cells.to_csv(out / f"{run}_{split}_cells.csv", index=False)
            slopes.to_csv(out / f"{run}_{split}_slopes.csv", index=False)
            row["comparisons"][split] = dict(mean_rt_rmse_ms=float(np.sqrt(np.mean(cells.mean_error_ms**2))),
                mean_quantile_rmse_ms=float(cells.quantile_rmse_ms.mean()),
                slopes_pass=int(slopes.slope_pass.sum()), slopes_total=len(slopes),
                max_miss_difference_points=float(cells.loc[cells.target_present == 1, "error_diff_points"].abs().max()),
                timeouts=int(current.timeouts.sum()))
            plot_comparison(cells, out / f"{run}_{split}.png", f"{run}: {split} participants")
        if entry.get("mirror"):
            py = model_frame([resolve(p) for p in entry["mirror"]], mirror=True)
            agreement = parity(trials, py)
            agreement.to_csv(out / f"{run}_parity.csv", index=False)
            row["parity"] = dict(cells=len(agreement), exceeds=int(agreement.exceeds_family_threshold.sum()),
                                 max_abs_z=float(agreement.z.abs().max()),
                                 min_retained_per_cell=int(min(agreement.n_lisp.min(), agreement.n_mirror.min())))
        if entry.get("fixations"):
            fix = pd.concat([pd.read_csv(resolve(p)) for p in entry["fixations"]])
            eye_summary(fix, trials).to_csv(out / f"{run}_eyes.csv", index=False)
        ex = []
        for keys, group in trials.groupby(CELLS):
            mu, sigma, tau = fit_exgaussian(group.loc[group.correct & group.rt_eligible, "rt_ms"].to_numpy())
            ex.append(dict(zip(CELLS, keys)) | dict(mu=mu, sigma=sigma, tau=tau))
        pd.DataFrame(ex).to_csv(out / f"{run}_exgaussian.csv", index=False)
        record["runs"].append(row)
    (out / "evaluation.json").write_text(json.dumps(record, indent=2))
    return record


def plot_comparison(cells, destination, title):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    tasks = sorted(cells.task.unique())
    fig, axes = plt.subplots(2, len(tasks), figsize=(5 * len(tasks), 8), squeeze=False)
    for col, task in enumerate(tasks):
        group = cells[cells.task == task]
        for present, style in ((1, "-"), (0, "--")):
            sub = group[group.target_present == present].sort_values("set_size")
            label = "present" if present else "absent"
            for side, color in (("human", "black"), ("model", "tab:blue")):
                axes[0, col].plot(sub.set_size, sub[f"mean_{side}"], style, color=color, marker="o", label=f"{side} {label}")
                axes[0, col].fill_between(sub.set_size, sub[f"mean_lo_{side}"], sub[f"mean_hi_{side}"], color=color, alpha=.12)
            for _, cell in sub.iterrows():
                axes[1, col].plot([cell[f"q{int(q*100)}_human"] for q in QUANTILES],
                                  [cell[f"q{int(q*100)}_model"] for q in QUANTILES], style,
                                  marker="o", label=f"N={cell.set_size} {label}")
        axes[0, col].set(title=task, xlabel="Set size", ylabel="Correct RT (ms)")
        axes[0, col].legend(fontsize=8)
        ax = axes[1, col]
        lo, hi = min(ax.get_xlim()[0], ax.get_ylim()[0]), max(ax.get_xlim()[1], ax.get_ylim()[1])
        ax.plot([lo, hi], [lo, hi], ":", color="gray")
        ax.set(xlabel="Human RT quantile (ms)", ylabel="ACT-R RT quantile (ms)")
        ax.legend(fontsize=7)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(destination, dpi=160)
    plt.close(fig)
