"""Reproduce development fits, freeze selection, and run ACT-R validation.

Commands use the repository venv. Test summaries are first accessed by report.py
with --final-test after this driver freezes model selection.
"""
from __future__ import annotations
import argparse
from dataclasses import asdict, replace
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from harness.fit import de_fit, quantile_cost, DE_BOUNDS
from harness.human_data import targets, digest
from harness.parameters import configuration, load, lisp_values, validate
from reference.gs_hybrid import DEFAULTS, run_cells, PHASE1, SHARED_DELTA
from harness.tasks import TASKS, SET_SIZES


def development(out, human, n=30, iterations=4, popsize=3):
    train, validation = targets(human, "train"), targets(human, "validation")
    candidates = {"defaults": DEFAULTS,
                  "historical_shared": replace(DEFAULTS, **SHARED_DELTA)}
    for seed in (201, 202):
        path = out / f"shared_{seed}.json"
        if path.exists():
            candidates[f"shared_{seed}"] = load(path)
        else:
            p, cost, result = de_fit(n_per_cell=n, maxiter=iterations, popsize=popsize,
                                    seed=seed, targets=train)
            path.write_text(json.dumps({"shared": configuration(p) | dict(cost=cost,
                seed=seed, bounds=DE_BOUNDS, n_per_cell=n, maxiter=iterations, popsize=popsize,
                evaluations=int(result.nfev), optimizer_success=bool(result.success),
                message=str(result.message), fit_split="train")}, indent=2))
            candidates[f"shared_{seed}"] = p
    scores = {}
    for name, p in candidates.items():
        costs = [quantile_cost(t, p, 250, seed, validation[t])[0]
                 for seed in (211, 212) for t in TASKS]
        scores[name] = sum(costs) / len(costs)
        print("validation", name, scores[name], flush=True)
    winner = min(scores, key=scores.get)
    selected = {"shared": configuration(candidates[winner])}
    selection = dict(shared_winner=winner, shared_validation_scores=scores,
                     validation_seeds=[211, 212], validation_n_per_cell=250,
                     train_optimizer_seeds=[201, 202], bounds=DE_BOUNDS,
                     human_manifest=json.loads((human / "manifest.json").read_text()))
    (out / "selected.json").write_text(json.dumps(selected, indent=2))
    for task in TASKS:
        options = {"shared": candidates[winner], "historical": replace(DEFAULTS, **PHASE1[task])}
        for seed in (221, 222):
            path = out / f"{task}_{seed}.json"
            if path.exists():
                p = load(path, task)
            else:
                p, cost, result = de_fit(tasks=(task,), n_per_cell=n, maxiter=iterations,
                                         popsize=popsize, seed=seed, targets=train)
                path.write_text(json.dumps({task: configuration(p) | dict(cost=cost, seed=seed,
                    bounds=DE_BOUNDS, n_per_cell=n, maxiter=iterations, popsize=popsize,
                    evaluations=int(result.nfev), optimizer_success=bool(result.success),
                    message=str(result.message), fit_split="train")}, indent=2))
            options[str(seed)] = p
        costs = {name: sum(quantile_cost(task, p, 250, s, validation[task])[0]
                          for s in (231, 232)) / 2 for name, p in options.items()}
        name = min(costs, key=costs.get)
        selected[task] = configuration(options[name])
        overrides = [field for field, value in asdict(options[name]).items()
                     if value != getattr(candidates[winner], field)]
        selection[task] = dict(winner=name, validation_costs=costs,
                               task_specific_overrides=overrides,
                               extra_free_parameters=len(overrides),
                               newly_fitted_parameters=len(DE_BOUNDS) if name in ("221", "222") else 0,
                               optimizer_seeds=[221, 222], validation_seeds=[231, 232])
        (out / "selected.json").write_text(json.dumps(selected, indent=2))
        print("selected", task, name, costs, flush=True)
    selection["model_selection_status"] = "frozen_before_test"
    selection["selected_hash"] = digest(selected)
    (out / "selection.json").write_text(json.dumps(selection, indent=2))


