"""Fit and evaluate gs6-vision, the Guided Search 6 variant of the module.

Two candidates are fitted on the training participants with the Python mirror
(``reference/gs6_hybrid.py``):

``posted``
    Wolfe's engine exactly as posted (diffuser step, drift, noise, bounds,
    quit signal, threshold, feedback steps, error goal, no memory beyond the
    diffuser).  Only the parameters GS6 does not specify are fitted: the
    attentional field, the shape acuity slope, the bottom-up weight, the onset
    latency, the saccade trigger, the few-item IOR memory, the choice
    temperature and the priority noise.
``fitted``
    The same, plus the engine's own rates and thresholds, the similarity
    scaling of distractor drift, the selection interval and the error goal.

The stages mirror ``harness/refit.py``: ``fit`` on the training participants,
``select`` among candidates on the validation participants with fresh seeds,
``final`` runs the candidates in ACT-R (gs6-vision) and in the mirror next to
the frozen gs-vision baseline and the September 5 refit, ``evaluate`` writes
the comparison for every split.  The frozen validation directories are not
touched.  The frozen model's test summaries were inspected before this work
began, so every result is exploratory.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from harness.fit import de_fit, quantile_cost                                  # noqa: E402
from harness.human_data import targets, digest                                 # noqa: E402
from harness.parameters import configuration, load, lisp_values, validate      # noqa: E402
from harness.tasks import TASKS, SET_SIZES                                     # noqa: E402
from reference.gs6_hybrid import DEFAULTS as GS6_DEFAULTS                      # noqa: E402
from reference.gs_hybrid import run_cells                                      # noqa: E402

FROZEN_DIR = ROOT / "data/model/repair_20260905"
FROZEN_SELECTED = ROOT / "docs/validation-20260905/selected.json"
REFIT_DIR = ROOT / "data/model/refit_20260905"
REFIT_CANDIDATE = "refit_trigger_501"

# What GS6 leaves open: the spatial layer and the selection noise.
SPATIAL_BOUNDS = [
    ("attn_fvf", 4.0, 16.0),
    ("shape_theta", 0.10, 0.45),
    ("w_bu", 0.0, 4.0),
    ("onset_latency", 0.0, 0.20),
    ("saccade_trigger", 1.0, 10.0),
    ("memory", 0.0, 4.0),
    ("choice_beta", 1.0, 8.0),
    ("noise", 0.05, 0.60),
]
# What the posted simulation fixes and the paper leaves to data.
ENGINE_BOUNDS = [
    ("diff_inc", 0.02, 0.20),
    ("diff_noise", 1.0, 4.0),
    ("quit_inc", 0.005, 0.10),
    ("qt_init", 0.2, 6.0),
    ("qt_step", 0.0005, 0.05),
    ("error_goal", 0.01, 0.15),
    ("similarity_drift", 0.0, 1.0),
    ("select_interval", 0.02, 0.10),
]
BOUNDS = {"posted": SPATIAL_BOUNDS, "fitted": SPATIAL_BOUNDS + ENGINE_BOUNDS}
# The optimizer's starting member must lie inside the bounds; the saccade
# trigger is off (0) in the module defaults and always on in the fitted range.
BASE = replace(GS6_DEFAULTS, saccade_trigger=6.0)
EXPLORATORY_NOTE = ("Test summaries of the frozen September 5 gs-vision model were inspected before this "
                    "work. Selection here happens before the gs6 test evaluation, but the round is exploratory.")


def fit(out, human, n, iterations, popsize, workers, seeds, base_name):
    train = targets(human, "train")
    bounds = BOUNDS[base_name]
    for seed in seeds:
        path = out / f"gs6_{base_name}_{seed}.json"
        if path.exists():
            print("exists", path, flush=True)
            continue
        p, cost, res = de_fit(n_per_cell=n, maxiter=iterations, popsize=popsize, seed=seed,
                              targets=train, base=BASE, bounds=bounds, workers=workers)
        path.write_text(json.dumps({"gs6": configuration(p) | dict(
            cost=cost, seed=seed, base=base_name, bounds=bounds, n_per_cell=n, maxiter=iterations,
            popsize=popsize, workers=workers, evaluations=int(res.nfev),
            optimizer_success=bool(res.success), message=str(res.message), fit_split="train")},
            indent=2))
        print("fit", base_name, seed, cost, flush=True)


def candidates_of(out) -> dict:
    """The module defaults plus every fit file ``gs6_<base>_<seed>.json``."""
    import re
    out_c = {"gs6_defaults": GS6_DEFAULTS}
    for path in sorted(out.glob("gs6_*.json")):
        if re.fullmatch(r"gs6_(posted|fitted)_\d+", path.stem):
            out_c[path.stem] = load(path, "gs6")
    return out_c


def select(out, human, n, seeds):
    validation = targets(human, "validation")
    candidates = candidates_of(out)
    references = {"frozen_shared": load(FROZEN_SELECTED, "shared"),
                  REFIT_CANDIDATE: load(REFIT_DIR / f"{REFIT_CANDIDATE}.json", "refit")}
    scores, per_task = {}, {}
    for name, p in (candidates | references).items():
        costs = {t: [quantile_cost(t, p, n, s, validation[t])[0] for s in seeds] for t in TASKS}
        per_task[name] = {t: sum(v) / len(v) for t, v in costs.items()}
        scores[name] = sum(per_task[name].values()) / len(TASKS)
        print("validation", name, round(scores[name], 1),
              {t: round(v, 1) for t, v in per_task[name].items()}, flush=True)
    winner = min((k for k in candidates), key=scores.get)
    selected = {"gs6": configuration(candidates[winner])}
    (out / "selected.json").write_text(json.dumps(selected, indent=2))
    selection = dict(winner=winner, validation_scores=scores, validation_scores_by_task=per_task,
                     validation_seeds=list(seeds), validation_n_per_cell=n, bounds=BOUNDS,
                     candidates=sorted(candidates), references=sorted(references),
                     selected_hash=digest(selected), model_selection_status="frozen_before_test",
                     exploratory=EXPLORATORY_NOTE,
                     human_manifest=json.loads((human / "manifest.json").read_text()))
    (out / "selection.json").write_text(json.dumps(selection, indent=2))
    print("selected", winner, flush=True)


def final(out, n, seeds, names):
    """Run every named gs6 candidate in ACT-R and the mirror, next to the baselines."""
    from harness.run_batch import ACTRSession, LOAD_FILES, run_batch
    selection = json.loads((out / "selection.json").read_text())
    selected = json.loads((out / "selected.json").read_text())
    if digest(selected) != selection["selected_hash"]:
        raise ValueError("Selected parameters changed after model selection")
    candidates = candidates_of(out)
    runs = []
    for name in names:
        params = candidates[name]
        runs.append(dict(id=name, role="candidate", model="gs6",
                         trials=[f"{name}_seed{s}_trials.csv" for s in seeds],
                         fixations=[f"{name}_seed{s}_fixations.csv" for s in seeds],
                         mirror=[f"{name}_mirror_seed{s}.json" for s in seeds],
                         parameters=configuration(params), seeds=list(seeds), n_per_cell=n))
    runs.append(dict(id="frozen_shared", role="baseline", model="gs",
                     trials=[f"../repair_20260905/shared_seed{s}_trials.csv" for s in (401, 402)],
                     fixations=[f"../repair_20260905/shared_seed{s}_fixations.csv" for s in (401, 402)],
                     parameters=configuration(load(FROZEN_SELECTED, "shared")), seeds=[401, 402],
                     n_per_cell=1000))
    runs.append(dict(id=REFIT_CANDIDATE, role="baseline", model="gs",
                     trials=[f"../refit_20260905/{REFIT_CANDIDATE}_seed{s}_trials.csv" for s in (601, 602)],
                     fixations=[f"../refit_20260905/{REFIT_CANDIDATE}_seed{s}_fixations.csv" for s in (601, 602)],
                     parameters=configuration(load(REFIT_DIR / f"{REFIT_CANDIDATE}.json", "refit")),
                     seeds=[601, 602], n_per_cell=1000))
    manifest = dict(schema_version=1, human="../repair_20260905/human", frozen="frozen.json", runs=runs)
    frozen = selection | dict(runs_hash=digest(runs), final_seeds=list(seeds), final_n_per_cell_per_seed=n,
                              final_minimum_retained_per_cell=len(seeds) * n, candidates=list(names),
                              mechanism="gs6-vision: Wolfe's asynchronous two-bound diffuser with an adaptive "
                                        "start point, the GS6 quit-signal diffuser with the posted feedback "
                                        "rules, diffuser-only memory, GS2 dual orientation channels and "
                                        "best-channel top-down guidance, on the gs-vision spatial layer",
                              test_results_used_for_selection=False)
    for name, value in (("run_manifest.json", manifest), ("frozen.json", frozen)):
        path = out / name
        if path.exists() and json.loads(path.read_text()) != value:
            raise ValueError(f"Refusing to replace frozen manifest: {path}")
        path.write_text(json.dumps(value, indent=2))
    with ACTRSession(log_path=out / "final_lisp.log", load_file=LOAD_FILES["gs6"]) as session:
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
        if "parity" in run:
            print(run["id"], "parity", run["parity"], flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stage", choices=["fit", "select", "final", "evaluate"])
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/gs6_20260905")
    ap.add_argument("--docs", type=Path, default=ROOT / "docs/validation-gs6-20260905")
    ap.add_argument("--human", type=Path, default=FROZEN_DIR / "human")
    ap.add_argument("-n", type=int, help="trials per cell: fit 200, select 400, final 1000")
    ap.add_argument("--iterations", type=int, default=30)
    ap.add_argument("--popsize", type=int, default=6)
    ap.add_argument("--workers", type=int, default=7)
    ap.add_argument("--base", choices=sorted(BOUNDS), default="posted")
    ap.add_argument("--seeds", type=int, nargs="*")
    ap.add_argument("--candidates", nargs="*", default=["gs6_defaults", "gs6_posted_801", "gs6_fitted_801"],
                    help="candidate names to run in ACT-R for the final comparison")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.stage == "fit":
        fit(args.out, args.human, args.n or 200, args.iterations, args.popsize, args.workers,
            args.seeds or (801,), args.base)
    elif args.stage == "select":
        select(args.out, args.human, args.n or 400, args.seeds or (811, 812))
    elif args.stage == "final":
        final(args.out, args.n or 1000, args.seeds or (901, 902), args.candidates)
    else:
        evaluate(args.out, args.docs)


if __name__ == "__main__":
    main()
