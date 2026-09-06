"""Side-by-side summary of two evaluated runs (refit versus frozen) as Markdown.

Reads the CSVs that ``harness/evaluate.py`` writes for a manifest and prints
the tables that ``docs/RESULTS-REFIT-20260905.md`` reports. Nothing here
simulates or selects; it only formats measured files.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def headline(evaluation: dict, runs: dict) -> str:
    rows = ["| Run | Split | Mean RT RMSE (ms) | Quantile RMSE (ms) | Slopes within 5 ms/item | Largest miss error (points) | Timeouts |",
            "|---|---|---|---|---|---|---|"]
    for run in evaluation["runs"]:
        if run["id"] not in runs:
            continue
        for split, c in run["comparisons"].items():
            rows.append(f"| {runs[run['id']]} | {split} | {c['mean_rt_rmse_ms']:.1f} | {c['mean_quantile_rmse_ms']:.1f} | "
                        f"{c['slopes_pass']}/{c['slopes_total']} | {c['max_miss_difference_points']:.1f} | {c['timeouts']} |")
    return "\n".join(rows)


def slopes(docs: Path, split: str, runs: dict) -> str:
    frames = {label: pd.read_csv(docs / f"{run}_{split}_slopes.csv") for run, label in runs.items()}
    first = next(iter(frames.values()))
    rows = ["| Task | Target | Human slope | " + " | ".join(f"{l} slope" for l in frames) + " | Human intercept | " +
            " | ".join(f"{l} intercept" for l in frames) + " |",
            "|---|---|---|" + "---|" * len(frames) + "---|" + "---|" * len(frames)]
    for _, r in first.iterrows():
        sel = [f[(f.task == r.task) & (f.target_present == r.target_present)].iloc[0] for f in frames.values()]
        rows.append(f"| {r.task} | {'present' if r.target_present else 'absent'} | {r.slope_human:.1f} | " +
                    " | ".join(f"{s.slope_model:.1f}" for s in sel) + f" | {r.intercept_human:.0f} | " +
                    " | ".join(f"{s.intercept_model:.0f}" for s in sel) + " |")
    return "\n".join(rows)


def cells(docs: Path, split: str, runs: dict) -> str:
    frames = {label: pd.read_csv(docs / f"{run}_{split}_cells.csv") for run, label in runs.items()}
    first = next(iter(frames.values()))
    labels = list(frames)
    rows = ["| Task | N | Target | Human mean | " + " | ".join(f"{l} mean" for l in labels) +
            " | Human q10 | " + " | ".join(f"{l} q10" for l in labels) +
            " | Human error % | " + " | ".join(f"{l} error %" for l in labels) +
            " | " + " | ".join(f"{l} quantile RMSE" for l in labels) + " |",
            "|---|---|---|---|" + "---|" * (4 * len(labels) + 2)]
    for _, r in first.sort_values(["task", "set_size", "target_present"]).iterrows():
        sel = [f[(f.task == r.task) & (f.set_size == r.set_size) & (f.target_present == r.target_present)].iloc[0]
               for f in frames.values()]
        rows.append(f"| {r.task} | {r.set_size} | {'present' if r.target_present else 'absent'} | {r.mean_human:.0f} | " +
                    " | ".join(f"{s.mean_model:.0f}" for s in sel) + f" | {r.q10_human:.0f} | " +
                    " | ".join(f"{s.q10_model:.0f}" for s in sel) + f" | {100 * r.error_rate_human:.1f} | " +
                    " | ".join(f"{100 * s.error_rate_model:.1f}" for s in sel) + " | " +
                    " | ".join(f"{s.quantile_rmse_ms:.0f}" for s in sel) + " |")
    return "\n".join(rows)


def false_alarms(docs: Path, split: str, runs: dict) -> str:
    out = []
    for run, label in runs.items():
        f = pd.read_csv(docs / f"{run}_{split}_cells.csv")
        absent = f[f.target_present == 0]
        present = f[f.target_present == 1]
        out.append(f"{label}: mean false-alarm rate {100 * absent.error_rate_model.mean():.2f}% (human {100 * absent.error_rate_human.mean():.2f}%), "
                   f"mean miss rate {100 * present.error_rate_model.mean():.2f}% (human {100 * present.error_rate_human.mean():.2f}%)")
    return "\n".join(out)


def eyes(docs: Path, runs: dict) -> str:
    rows = ["| Run | Task | Fixations per trial | Stationary duration (ms) | Saccade amplitude (deg) | Refixation rate |",
            "|---|---|---|---|---|---|"]
    for run, label in runs.items():
        path = docs / f"{run}_eyes.csv"
        if not path.exists():
            continue
        for _, r in pd.read_csv(path).iterrows():
            rows.append(f"| {label} | {r.task} | {r.mean_count:.2f} | {r.mean_duration_ms:.0f} | {r.mean_amplitude_deg:.1f} | {r.refixation_rate:.3f} |")
    return "\n".join(rows)


def amplitude_split(run_dir: Path, pattern: str, label: str) -> str:
    """First (from the fixation cross) versus later saccade amplitudes, by task."""
    import glob
    from harness.tasks import px2deg
    fix_files = sorted(glob.glob(str(run_dir / pattern)))
    if not fix_files:
        return f"{label}: no fixation logs matching {pattern}"
    fx = pd.concat(pd.read_csv(f).assign(source=i) for i, f in enumerate(fix_files))
    fx = fx[fx.practice == 0] if "practice" in fx else fx
    rows = ["| Run | Task | First saccade (deg) | Later saccades (deg) | Later saccades beyond 11 deg |",
            "|---|---|---|---|---|"]
    for task, g in fx.groupby("task"):
        first, later = [], []
        for _, t in g.groupby(["source", "subject_seed", "trial"]):
            xy = t.sort_values("idx")[["x", "y"]].to_numpy()
            if len(xy) > 1:
                d = [px2deg(float(v)) for v in np.linalg.norm(np.diff(xy, axis=0), axis=1)]
                first.append(d[0])
                later.extend(d[1:])
        later = np.array(later)
        rows.append(f"| {label} | {task} | {np.mean(first):.1f} | {np.mean(later) if len(later) else float('nan'):.1f} | "
                    f"{100 * np.mean(later > 10.98) if len(later) else float('nan'):.0f}% |")
    return "\n".join(rows)


def exgaussian(docs: Path, runs: dict, human_split: str) -> str:
    human = pd.read_csv(docs / f"human_{human_split}_exgaussian.csv")
    hm = human.groupby(["task", "set_size", "target_present"])[["mu", "sigma", "tau"]].mean().reset_index()
    frames = {label: pd.read_csv(docs / f"{run}_exgaussian.csv") for run, label in runs.items()}
    labels = list(frames)
    rows = ["| Task | N | Target | Human mu / sigma / tau | " + " | ".join(f"{l} mu / sigma / tau" for l in labels) + " |",
            "|---|---|---|---|" + "---|" * len(labels)]
    for _, r in hm.sort_values(["task", "set_size", "target_present"]).iterrows():
        sel = [f[(f.task == r.task) & (f.set_size == r.set_size) & (f.target_present == r.target_present)].iloc[0]
               for f in frames.values()]
        rows.append(f"| {r.task} | {r.set_size} | {'present' if r.target_present else 'absent'} | "
                    f"{r.mu:.0f} / {r.sigma:.0f} / {r.tau:.0f} | " +
                    " | ".join(f"{s.mu:.0f} / {s.sigma:.0f} / {s.tau:.0f}" for s in sel) + " |")
    return "\n".join(rows)


def parity(docs: Path, run: str) -> str:
    path = docs / f"{run}_parity.csv"
    if not path.exists():
        return "No mirror comparison for this run."
    p = pd.read_csv(path)
    return (f"{int(p.exceeds_family_threshold.sum())} of {len(p)} search-time means exceed the Bonferroni family threshold; "
            f"maximum |z| = {p.z.abs().max():.2f}; minimum retained trials per cell = {int(min(p.n_lisp.min(), p.n_mirror.min()))}.")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--docs", type=Path, default=ROOT / "docs/validation-refit-20260905")
    ap.add_argument("--runs", nargs="+", default=["refit=Refit", "frozen_shared=Frozen"],
                    help="run_id=Label pairs, first is primary")
    ap.add_argument("--splits", nargs="+", default=["train", "validation", "test"])
    ap.add_argument("--run-dir", type=Path, default=ROOT / "data/model/refit_20260905")
    ap.add_argument("--run-dirs", nargs="*", default=[],
                    help="run_id=directory pairs for runs whose fixation logs live elsewhere")
    args = ap.parse_args()
    runs = dict(pair.split("=", 1) for pair in args.runs)
    run_dirs = {k: Path(v) for k, v in (pair.split("=", 1) for pair in args.run_dirs)}
    evaluation = json.loads((args.docs / "evaluation.json").read_text())
    print("## Headline\n")
    print(headline(evaluation, runs))
    for split in args.splits:
        print(f"\n## Slopes and intercepts: {split}\n")
        print(slopes(args.docs, split, runs))
        print(f"\n## Cells: {split}\n")
        print(cells(args.docs, split, runs))
        print()
        print(false_alarms(args.docs, split, runs))
    print("\n## Eye movements\n")
    print(eyes(args.docs, runs))
    print()
    tables = []
    for run, label in runs.items():
        if run == "frozen_shared":
            tables.append(amplitude_split(args.run_dir.parent / "repair_20260905", "shared_seed40*_fixations.csv", label))
        else:
            tables.append(amplitude_split(run_dirs.get(run, args.run_dir), f"{run}_seed*_fixations.csv", label))
    lines = tables[0].splitlines()
    for t in tables[1:]:
        lines.extend(t.splitlines()[2:])            # rows only; one shared header
    print("\n".join(lines))
    print("\n## Ex-Gaussian shape (test participants)\n")
    print(exgaussian(args.docs, runs, args.splits[-1]))
    print("\n## Implementation agreement\n")
    print(parity(args.docs, next(iter(runs))))


if __name__ == "__main__":
    main()