def final_runs(out, n=1000):
    from harness.run_batch import ACTRSession, run_batch
    selection = json.loads((out / "selection.json").read_text())
    selected = json.loads((out / "selected.json").read_text())
    if digest(selected) != selection["selected_hash"]:
        raise ValueError("Selected parameters changed after model selection")
    runs = []
    # Independent final seeds, with at least 2,000 retained trials per cell.
    for name, key, tasks, role in [("unfitted", None, TASKS, "unfitted"),
                                  ("shared", "shared", TASKS, "primary")] + [
                                  (f"task_{t}", t, (t,), "secondary") for t in TASKS]:
        params = DEFAULTS if key is None else load(out / "selected.json", key)
        seeds = (401, 402)
        retained = min(250, n) if role == "unfitted" else n
        entry = dict(id=name, role=role, trials=[f"{name}_seed{s}_trials.csv" for s in seeds],
                     fixations=[f"{name}_seed{s}_fixations.csv" for s in seeds],
                     mirror=[f"{name}_mirror_seed{s}.json" for s in seeds],
                     parameters=configuration(params), seeds=list(seeds), n_per_cell=retained)
        if role == "secondary" and params == load(out / "selected.json", "shared"):
            entry["reuse_shared_simulation"] = True
        runs.append(entry)
    manifest = dict(schema_version=1, human="human", frozen="frozen.json", runs=runs)
    frozen = selection | dict(runs_hash=digest(runs), final_seeds=[401, 402],
        final_n_per_cell_per_seed=n, final_minimum_retained_per_cell=2*n,
        mechanism="Wald-once; noise-free/proximity saccades; bounded guidance quit weights; drain adaptive decisions",
        preprocessing="human/protocol.json", scoring="human/protocol.json",
        test_results_used_for_selection=False)
    for name, value in (("run_manifest.json", manifest), ("frozen.json", frozen)):
        path = out / name
        if path.exists() and json.loads(path.read_text()) != value:
            raise ValueError(f"Refusing to replace frozen manifest: {path}")
        path.write_text(json.dumps(value, indent=2))
    with ACTRSession(log_path=out / "final_lisp.log") as session:
        for entry in runs:
            p = validate(entry["parameters"]["params"])
            for seed in entry["seeds"]:
                trial_path = out / f"{entry['id']}_seed{seed}_trials.csv"
                tasks = TASKS if entry["role"] != "secondary" else (entry["id"].removeprefix("task_"),)
                if entry.get("reuse_shared_simulation"):
                    import pandas as pd
                    for kind in ("trials", "fixations"):
                        df = pd.read_csv(out / f"shared_seed{seed}_{kind}.csv")
                        df[df.task.isin(tasks)].to_csv(out / f"{entry['id']}_seed{seed}_{kind}.csv", index=False)
                    rows = json.loads((out / f"shared_mirror_seed{seed}.json").read_text())
                    (out / f"{entry['id']}_mirror_seed{seed}.json").write_text(json.dumps([r for r in rows if r["task"] in tasks]))
                    continue
                if not trial_path.exists():
                    run_batch(session.actr, tasks, SET_SIZES, entry["n_per_cell"], seed, lisp_values(p), out,
                              entry["id"], session=session)
                mirror = out / f"{entry['id']}_mirror_seed{seed}.json"
                if not mirror.exists():
                    mirror.write_text(json.dumps(run_cells(p, tasks=tasks, n_per_cell=entry["n_per_cell"],
                                                          seed=seed, keep_fixations=True)))
                print("finished", entry["id"], seed, flush=True)


def ablations(out, n=150):
    from harness.run_batch import ACTRSession, run_batch
    variants = {"corrected_defaults": DEFAULTS,
                "extra_recognition": replace(DEFAULTS, recognition_extra=True),
                "old_saccades": replace(DEFAULTS, revised_saccades=False),
                "old_quit_weights": replace(DEFAULTS, quit_noise_free=False),
                "bu3": replace(DEFAULTS, w_bu=3.),
                "step005": replace(DEFAULTS, qt_step=.005)}
    out.mkdir(parents=True, exist_ok=True)
    (out / "configurations.json").write_text(json.dumps({k:configuration(p) for k,p in variants.items()}, indent=2))
    with ACTRSession(log_path=out / "lisp.log") as session:
        for name, p in variants.items():
            for seed in (321, 322):
                run_batch(session.actr, TASKS, SET_SIZES, n, seed, lisp_values(p), out,
                          name, session=session, progress=False)
                (out / f"{name}_mirror_seed{seed}.json").write_text(json.dumps(
                    run_cells(p, n_per_cell=n, seed=seed, keep_fixations=True)))
            print("ablation complete", name, flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stage", choices=["development", "final", "ablations"])
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/repair_20260905")
    ap.add_argument("--human", type=Path)
    ap.add_argument("-n", type=int, help="trials per cell per seed; defaults 30 development / 1000 final")
    ap.add_argument("--iterations", type=int, default=4)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.stage == "development":
        development(args.out, args.human or args.out / "human", args.n or 30, args.iterations)
    elif args.stage == "final":
        final_runs(args.out, args.n or 1000)
    else:
        ablations(args.out / "ablations", args.n or 150)


if __name__ == "__main__":
    main()
