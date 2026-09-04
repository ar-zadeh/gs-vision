"""Turn the batch CSVs into the numbers and plots that RESULTS.md reports.

Handoff section 8.3.  Reads whatever ``run_batch.py`` wrote (or, with
``--hybrid``, runs ``reference/gs_hybrid.py`` and analyses that instead, which
is how the Python and Lisp sides are compared cell by cell).

Produces:

* slope and intercept per task and presence, by least squares on the cell
  means, and the target-absent to target-present slope ratio;
* the .1/.3/.5/.7/.9 RT quantiles per cell;
* ex-Gaussian mu, sigma and tau per cell by maximum likelihood;
* miss and false-alarm rate by set size;
* fixation count, duration, saccade amplitude and refixation rate;
* RT by set size, quantile-probability and fixation-count plots.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys

import numpy as np
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from harness.tasks import SET_SIZES, TASKS, px2deg     # noqa: E402

QUANTILES = (0.1, 0.3, 0.5, 0.7, 0.9)


# --------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------

def load_trials(path) -> pd.DataFrame:
    df = pd.read_csv(path)
    df = df[df["rt_ms"].notna()].copy()
    df["rt_ms"] = df["rt_ms"].astype(float)
    df["correct"] = df["correct"].astype(int).astype(bool)
    df["target_present"] = df["target_present"].astype(int).astype(bool)
    return df


def hybrid_frame(n_per_cell: int = 400, seed: int = 0, params=None) -> pd.DataFrame:
    from reference.gs_hybrid import DEFAULTS, run_cells
    rows = run_cells(params or DEFAULTS, n_per_cell=n_per_cell, seed=seed)
    df = pd.DataFrame(rows)
    df["rt_ms"] = df["rt"] * 1000.0
    return df


# --------------------------------------------------------------------------
# Statistics
# --------------------------------------------------------------------------

def cell_means(df: pd.DataFrame) -> pd.DataFrame:
    ok = df[df["correct"]]
    g = ok.groupby(["task", "set_size", "target_present"])["rt_ms"]
    out = g.agg(["mean", "std", "count"]).reset_index()
    err = (df.groupby(["task", "set_size", "target_present"])["correct"]
             .apply(lambda s: 1.0 - s.mean()).reset_index(name="error_rate"))
    return out.merge(err, on=["task", "set_size", "target_present"])


def slopes(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    cm = cell_means(df)
    for task in sorted(df["task"].unique()):
        rec = {"task": task}
        for present, key in ((True, "tp"), (False, "ta")):
            sub = cm[(cm["task"] == task) & (cm["target_present"] == present)]
            if len(sub) >= 2:
                s, i = np.polyfit(sub["set_size"].astype(float), sub["mean"], 1)
            else:
                s = i = float("nan")
            rec[f"{key}_slope"] = float(s)
            rec[f"{key}_intercept"] = float(i)
        rec["ratio"] = (rec["ta_slope"] / rec["tp_slope"]
                        if rec["tp_slope"] else float("nan"))
        rows.append(rec)
    return pd.DataFrame(rows)


def quantile_table(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    ok = df[df["correct"]]
    for (task, n, present), sub in ok.groupby(["task", "set_size", "target_present"]):
        q = np.quantile(sub["rt_ms"], QUANTILES) if len(sub) >= 5 else [np.nan] * 5
        rows.append(dict(task=task, set_size=n, target_present=present, n=len(sub),
                         **{f"q{int(p*100)}": v for p, v in zip(QUANTILES, q)}))
    return pd.DataFrame(rows).sort_values(["task", "target_present", "set_size"])


# --- ex-Gaussian -----------------------------------------------------------

def _exgauss_nll(theta, x):
    mu, sigma, tau = theta
    if sigma <= 0 or tau <= 0:
        return 1e12
    from scipy.special import log_ndtr
    z = (x - mu) / sigma - sigma / tau
    ll = -math.log(tau) - (x - mu) / tau + sigma ** 2 / (2 * tau ** 2) + log_ndtr(z)
    if not np.all(np.isfinite(ll)):
        return 1e12
    return -float(np.sum(ll))


def fit_exgaussian(x) -> tuple:
    """Maximum-likelihood mu, sigma, tau.  Returns NaNs if it will not fit."""
    from scipy.optimize import minimize
    x = np.asarray(x, float)
    if len(x) < 20:
        return (float("nan"),) * 3
    m, s = x.mean(), x.std(ddof=1)
    start = [m - 0.6 * s, max(1.0, 0.6 * s), max(1.0, 0.6 * s)]
    res = minimize(_exgauss_nll, start, args=(x,), method="Nelder-Mead",
                   options={"maxiter": 4000, "xatol": 1e-3, "fatol": 1e-3})
    if not res.success and res.fun >= 1e11:
        return (float("nan"),) * 3
    return tuple(float(v) for v in res.x)


def exgaussian_table(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    ok = df[df["correct"]]
    for (task, n, present), sub in ok.groupby(["task", "set_size", "target_present"]):
        mu, sigma, tau = fit_exgaussian(sub["rt_ms"].to_numpy())
        rows.append(dict(task=task, set_size=n, target_present=present,
                         n=len(sub), mu=mu, sigma=sigma, tau=tau))
    return pd.DataFrame(rows).sort_values(["task", "target_present", "set_size"])


def error_table(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (task, n, present), sub in df.groupby(["task", "set_size", "target_present"]):
        rows.append(dict(task=task, set_size=n, target_present=present,
                         n=len(sub), error_rate=1.0 - sub["correct"].mean()))
    out = pd.DataFrame(rows)
    out["kind"] = np.where(out["target_present"], "miss", "false_alarm")
    return out.sort_values(["task", "kind", "set_size"])


# --- fixations -------------------------------------------------------------

def fixation_stats(fix_path, trials: pd.DataFrame | None = None) -> dict:
    """Counts, durations, saccade amplitudes and refixation rate."""
    fx = pd.read_csv(fix_path)
    if fx.empty:
        return {}
    per_trial = fx.groupby("trial").size()
    amps, refix = [], 0
    for _trial, sub in fx.groupby("trial"):
        sub = sub.sort_values("idx")
        xy = sub[["x", "y"]].to_numpy()
        if len(xy) > 1:
            d = np.hypot(*(xy[1:] - xy[:-1]).T)
            amps.extend(px2deg(v) for v in d)
            # a refixation is a landing within 1 degree of an earlier one
            for i in range(1, len(xy)):
                if any(px2deg(float(np.hypot(*(xy[i] - xy[j])))) < 1.0
                       for j in range(i)):
                    refix += 1
    out = {
        "mean_fixations_per_trial": float(per_trial.mean()),
        "mean_fixation_duration_ms": float(fx["dur"].mean()),
        "median_fixation_duration_ms": float(fx["dur"].median()),
        "mean_saccade_amplitude_deg": float(np.mean(amps)) if amps else float("nan"),
        "refixation_rate": refix / len(fx),
        "n_fixations": int(len(fx)),
    }
    if trials is not None and "n_fixations" in trials:
        by_n = trials.groupby(["task", "set_size", "target_present"])["n_fixations"].mean()
        out["fixations_by_cell"] = {str(k): float(v) for k, v in by_n.items()}
    return out


# --------------------------------------------------------------------------
# Plots
# --------------------------------------------------------------------------

def make_plots(df: pd.DataFrame, out_dir: pathlib.Path, human: dict | None = None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out_dir.mkdir(parents=True, exist_ok=True)
    cm = cell_means(df)
    tasks = sorted(df["task"].unique())

    fig, axes = plt.subplots(1, len(tasks), figsize=(4.2 * len(tasks), 3.6), sharey=True)
    axes = np.atleast_1d(axes)
    for ax, task in zip(axes, tasks):
        for present, style, label in ((True, "-o", "target present"),
                                      (False, "--s", "target absent")):
            sub = cm[(cm["task"] == task) & (cm["target_present"] == present)]
            ax.plot(sub["set_size"], sub["mean"], style, label=f"model, {label}")
        if human and task in human:
            for present, key, style in ((True, "tp", ":^"), (False, "ta", ":v")):
                s, i = human[task][key]
                xs = np.array(SET_SIZES, float)
                ax.plot(xs, i + s * xs, style, color="grey",
                        label=f"human, {'present' if present else 'absent'}")
        ax.set_title(task)
        ax.set_xlabel("set size")
    axes[0].set_ylabel("mean correct RT (ms)")
    axes[-1].legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(out_dir / "rt_by_set_size.png", dpi=140)
    plt.close(fig)

    # quantile-probability: quantiles against the proportion correct
    fig, axes = plt.subplots(1, len(tasks), figsize=(4.2 * len(tasks), 3.6), sharey=True)
    axes = np.atleast_1d(axes)
    qt = quantile_table(df)
    er = error_table(df)
    for ax, task in zip(axes, tasks):
        for present, marker in ((True, "o"), (False, "s")):
            for n in sorted(df["set_size"].unique()):
                row = qt[(qt.task == task) & (qt.set_size == n)
                         & (qt.target_present == present)]
                e = er[(er.task == task) & (er.set_size == n)
                       & (er.target_present == present)]
                if row.empty or e.empty:
                    continue
                p = 1.0 - float(e["error_rate"].iloc[0])
                ax.plot([p] * 5, [row[f"q{int(q*100)}"].iloc[0] for q in QUANTILES],
                        marker, ms=3, color="C0" if present else "C1")
        ax.set_title(task)
        ax.set_xlabel("proportion correct")
    axes[0].set_ylabel("RT quantile (ms)")
    fig.tight_layout()
    fig.savefig(out_dir / "quantile_probability.png", dpi=140)
    plt.close(fig)

    if "n_fixations" in df:
        fig, axes = plt.subplots(1, len(tasks), figsize=(4.2 * len(tasks), 3.2), sharey=True)
        axes = np.atleast_1d(axes)
        for ax, task in zip(axes, tasks):
            sub = df[df["task"] == task]
            ax.hist(sub["n_fixations"], bins=range(0, 31), color="C0")
            ax.set_title(task)
            ax.set_xlabel("fixations per trial")
        axes[0].set_ylabel("trials")
        fig.tight_layout()
        fig.savefig(out_dir / "fixation_counts.png", dpi=140)
        plt.close(fig)


# --------------------------------------------------------------------------

def compare_lisp_python(trials_csv, task: str, param_delta: dict | None = None,
                        n_per_cell: int = 400, seed: int = 0) -> pd.DataFrame:
    """Cell-by-cell agreement between the Lisp module and its Python mirror.

    Phase 4's criterion: the two must agree within Monte Carlo error at the
    same parameters.  A disagreement larger than that means the port is wrong,
    not the fit (handoff section 8.4).  The standard error of each cell mean is
    reported alongside the difference so "within Monte Carlo error" is a
    number the reader can check rather than a claim.
    """
    from dataclasses import replace
    from reference.gs_hybrid import DEFAULTS, run_cells

    lisp = load_trials(trials_csv)
    params = replace(DEFAULTS, **(param_delta or {}))
    py = pd.DataFrame(run_cells(params, tasks=(task,), n_per_cell=n_per_cell, seed=seed))
    py["rt_ms"] = py["rt"] * 1000.0

    rows = []
    for n in sorted(lisp["set_size"].unique()):
        for present in (True, False):
            def _cell(df):
                sub = df[(df["set_size"] == n) & (df["target_present"] == present)
                         & (df["correct"])]
                if sub.empty:
                    return float("nan"), float("nan"), 0
                return (float(sub["rt_ms"].mean()),
                        float(sub["rt_ms"].std(ddof=1) / max(1, len(sub)) ** 0.5),
                        len(sub))
            lm, lse, ln = _cell(lisp)
            pm, pse, pn = _cell(py)
            diff = lm - pm
            se = float(np.hypot(lse, pse))
            rows.append(dict(task=task, set_size=n, target_present=present,
                             lisp_mean=lm, lisp_n=ln, python_mean=pm, python_n=pn,
                             difference=diff, joint_se=se,
                             z=diff / se if se else float("nan")))
    return pd.DataFrame(rows)


def summarise(df: pd.DataFrame, fix_path=None) -> dict:
    out = {
        "n_trials": int(len(df)),
        "slopes": slopes(df).to_dict("records"),
        "cell_means": cell_means(df).to_dict("records"),
        "quantiles": quantile_table(df).to_dict("records"),
        "exgaussian": exgaussian_table(df).to_dict("records"),
        "errors": error_table(df).to_dict("records"),
    }
    if fix_path and pathlib.Path(fix_path).exists():
        out["fixations"] = fixation_stats(fix_path, df)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("trials", nargs="?", help="trial CSV from run_batch.py")
    ap.add_argument("--fixations", default=None)
    ap.add_argument("--hybrid", action="store_true",
                    help="analyse reference/gs_hybrid.py instead of a CSV")
    ap.add_argument("-n", "--n-per-cell", type=int, default=400)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--plots", default=str(ROOT / "data" / "model" / "plots"))
    ap.add_argument("-o", "--out", default=None)
    ap.add_argument("--compare", metavar="TASK",
                    help="also compare the given task's cells with gs_hybrid.py")
    ap.add_argument("--compare-params", default=None,
                    help="fit.json holding the parameter delta used for the run")
    ap.add_argument("--compare-key", default=None)
    args = ap.parse_args()

    if args.hybrid:
        df = hybrid_frame(args.n_per_cell, args.seed)
        fix = None
    else:
        if not args.trials:
            ap.error("give a trial CSV or --hybrid")
        df = load_trials(args.trials)
        fix = args.fixations or str(args.trials).replace("_trials.csv", "_fixations.csv")

    res = summarise(df, fix)
    from harness.fit import TIER1_SLOPES, TIER1_INTERCEPTS
    human = {t: {"tp": (TIER1_SLOPES[t][0], TIER1_INTERCEPTS[t][0]),
                 "ta": (TIER1_SLOPES[t][1], TIER1_INTERCEPTS[t][1])}
             for t in TASKS}
    make_plots(df, pathlib.Path(args.plots), human)

    print(slopes(df).to_string(index=False, float_format=lambda v: f"{v:8.1f}"))
    print()
    print(error_table(df).to_string(index=False, float_format=lambda v: f"{v:6.3f}"))
    if "fixations" in res:
        print()
        for k, v in res["fixations"].items():
            if not isinstance(v, dict):
                print(f"{k:32s} {v}")

    if args.compare:
        delta = {}
        if args.compare_params:
            key = args.compare_key or args.compare
            delta = json.loads(pathlib.Path(args.compare_params).read_text())                .get(key, {}).get("delta", {})
        cmp = compare_lisp_python(args.trials, args.compare, delta,
                                  n_per_cell=args.n_per_cell, seed=args.seed)
        print("
Lisp vs Python mirror, correct-trial cell means (ms)")
        print(cmp.to_string(index=False, float_format=lambda v: f"{v:9.1f}"))
        res["lisp_vs_python"] = cmp.to_dict("records")

    if args.out:
        pathlib.Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(args.out).write_text(json.dumps(res, indent=2, default=str))
        print("\nwrote", args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
