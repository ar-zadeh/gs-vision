"""Fit the hybrid to validated, participant-weighted human training summaries.

The real-data CLI requires --human and --de. The objective averages cell
quantile RMSE (milliseconds), 1000 times absolute error-rate difference, and
2000 times timeout fraction; empty correct cells receive a 2000 ms penalty.
Training fits and larger independent validation simulations remain separate.
The six-parameter DE space fixes drift, choice temperature, and noise to avoid
redundant scale fitting. Complete parameter configurations use parameters.py.

Historical slope dictionaries and synthetic_target exist only for explicitly
labeled smoke tests. They are never the default real-data target. ACT-R, not
mirror fit success, supplies final stimulus-to-keypress human validation.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from dataclasses import replace, asdict

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference.gs_hybrid import DEFAULTS, GSParams, run_cells, slopes  # noqa: E402
from harness.tasks import SET_SIZES, TASKS                             # noqa: E402
from harness.parameters import configuration
from harness.human_data import targets as human_targets

# Historical provisional slopes, NOT measured raw-data targets.
TIER1_SLOPES = {
    "feature": (1.0, 3.0),
    "conjunction": (20.0, 45.0),
    "spatial": (43.0, 95.0),
}
# Historical provisional intercepts, NOT measured raw-data targets.
TIER1_INTERCEPTS = {
    "feature": (480.0, 500.0),
    "conjunction": (520.0, 560.0),
    "spatial": (560.0, 580.0),
}
QUANTILES = (0.1, 0.3, 0.5, 0.7, 0.9)

# Search space for --phase1.  Every entry is a handoff parameter that section
# 5 or section 12 marks as provisional or task-dependent.
PHASE1_SPACE = {
    "memory": [4, 6, 8, 12, 16],
    "w_e": [0.02, 0.05, 0.10, 0.15, 0.25],
    "noise": [0.05, 0.1, 0.2, 0.3],
    "choice_beta": [2.0, 4.0, 8.0, 16.0],
    "select_interval": [0.020, 0.030, 0.050, 0.080],
    "diffuser_capacity": [2, 3, 5, 8],
    "attn_fvf": [5.0, 8.0, 10.0, 12.0, 16.0],
    "max_fixation": [0.20, 0.25, 0.4, 0.6],
}

# Slopes are the section 10 acceptance criterion (within 5 ms/item), so they
# carry the objective.  Intercepts enter at a weight that makes a 300 ms miss
# worth about as much as a 12 ms/item slope miss: they are informative but
# they must not decide the fit, especially since the response stage that sets
# them is deliberately outside the module.
INTERCEPT_WEIGHT = 0.002


# --------------------------------------------------------------------------
# Objectives
# --------------------------------------------------------------------------

def slope_cost(task: str, params: GSParams, n_per_cell: int, seed: int) -> tuple:
    """Squared slope error plus penalties for absurd error rates."""
    rows = run_cells(params, tasks=(task,), n_per_cell=n_per_cell, seed=seed)
    s = slopes(rows, task)
    tp_t, ta_t = TIER1_SLOPES[task]
    cost = (s["tp"][0] - tp_t) ** 2 + (s["ta"][0] - ta_t) ** 2
    if not np.isfinite(cost):
        return float("inf"), s
    miss = np.nanmean(list(s["miss"].values()))
    fa = np.nanmean(list(s["fa"].values()))
    cost += 4000.0 * max(0.0, miss - 0.15) ** 2      # tolerate up to 15% misses
    cost += 40000.0 * max(0.0, fa - 0.05) ** 2
    tp_i, ta_i = TIER1_INTERCEPTS[task]
    cost += INTERCEPT_WEIGHT * ((s["tp"][1] - tp_i) ** 2 + (s["ta"][1] - ta_i) ** 2)
    return float(cost), s


def _quantiles(vals, qs=QUANTILES):
    return np.quantile(np.asarray(vals, float), qs) if len(vals) >= 5 else \
        np.full(len(qs), np.nan)


def cell_quantiles(rows, task: str) -> dict:
    """Correct-trial RT quantiles (ms) and error rate for each cell."""
    out = {}
    for n in SET_SIZES:
        for present in (True, False):
            sel = [r for r in rows if r["task"] == task and r["set_size"] == n
                   and r["target_present"] == present]
            upper = 8000 if task == "spatial" else 4000
            ok = [r["rt"] * 1000.0 for r in sel if r["correct"] and
                  200 <= r["rt"] * 1000 <= upper]
            out[(n, present)] = {
                "q": _quantiles(ok),
                "err": (sum(1 for r in sel if not r["correct"] and not r.get("timed_out")) / len(sel)) if sel else np.nan,
                "timeout_rate": sum(bool(r.get("timed_out")) for r in sel) / len(sel) if sel else 1,
                "n": len(sel),
            }
    return out


def synthetic_target(task: str) -> dict:
    """Tier 1 target cells built from the published slopes and intercepts.

    Real quantiles need the trial-level data.  Until the Wolfe server responds
    we build each cell's mean from ``intercept + slope * N`` and give it an
    ex-Gaussian shape with tau = 0.35 * mean, which is the shape those tasks
    show; the quantile spacing, not the exact tau, is what the objective sees.
    """
    tp_s, ta_s = TIER1_SLOPES[task]
    tp_i, ta_i = TIER1_INTERCEPTS[task]
    rng = np.random.default_rng(12345)
    out = {}
    for n in SET_SIZES:
        for present in (True, False):
            m = (tp_i + tp_s * n) if present else (ta_i + ta_s * n)
            tau = 0.35 * m
            mu = m - tau
            sigma = 0.12 * m
            draws = rng.normal(mu, sigma, 20000) + rng.exponential(tau, 20000)
            out[(n, present)] = {"q": np.quantile(draws, QUANTILES),
                                 "err": 0.05 if present else 0.01}
    return out


def quantile_cost(task: str, params: GSParams, n_per_cell: int, seed: int,
                  target: dict | None = None) -> tuple:
    """Section 8.4 objective: quantile RMSE + 10 * |error-rate difference|."""
    if target is None:
        raise ValueError("Validated human targets and split required; use synthetic_target explicitly for smoke tests")
    rows = run_cells(params, tasks=(task,), n_per_cell=n_per_cell, seed=seed, practice=30)
    model = cell_quantiles(rows, task)
    total, per_cell = 0.0, {}
    for key, tgt in target.items():
        mq, tq = model[key]["q"], tgt["q"]
        if np.any(~np.isfinite(mq)):
            rmse = 2000.0
        else:
            rmse = float(np.sqrt(np.mean((mq - tq) ** 2)))
        derr = abs(model[key]["err"] - tgt["err"]) if np.isfinite(model[key]["err"]) else 1.0
        per_cell[key] = {"quantile_rmse_ms": rmse, "err_diff": derr}
        timeout_rate = model[key].get("timeout_rate", 0.0)
        per_cell[key]["timeout_rate"] = timeout_rate
        total += rmse + 10.0 * derr * 100.0 + 2000.0 * timeout_rate
    return total / len(target), per_cell


# --------------------------------------------------------------------------
# Phase 1 search
# --------------------------------------------------------------------------

def phase1(task: str, n_iter: int = 60, n_per_cell: int = 120, seed: int = 0,
           base: GSParams = DEFAULTS, verbose: bool = True) -> tuple:
    rng = np.random.default_rng(seed)
    keys = list(PHASE1_SPACE)

    best = base
    best_cost, best_s = slope_cost(task, base, n_per_cell, seed)
    if verbose:
        print(f"  base   cost {best_cost:11.1f}  TP {best_s['tp'][0]:7.1f} "
              f"TA {best_s['ta'][0]:7.1f}")

    for i in range(n_iter):
        cand = {k: PHASE1_SPACE[k][int(rng.integers(len(PHASE1_SPACE[k])))] for k in keys}
        p = replace(base, **cand)
        c, s = slope_cost(task, p, n_per_cell, seed)
        if c < best_cost:
            best, best_cost, best_s = p, c, s
            if verbose:
                print(f"  rnd{i:03d} cost {c:11.1f}  TP {s['tp'][0]:7.1f} "
                      f"TA {s['ta'][0]:7.1f}  {cand}")

    improved = True
    while improved:                                   # coordinate refinement
        improved = False
        for k in keys:
            for v in PHASE1_SPACE[k]:
                if getattr(best, k) == v:
                    continue
                p = replace(best, **{k: v})
                c, s = slope_cost(task, p, n_per_cell, seed)
                if c < best_cost - 1e-9:
                    best, best_cost, best_s, improved = p, c, s, True
                    if verbose:
                        print(f"  ref    cost {c:11.1f}  TP {s['tp'][0]:7.1f} "
                              f"TA {s['ta'][0]:7.1f}  {k}={v}")
    return best, best_cost, best_s


def params_delta(p: GSParams, base: GSParams = DEFAULTS) -> dict:
    return {k: v for k, v in asdict(p).items() if v != asdict(base)[k]}


def shared_cost(params: GSParams, n_per_cell: int, seed: int,
                tasks=TASKS) -> tuple:
    """Sum the per-task slope cost: one parameter set for all three tasks.

    Section 12 decision 6 asks whether :gs-select-interval and
    :gs-diffuser-capacity may differ per task.  This is the other branch, so
    that the residual misfit at a single shared set can be reported rather
    than hidden."""
    total, per = 0.0, {}
    for t in tasks:
        c, s = slope_cost(t, params, n_per_cell, seed)
        total += c
        per[t] = s
    return total, per


def phase1_shared(n_iter: int = 60, n_per_cell: int = 120, seed: int = 0,
                  base: GSParams = DEFAULTS, verbose: bool = True) -> tuple:
    rng = np.random.default_rng(seed)
    keys = list(PHASE1_SPACE)
    best = base
    best_cost, best_s = shared_cost(base, n_per_cell, seed)

    def _show(tag, c, s):
        bits = " ".join(f"{t[:4]} {s[t]['tp'][0]:5.1f}/{s[t]['ta'][0]:6.1f}" for t in TASKS)
        print(f"  {tag} cost {c:10.1f}  {bits}")

    if verbose:
        _show("base  ", best_cost, best_s)
    for i in range(n_iter):
        cand = {k: PHASE1_SPACE[k][int(rng.integers(len(PHASE1_SPACE[k])))] for k in keys}
        p = replace(base, **cand)
        c, s = shared_cost(p, n_per_cell, seed)
        if c < best_cost:
            best, best_cost, best_s = p, c, s
            if verbose:
                _show(f"rnd{i:03d}", c, s)
    improved = True
    while improved:
        improved = False
        for k in keys:
            for v in PHASE1_SPACE[k]:
                if getattr(best, k) == v:
                    continue
                p = replace(best, **{k: v})
                c, s = shared_cost(p, n_per_cell, seed)
                if c < best_cost - 1e-9:
                    best, best_cost, best_s, improved = p, c, s, True
                    if verbose:
                        _show("ref   ", c, s)
    return best, best_cost, best_s


# --------------------------------------------------------------------------
# Differential evolution (section 8.4)
# --------------------------------------------------------------------------

DE_BOUNDS = [
    ("id_threshold", 0.015, 0.08), # drift fixed: avoid fitting two redundant time scales
    ("memory", 4.0, 18.0),
    ("select_interval", 0.02, 0.10),
    ("w_bu", 0.0, 4.0),
    ("attn_fvf", 5.0, 12.0),
    ("quit_delta", 0.002, 0.15),
]

# The September 5 refit.  Identification noise, decision error, onset latency,
# the quit controller's goal, choice temperature, priority noise and the shape
# acuity slope were fixed constants in the six-parameter search above.
# ``shape_theta`` is not a GSParams field: it rewrites the shape entry of
# ``acuity_theta``.  Drift stays fixed (theta/mu is the mean, sigma the CV).
DE_BOUNDS_REFIT = [
    ("id_threshold", 0.015, 0.10),
    ("id_sigma", 0.01, 0.12),
    ("id_error", 0.0, 0.04),
    ("onset_latency", 0.0, 0.20),
    ("memory", 4.0, 18.0),
    ("select_interval", 0.02, 0.10),
    ("w_bu", 0.0, 4.0),
    ("attn_fvf", 4.0, 16.0),
    ("quit_delta", 0.002, 0.15),
    ("error_goal", 0.01, 0.15),
    ("choice_beta", 1.0, 8.0),
    ("noise", 0.05, 0.60),
    ("shape_theta", 0.10, 0.45),
]


def unpack_vector(x, bounds, base: GSParams) -> GSParams:
    """Map an optimizer vector onto a complete parameter set."""
    d = {}
    for (name, _lo, _hi), v in zip(bounds, x):
        if name == "memory":
            d[name] = int(round(v))
        elif name == "shape_theta":
            d["acuity_theta"] = tuple((k, float(v) if k == "shape" else t)
                                      for k, t in base.acuity_theta)
        else:
            d[name] = float(v)
    return replace(base, **d)


def pack_params(p: GSParams, bounds) -> list:
    return [dict(p.acuity_theta)["shape"] if name == "shape_theta" else getattr(p, name)
            for name, _, _ in bounds]


def _de_objective(x, bounds, base, tasks, n_per_cell, seed, targets):
    """Module-level so that scipy's worker pool can pickle it."""
    p = unpack_vector(x, bounds, base)
    return float(np.mean([quantile_cost(t, p, n_per_cell, seed, targets[t])[0] for t in tasks]))


