"""Controlled mechanism, capture, priming, and prevalence experiments.

All results here are simulation experiments. Capture uses an orientation-target
analogue of Adam et al., and the unknown-color priming protocol is a model
hypothesis. Neither is labeled an exact human experiment replication.
"""
from __future__ import annotations
import argparse
from dataclasses import replace
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from reference.gs_hybrid import DEFAULTS, GSHybrid, run_cells, run_singleton, run_prevalence
from harness.parameters import configuration, load
from harness.tasks import make_display
from harness.evaluate import model_frame, eye_summary


def priming(params, seed, n=2000, known_template=False):
    model, rng = GSHybrid(params, seed=seed), np.random.default_rng(seed+700)
    rows, previous, color, remaining = [], None, "red", 0
    for i in range(n+100):
        if remaining == 0:
            color = "green" if color == "red" else "red"
            remaining = int(rng.integers(1, 5))
        remaining -= 1
        display = make_display("feature", 12, bool(rng.random() < .5), rng, target_color=color)
        if known_template:
            template = {"color": color}
        else:
            # Identity remains shape-only; the upcoming guiding color is hidden.
            display.items = [replace(it, shape="two" if it.is_target else "five") for it in display.items]
            template = {"shape": "two"}
        row = model.run_trial(display, template=template)
        row.update(subject_seed=seed, trial=i, color_repeat=previous == color,
                   target_color=color, protocol="known_color" if known_template else "unknown_color")
        previous = color
        row.pop("events", None)
        row.pop("fixations", None)
        if i >= 100:
            rows.append(row)
    return rows


def contrasts(df, condition):
    """Seed-level condition contrasts, with a seed bootstrap CI."""
    diffs = []
    for seed, group in df[df.correct & df.target_present].groupby("subject_seed"):
        means = group.groupby(condition).rt.mean() * 1000
        if len(means) == 2:
            diffs.append(float(means.loc[True] - means.loc[False]))
    rng = np.random.default_rng(7001)
    ci = np.mean(rng.choice(diffs, (4000, len(diffs))), axis=1) if diffs else [np.nan]
    return dict(difference_true_minus_false_ms=float(np.mean(diffs)),
                lo=float(np.quantile(ci, .025)), hi=float(np.quantile(ci, .975)),
                seed_contrasts=diffs, counts=df.groupby(condition).size().to_dict())


def run(out, params, n=2000):
    out.mkdir(parents=True, exist_ok=True)
    result = dict(parameters=configuration(params), seeds=[301, 302, 303], synthetic_practice=100,
                  retained_trials_per_seed=n, experiments={})
    for mode in ("known", "unknown", "unknown_no_history"):
        rows = [r for seed in (301, 302, 303) for r in priming(
            replace(params, w_h=0) if mode == "unknown_no_history" else params,
            seed, n=n, known_template=mode == "known")]
        df = pd.DataFrame(rows)
        df.to_csv(out / f"priming_{mode}.csv", index=False)
        result["experiments"][mode] = contrasts(df, "color_repeat")
        # Repeat benefit is switch minus repeat, so invert this signed contrast.
        print(mode, result["experiments"][mode], flush=True)
    prev_rows = []
    for prevalence in (.1, .5):
        for seed in (301, 302, 303):
            rows = run_prevalence(params, task="conjunction", prevalence=prevalence,
                                  n_trials=n+1000, seed=seed, burn_in=1000/(n+1000))
            for r in rows:
                r.update(subject_seed=seed)
                r.pop("events", None)
                r.pop("fixations", None)
            prev_rows.extend(rows)
    df = pd.DataFrame(prev_rows)
    df.to_csv(out / "prevalence.csv", index=False)
    result["experiments"]["prevalence"] = [dict(prevalence=p, seed=s,
        miss_rate=float((~g[g.target_present].correct).mean()),
        absent_rt_ms=float(g[~g.target_present & g.correct].rt.mean()*1000),
        present_trials=int(g.target_present.sum()), final_qt=float(g.qt_scale.iloc[-1]))
        for (p,s),g in df.groupby(["prevalence", "subject_seed"])]
    capture = []
    for weight in sorted(set((.5, 3., params.w_bu))):
        rows = []
        for seed in (301, 302, 303):
            block = run_singleton(replace(params, w_bu=weight), n_trials=n+100, seed=seed,
                                  burn_in=100/(n+100))
            for r in block:
                r.update(subject_seed=seed)
                r.pop("events", None)
                r.pop("fixations", None)
            rows.extend(block)
        df = pd.DataFrame(rows)
        df.to_csv(out / f"capture_w{weight:.3f}.csv", index=False)
        capture.append(dict(w_bu=weight, **contrasts(df, "distractor_present")))
    result["experiments"]["capture"] = capture
    human = pd.read_csv(ROOT / "data/human/adam2021/aggregate_long/Search_1c_agg_long.csv")
    delta = human.groupby(["subject", "distractor"]).rt.mean().unstack()
    values = delta["present"] - delta["absent"]
    rng = np.random.default_rng(7002)
    boot = rng.choice(values, (4000,len(values))).mean(axis=1)
    result["capture_human"] = dict(source="Search_1c_agg_long.csv", participants=len(values),
        mean_cost_ms=float(values.mean()), lo=float(np.quantile(boot,.025)), hi=float(np.quantile(boot,.975)),
        interpretation="analogue comparison only: human shape target, model orientation target; weight sweep is calibration")
    # Reassess the controller step at fixed settings; keep trajectories for diagnosis.
    for step in (.05, .005):
        rows = []
        for seed in (311,312,313):
            block = run_cells(replace(params, qt_step=step), n_per_cell=100, seed=seed)
            rows.extend(block)
        pd.DataFrame(rows).to_csv(out / f"threshold_step_{step}.csv", index=False)
    (out / "experiments.json").write_text(json.dumps(result, indent=2, default=str))
    plot_prevalence(pd.DataFrame(prev_rows), out / "prevalence.png")
    return result


def plot_prevalence(df, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 1, figsize=(10, 7))
    for (prevalence, seed), block in df.groupby(["prevalence", "subject_seed"]):
        axes[0].plot(np.arange(len(block)), block.qt_scale.to_numpy(), alpha=.7, label=f"p={prevalence}, seed={seed}")
        miss = (~block.correct).where(block.target_present)
        axes[1].plot(np.arange(len(block)), miss.rolling(300, min_periods=30).mean().to_numpy(), alpha=.7)
    axes[0].set(ylabel="Adaptive threshold scale")
    axes[1].set(ylabel="Rolling miss rate", xlabel="Retained trial after 1,000 practice trials")
    axes[0].legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--params", type=Path)
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/repair_20260905/experiments")
    ap.add_argument("-n", type=int, default=2000)
    args = ap.parse_args()
    run(args.out, load(args.params) if args.params else DEFAULTS, args.n)


if __name__ == "__main__":
    main()
