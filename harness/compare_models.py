"""Fit the comparison models and score them next to the ACT-R runs.

Stages, all exploratory (the frozen gs-vision test summaries were inspected on
September 5, before this comparison):

``fit``
    Differential evolution on the training participants for every model in
    ``reference/baselines.py`` that has fitted parameters, with the same
    objective as the gs-vision fits (``harness.fit.quantile_cost``: mean cell
    quantile RMSE plus ten points per percentage point of error-rate
    difference).  ``per_task`` models get one search per task.  Models with no
    fitted parameters are written out at their defaults.
``final``
    Two seeds at 1,000 retained trials per cell per seed for every model, the
    same volume as the ACT-R final runs.
``evaluate``
    Train, validation and test comparisons with ``harness.evaluate.compare``,
    the same cell and slope CSVs and plots as the validation directories, and
    the same headline numbers recomputed for the existing ACT-R runs from
    their own cell CSVs so that all rows of the comparison share one formula.
``report``
    Markdown tables from the evaluation.

The frozen, refit and gs6 run directories are read, never written.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from harness.evaluate import compare, model_frame, plot_comparison, summary  # noqa: E402
from harness.human_data import group_summary, load_split, participant_summary, targets  # noqa: E402
from harness.tasks import TASKS  # noqa: E402
from reference.baselines import MODELS, de_fit, simulate  # noqa: E402

HUMAN = ROOT / "data/model/repair_20260905/human"
SPLITS = ("train", "validation", "test")

# Existing ACT-R runs, scored from the cell CSVs their own evaluations wrote.
EXISTING = {
    "gs_unfitted": dict(docs="docs/validation-20260905", run="unfitted",
                        title="gs-vision, module defaults (ACT-R)", n_fitted=0, actr=True),
    "gs_frozen": dict(docs="docs/validation-20260905", run="shared",
                      title="gs-vision, frozen shared fit (ACT-R)", n_fitted=6, actr=True),
    "gs_refit": dict(docs="docs/validation-refit-20260905", run="refit_trigger_501",
                     title="gs-vision, September 5 refit (ACT-R)", n_fitted=13, actr=True),
    "gs6_defaults": dict(docs="docs/validation-gs6-20260905", run="gs6_defaults",
                         title="gs6-vision, Wolfe's values (ACT-R)", n_fitted=0, actr=True),
    "gs6_posted": dict(docs="docs/validation-gs6-20260905", run="gs6_posted_801",
                       title="gs6-vision, engine posted, spatial layer fitted (ACT-R)", n_fitted=8, actr=True),
    "gs6_fitted": dict(docs="docs/validation-gs6-20260905", run="gs6_fitted_801",
                       title="gs6-vision, engine rates fitted (ACT-R)", n_fitted=16, actr=True),
}
DEFAULT_MODELS = list(MODELS)


def headline(cells: pd.DataFrame, slopes: pd.DataFrame) -> dict:
    present = cells[cells.target_present == 1]
    absent = cells[cells.target_present == 0]
    out = dict(mean_rt_rmse_ms=float(np.sqrt(np.mean(cells.mean_error_ms ** 2))),
               mean_quantile_rmse_ms=float(cells.quantile_rmse_ms.mean()),
               slopes_pass=int(slopes.slope_pass.sum()), slopes_total=int(len(slopes)),
               max_miss_difference_points=float(present.error_diff_points.abs().max()),
               miss_rate_model=float(present.error_rate_model.mean()),
               miss_rate_human=float(present.error_rate_human.mean()),
               fa_rate_model=float(absent.error_rate_model.mean()),
               fa_rate_human=float(absent.error_rate_human.mean()),
               timeouts=int(cells.timeouts.sum()) if "timeouts" in cells else 0)
    for task, group in cells.groupby("task"):
        out[f"quantile_rmse_{task}"] = float(group.quantile_rmse_ms.mean())
    return out


def fit(out: Path, names, n, maxiter, popsize, workers, seed, force=False):
    train = targets(HUMAN, "train")
    for name in names:
        cls = MODELS[name]
        path = out / f"{name}.json"
        if path.exists() and not force:
            print("exists", path, flush=True)
            continue
        record = dict(model=name, title=cls.title, n_fitted=cls.n_fitted(), per_task=cls.per_task,
                      bounds=cls.bounds, defaults=cls.defaults, fit_split="train", seed=seed,
                      n_per_cell=n, maxiter=maxiter, popsize=popsize)
        t0 = time.perf_counter()
        if not cls.bounds:
            record.update(values=dict(cls.defaults), cost=None, evaluations=0, fitted=False)
        elif cls.per_task:
            values, costs, evals = {}, {}, 0
            for task in TASKS:
                v, c, res = de_fit(name, {task: train[task]}, n_per_cell=n, maxiter=maxiter,
                                   popsize=popsize, seed=seed, workers=workers, tasks=(task,))
                values[task], costs[task], evals = v, c, evals + int(res.nfev)
                print("fit", name, task, round(c, 1), flush=True)
            record.update(values=values, cost=float(np.mean(list(costs.values()))), cost_by_task=costs,
                          evaluations=evals, fitted=True)
        else:
            v, c, res = de_fit(name, train, n_per_cell=n, maxiter=maxiter, popsize=popsize,
                               seed=seed, workers=workers)
            record.update(values=v, cost=c, evaluations=int(res.nfev), fitted=True,
                          optimizer_message=str(res.message))
        record["seconds"] = time.perf_counter() - t0
        path.write_text(json.dumps(record, indent=2))
        print("fit", name, record["cost"], f"{record['seconds']:.0f}s", flush=True)


def load_model(out: Path, name: str):
    record = json.loads((out / f"{name}.json").read_text())
    return MODELS[name](record["values"]), record


def final(out: Path, names, n, seeds):
    for name in names:
        model, _ = load_model(out, name)
        for seed in seeds:
            path = out / f"{name}_mirror_seed{seed}.json"
            if path.exists():
                continue
            t0 = time.perf_counter()
            rows = simulate(model, n_per_cell=n, seed=seed)
            path.write_text(json.dumps(rows))
            print("final", name, seed, len(rows), f"{time.perf_counter() - t0:.0f}s", flush=True)


def human_summaries(docs: Path) -> dict:
    humans = {}
    for split in SPLITS:
        df, _ = load_split(HUMAN, split)
        humans[split] = group_summary(participant_summary(df))
        humans[split].to_csv(docs / f"human_{split}.csv", index=False)
    return humans


def evaluate(out: Path, docs: Path, names, seeds):
    docs.mkdir(parents=True, exist_ok=True)
    humans = human_summaries(docs)
    record = dict(human=str(HUMAN), seeds=list(seeds), runs=[])
    for name in names:
        model, meta = load_model(out, name)
        paths = [out / f"{name}_mirror_seed{s}.json" for s in seeds]
        trials = model_frame(paths, mirror=True)
        current = summary(trials)
        current.to_csv(docs / f"{name}_model.csv", index=False)
        row = dict(id=name, title=meta["title"], n_fitted=meta["n_fitted"], actr=False,
                   values=meta["values"], train_cost=meta.get("cost"), comparisons={})
        for split, human in humans.items():
            cells, slopes = compare(human, current)
            cells.to_csv(docs / f"{name}_{split}_cells.csv", index=False)
            slopes.to_csv(docs / f"{name}_{split}_slopes.csv", index=False)
            row["comparisons"][split] = headline(cells, slopes)
            plot_comparison(cells, docs / f"{name}_{split}.png", f"{meta['title']}: {split} participants")
        record["runs"].append(row)
        print(name, {s: round(c["mean_quantile_rmse_ms"], 1) for s, c in row["comparisons"].items()}, flush=True)
    for name, info in EXISTING.items():
        row = dict(id=name, title=info["title"], n_fitted=info["n_fitted"], actr=True,
                   source=info["docs"], source_run=info["run"], comparisons={})
        for split in SPLITS:
            base = ROOT / info["docs"] / f"{info['run']}_{split}"
            cells = pd.read_csv(base.with_name(base.name + "_cells.csv"))
            slopes = pd.read_csv(base.with_name(base.name + "_slopes.csv"))
            row["comparisons"][split] = headline(cells, slopes)
        record["runs"].append(row)
    (docs / "evaluation.json").write_text(json.dumps(record, indent=2))
    return record


def _cells_path(docs: Path, run: dict, split: str) -> Path:
    if run["actr"]:
        return ROOT / run["source"] / f"{run['source_run']}_{split}_cells.csv"
    return docs / f"{run['id']}_{split}_cells.csv"


def _slopes_path(docs: Path, run: dict, split: str) -> Path:
    return _cells_path(docs, run, split).with_name(_cells_path(docs, run, split).name.replace("_cells", "_slopes"))


def report(docs: Path, order=None) -> str:
    record = json.loads((docs / "evaluation.json").read_text())
    runs = {r["id"]: r for r in record["runs"]}
    order = order or sorted(runs, key=lambda k: runs[k]["comparisons"]["test"]["mean_quantile_rmse_ms"])
    lines = []
    for split in SPLITS:
        lines += [f"## Headline: {split} participants", "",
                  "| Model | In ACT-R | Fitted params | Mean RT RMSE (ms) | Quantile RMSE (ms) | feature | conjunction | spatial | Slopes within 5 ms/item | Largest miss error (points) | Miss % (human) | FA % (human) |",
                  "|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for k in sorted(order, key=lambda k: runs[k]["comparisons"][split]["mean_quantile_rmse_ms"]):
            r, c = runs[k], runs[k]["comparisons"][split]
            lines.append(f"| {r['title']} | {'yes' if r['actr'] else 'no'} | {r['n_fitted']} | {c['mean_rt_rmse_ms']:.1f} | "
                         f"**{c['mean_quantile_rmse_ms']:.1f}** | {c['quantile_rmse_feature']:.0f} | {c['quantile_rmse_conjunction']:.0f} | "
                         f"{c['quantile_rmse_spatial']:.0f} | {c['slopes_pass']}/{c['slopes_total']} | {c['max_miss_difference_points']:.1f} | "
                         f"{100 * c['miss_rate_model']:.1f} ({100 * c['miss_rate_human']:.1f}) | "
                         f"{100 * c['fa_rate_model']:.2f} ({100 * c['fa_rate_human']:.2f}) |")
        lines.append("")
    lines += ["## Slopes and intercepts: test participants", ""]
    frames = {k: pd.read_csv(_slopes_path(docs, runs[k], "test")) for k in order}
    first = next(iter(frames.values()))
    lines += ["| Task | Target | Human | " + " | ".join(runs[k]["title"] for k in order) + " |",
              "|---|---|---|" + "---|" * len(order)]
    for _, r in first.iterrows():
        sel = [f[(f.task == r.task) & (f.target_present == r.target_present)].iloc[0] for f in frames.values()]
        lines.append(f"| {r.task} | {'present' if r.target_present else 'absent'} | {r.slope_human:.1f} / {r.intercept_human:.0f} | " +
                     " | ".join(f"{s.slope_model:.1f} / {s.intercept_model:.0f}" for s in sel) + " |")
    lines += ["", "Slope in ms/item / intercept in ms.", "", "## Present-trial error by set size: test participants", ""]
    cframes = {k: pd.read_csv(_cells_path(docs, runs[k], "test")) for k in order}
    lines += ["| Task | N | Human miss % | " + " | ".join(runs[k]["title"] for k in order) + " |",
              "|---|---|---|" + "---|" * len(order)]
    hc = next(iter(cframes.values()))
    for _, r in hc[hc.target_present == 1].sort_values(["task", "set_size"]).iterrows():
        sel = [f[(f.task == r.task) & (f.set_size == r.set_size) & (f.target_present == 1)].iloc[0] for f in cframes.values()]
        lines.append(f"| {r.task} | {r.set_size} | {100 * r.error_rate_human:.1f} | " +
                     " | ".join(f"{100 * s.error_rate_model:.1f}" for s in sel) + " |")
    lines += ["", "## Fitted values", ""]
    for k in order:
        r = runs[k]
        if r["actr"] or "values" not in r:
            continue
        v = r["values"]
        if isinstance(next(iter(v.values())), dict):
            body = "; ".join(f"{t}: " + ", ".join(f"{n}={x:.4g}" for n, x in tv.items()) for t, tv in v.items())
        else:
            body = ", ".join(f"{n}={x:.4g}" for n, x in v.items())
        lines.append(f"- **{r['title']}** (training cost {r['train_cost'] if r['train_cost'] is None else round(r['train_cost'], 1)}): {body}")
    text = "\n".join(lines) + "\n"
    (docs / "REPORT-TABLES.md").write_text(text)
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stage", choices=["fit", "final", "evaluate", "report", "all"])
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/comparison_20260906")
    ap.add_argument("--docs", type=Path, default=ROOT / "docs/validation-comparison-20260906")
    ap.add_argument("--models", nargs="*", default=DEFAULT_MODELS)
    ap.add_argument("-n", type=int, default=200, help="trials per cell for the fit")
    ap.add_argument("--final-n", type=int, default=1000)
    ap.add_argument("--maxiter", type=int, default=60)
    ap.add_argument("--popsize", type=int, default=8)
    ap.add_argument("--workers", type=int, default=14)
    ap.add_argument("--seed", type=int, default=1001)
    ap.add_argument("--seeds", type=int, nargs="*", default=[1101, 1102])
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.stage in ("fit", "all"):
        fit(args.out, args.models, args.n, args.maxiter, args.popsize, args.workers, args.seed, args.force)
    if args.stage in ("final", "all"):
        final(args.out, args.models, args.final_n, args.seeds)
    if args.stage in ("evaluate", "all"):
        evaluate(args.out, args.docs, args.models, args.seeds)
    if args.stage in ("report", "all"):
        print(report(args.docs))


if __name__ == "__main__":
    main()