def de_fit(tasks=TASKS, n_per_cell: int = 60, maxiter: int = 12, popsize: int = 8,
           seed: int = 0, base: GSParams = DEFAULTS, verbose: bool = True,
           targets=None, bounds=DE_BOUNDS, workers: int = 1, x0=None):
    """Differential evolution over ``bounds``, shared across ``tasks``.

    ``workers`` > 1 evaluates a generation in parallel processes (scipy's
    deferred updating), which changes the search path but not the objective.
    """
    from functools import partial
    from scipy.optimize import differential_evolution

    if targets is None:
        raise ValueError("Explicit targets required")
    obj = partial(_de_objective, bounds=bounds, base=base, tasks=tuple(tasks),
                  n_per_cell=n_per_cell, seed=seed, targets=targets)
    extra = dict(workers=workers, updating="deferred") if workers != 1 else {}
    res = differential_evolution(
        obj, [(lo, hi) for _n, lo, hi in bounds], seed=seed, maxiter=maxiter,
        popsize=popsize, tol=0.01, polish=False, disp=verbose, init="latinhypercube",
        x0=pack_params(base, bounds) if x0 is None else x0, **extra)
    return unpack_vector(res.x, bounds, base), float(res.fun), res


# --------------------------------------------------------------------------

def _jsonable(p: GSParams) -> dict:
    return {k: (list(v) if isinstance(v, tuple) else v)
            for k, v in p.__dict__.items()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase1", action="store_true")
    ap.add_argument("--shared", action="store_true",
                    help="fit one parameter set across all three tasks")
    ap.add_argument("--de", action="store_true")
    ap.add_argument("--tasks", nargs="*", default=list(TASKS))
    ap.add_argument("-n", "--n-per-cell", type=int, default=120)
    ap.add_argument("--iters", type=int, default=60)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--human", help="validated human_data.py output directory")
    ap.add_argument("--popsize", type=int, default=4)
    ap.add_argument("--synthetic-smoke", action="store_true", help="explicit historical synthetic smoke test")
    ap.add_argument("-o", "--out", default=str(ROOT / "data" / "model" / "fit.json"))
    args = ap.parse_args()

    if not args.human and not args.synthetic_smoke:
        ap.error("--human is required for real-data fitting; synthetic smoke tests must be explicit")
    target = human_targets(args.human, "train") if args.human else {t: synthetic_target(t) for t in args.tasks}
    if args.human and not args.de:
        ap.error("Real-data fitting uses --de; historical slope-only modes require --synthetic-smoke")

    result = {}
    if args.shared:
        print("== phase 1: one shared parameter set for all three tasks")
        p, c, s = phase1_shared(n_iter=args.iters, n_per_cell=args.n_per_cell,
                                seed=args.seed)
        result["shared"] = {
            "delta": params_delta(p), "cost": c, "params": _jsonable(p),
            "per_task": {t: {"tp_slope": s[t]["tp"][0], "ta_slope": s[t]["ta"][0],
                             "tp_intercept": s[t]["tp"][1],
                             "ta_intercept": s[t]["ta"][1],
                             "miss": s[t]["miss"], "fa": s[t]["fa"],
                             "mean_fixations": s[t]["mean_fixations"]}
                         for t in TASKS}}
        print("  best ->", params_delta(p))
    if args.phase1 or not (args.de or args.shared):
        for task in args.tasks:
            print(f"== phase 1: {task} (target "
                  f"{TIER1_SLOPES[task][0]:.0f}/{TIER1_SLOPES[task][1]:.0f} ms/item)")
            p, c, s = phase1(task, n_iter=args.iters, n_per_cell=args.n_per_cell,
                             seed=args.seed)
            result[task] = {"delta": params_delta(p), "cost": c,
                            "tp_slope": s["tp"][0], "ta_slope": s["ta"][0],
                            "tp_intercept": s["tp"][1], "ta_intercept": s["ta"][1],
                            "miss": s["miss"], "fa": s["fa"],
                            "mean_fixations": s["mean_fixations"],
                            "params": _jsonable(p)}
            print(f"  best  TP {s['tp'][0]:.1f}  TA {s['ta'][0]:.1f}  -> {params_delta(p)}")
    if args.de:
        p, c, _ = de_fit(tuple(args.tasks), n_per_cell=args.n_per_cell,
                         maxiter=args.iters, seed=args.seed, targets=target, popsize=args.popsize)
        result["shared" if len(args.tasks) > 1 else args.tasks[0]] = configuration(p) | {
            "cost": c, "fit_split": "train", "human": args.human,
            "synthetic": args.synthetic_smoke, "seed": args.seed,
            "n_per_cell": args.n_per_cell, "maxiter": args.iters,
            "popsize": args.popsize, "bounds": DE_BOUNDS}
        print("DE best:", params_delta(p), "cost", c)

    out = pathlib.Path(args.out)
    result["_provenance"] = dict(schema_version=1, synthetic=args.synthetic_smoke,
                                human=args.human, fit_split="train" if args.human else "synthetic",
                                objective="mean cell quantile RMSE ms + 1000*error-rate difference + 2000*timeout fraction")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, default=str))
    print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
