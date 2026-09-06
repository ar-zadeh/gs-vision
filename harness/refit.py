"""Post-freeze refit (September 5, 2026): wider parameter set, larger optimizer budget.

The frozen September 5 selection (docs/validation-20260905) is left untouched.
This driver fits the expanded parameter set of ``harness.fit.DE_BOUNDS_REFIT``
on the training participants with the Python mirror, selects among candidates
on the validation participants with fresh seeds, runs the selected candidate
in ACT-R, and evaluates it on all three splits.

The test participants' summaries for the frozen model were inspected before
this refit began, so every result written here is labeled exploratory even
though this round's own selection is made before its test evaluation.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from harness.fit import de_fit, quantile_cost, DE_BOUNDS_REFIT          # noqa: E402
from harness.human_data import targets, digest                         # noqa: E402
from harness.parameters import configuration, load, lisp_values, validate  # noqa: E402
from harness.tasks import TASKS, SET_SIZES                              # noqa: E402
from reference.gs_hybrid import DEFAULTS, run_cells                     # noqa: E402

FROZEN_DIR = ROOT / "data/model/repair_20260905"
FROZEN_SELECTED = ROOT / "docs/validation-20260905/selected.json"
# The two policy switches are on for every refit candidate; everything else
# starts from the module defaults and is either fitted or left at its default.
BASE = replace(DEFAULTS, adaptive_quit_delta=True, explore_proximity=True)
# Two bases are fitted: the exploration rule alone, and the exploration rule
# with a 6 degree saccade trigger (the eye moves once nothing selectable is
# closer than that).  Validation decides between them; amplitude is not in
# the objective, so the trigger has to earn its place on RT and errors.
BASES = {"explore": BASE, "trigger": replace(BASE, saccade_trigger=6.0)}
EXPLORATORY_NOTE = ("Test summaries of the frozen September 5 model were inspected before this refit. "
                    "This round selects before its own test evaluation, but the round is exploratory.")


def fit(out, human, n, iterations, popsize, workers, seeds, base_name):
    from dataclasses import asdict
    base = BASES[base_name]
    switches = {k: v for k, v in asdict(base).items() if v != getattr(DEFAULTS, k)}
    train = targets(human, "train")
    for seed in seeds:
        path = out / f"refit_{base_name}_{seed}.json"
        if path.exists():
            print("exists", path, flush=True)
            continue
        p, cost, res = de_fit(n_per_cell=n, maxiter=iterations, popsize=popsize, seed=seed,
                              targets=train, base=base, bounds=DE_BOUNDS_REFIT, workers=workers)
        path.write_text(json.dumps({"refit": configuration(p) | dict(
            cost=cost, seed=seed, base=base_name, base_switches=switches, bounds=DE_BOUNDS_REFIT,
            n_per_cell=n, maxiter=iterations, popsize=popsize, workers=workers,
            evaluations=int(res.nfev), optimizer_success=bool(res.success),
            message=str(res.message), fit_split="train")}, indent=2))
        print("fit", base_name, seed, cost, flush=True)


def select(out, human, n, seeds):
    validation = targets(human, "validation")
    candidates = {"defaults": DEFAULTS,
                  "frozen_shared": load(FROZEN_SELECTED, "shared")}
    for path in sorted(out.glob("refit_*.json")):
        candidates[path.stem] = load(path, "refit")
    scores, per_task = {}, {}
    for name, p in candidates.items():
        costs = {t: [quantile_cost(t, p, n, s, validation[t])[0] for s in seeds] for t in TASKS}
        per_task[name] = {t: sum(v) / len(v) for t, v in costs.items()}
        scores[name] = sum(per_task[name].values()) / len(TASKS)
        print("validation", name, round(scores[name], 1),
              {t: round(v, 1) for t, v in per_task[name].items()}, flush=True)
    winner = min(scores, key=scores.get)
    selected = {"refit": configuration(candidates[winner])}
    (out / "selected.json").write_text(json.dumps(selected, indent=2))
    selection = dict(winner=winner, validation_scores=scores, validation_scores_by_task=per_task,
                     validation_seeds=list(seeds), validation_n_per_cell=n, bounds=DE_BOUNDS_REFIT,
                     candidates=sorted(candidates), selected_hash=digest(selected),
                     model_selection_status="frozen_before_test", exploratory=EXPLORATORY_NOTE,
                     human_manifest=json.loads((human / "manifest.json").read_text()))
    (out / "selection.json").write_text(json.dumps(selection, indent=2))
    print("selected", winner, flush=True)


def final(out, n, seeds, candidates):
    """Run every named candidate in ACT-R (and the mirror) next to the frozen baseline.

    ``candidates`` are fit-file stems such as ``refit_explore_501``.  Every
    candidate is run whatever the validation selection chose, so that the
    comparison on each split is like for like; ``selection.json`` records
    which one validation would have picked.
    """
    from harness.run_batch import ACTRSession, run_batch
    selection = json.loads((out / "selection.json").read_text())
    selected = json.loads((out / "selected.json").read_text())
    if digest(selected) != selection["selected_hash"]:
        raise ValueError("Selected parameters changed after model selection")
    frozen_params = load(FROZEN_SELECTED, "shared")
    runs = []
    for name in candidates:
        params = load(out / f"{name}.json", "refit")
        runs.append(dict(id=name, role="candidate", trials=[f"{name}_seed{s}_trials.csv" for s in seeds],
                         fixations=[f"{name}_seed{s}_fixations.csv" for s in seeds],
                         mirror=[f"{name}_mirror_seed{s}.json" for s in seeds],
                         parameters=configuration(params), seeds=list(seeds), n_per_cell=n))
    # The frozen primary run, re-evaluated here for a like-for-like table.
    runs.append(dict(id="frozen_shared", role="baseline",
                     trials=[f"../repair_20260905/shared_seed{s}_trials.csv" for s in (401, 402)],
                     fixations=[f"../repair_20260905/shared_seed{s}_fixations.csv" for s in (401, 402)],
                     parameters=configuration(frozen_params), seeds=[401, 402], n_per_cell=1000))
    manifest = dict(schema_version=1, human="../repair_20260905/human", frozen="frozen.json", runs=runs)
    frozen = selection | dict(runs_hash=digest(runs), final_seeds=list(seeds), final_n_per_cell_per_seed=n,
                              final_minimum_retained_per_cell=len(seeds) * n, candidates=list(candidates),
                              mechanism="refit: fitted Wald noise, decision error, onset latency, error goal, "
                                        "choice temperature, priority noise, shape acuity; adaptive competitive "
                                        "quit increment; distance-penalised exploration; optional saccade trigger",
                              test_results_used_for_selection=False)
    for name, value in (("run_manifest.json", manifest), ("frozen.json", frozen)):
        path = out / name
        if path.exists() and json.loads(path.read_text()) != value:
            raise ValueError(f"Refusing to replace frozen manifest: {path}")
        path.write_text(json.dumps(value, indent=2))
    with ACTRSession(log_path=out / "final_lisp.log") as session:
        for entry in runs:
            if entry["role"] != "candidate":
                continue
            p = validate(entry["parameters"]["params"])
            for seed in seeds:
                if not (out / f"{entry['id']}_seed{seed}_trials.csv").exists():
                    run_batch(session.actr, TASKS, SET_SIZES, n, seed, lisp_values(p), out, entry["id"],
                              session=session, progress=False)
                mirror = out / f"{entry['id']}_mirror_seed{seed}.json"
                if not mirror.exists():
                    mirror.write_text(json.dumps(run_cells(p, n_per_cell=n, seed=seed, keep_fixations=True)))
                print("finished", entry["id"], seed, flush=True)


def evaluate(out, docs):
    from harness.evaluate import evaluate_manifest
    record = evaluate_manifest(out / "run_manifest.json", docs, final_test=True)
    for run in record["runs"]:
        for split, c in run["comparisons"].items():
            print(run["id"], split,
                  {k: (round(v, 1) if isinstance(v, float) else v) for k, v in c.items()}, flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stage", choices=["fit", "select", "final", "evaluate"])
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/refit_20260905")
    ap.add_argument("--docs", type=Path, default=ROOT / "docs/validation-refit-20260905")
    ap.add_argument("--human", type=Path, default=FROZEN_DIR / "human")
    ap.add_argument("-n", type=int, help="trials per cell: fit 200, select 400, final 1000")
    ap.add_argument("--iterations", type=int, default=30)
    ap.add_argument("--popsize", type=int, default=6)
    ap.add_argument("--workers", type=int, default=7)
    ap.add_argument("--base", choices=sorted(BASES), default="explore")
    ap.add_argument("--seeds", type=int, nargs="*")
    ap.add_argument("--candidates", nargs="*", default=["refit_explore_501", "refit_trigger_501"],
                    help="fit-file stems to run in ACT-R for the final comparison")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.stage == "fit":
        fit(args.out, args.human, args.n or 200, args.iterations, args.popsize, args.workers,
            args.seeds or (501, 502), args.base)
    elif args.stage == "select":
        select(args.out, args.human, args.n or 400, args.seeds or (511, 512))
    elif args.stage == "final":
        final(args.out, args.n or 1000, args.seeds or (601, 602), args.candidates)
    else:
        evaluate(args.out, args.docs)


if __name__ == "__main__":
    main()
