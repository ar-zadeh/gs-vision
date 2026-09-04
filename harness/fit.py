"""Parameter fitting for the gs-vision module, handoff section 8.4.

Fitting runs against ``reference/gs_hybrid.py``, never against the Lisp
module: one objective evaluation is 24 cells times a few hundred trials, and
differential evolution needs thousands of evaluations.  In numpy that is
minutes to hours; over the ACT-R JSON-RPC link it would be months.  The Lisp
module is then run once at the fitted values and its misfit reported beside
the Python one, per cell.  If the two disagree by more than Monte Carlo error,
the Lisp port is wrong, not the fit.

Two modes
---------
``--phase1``
    Coarse per-task search on *slopes* only, to establish the phase 1
    parameter sets the handoff asks for ("a first parameter set per task
    giving Tier 1 slopes within 10 ms/item").  Random search followed by
    coordinate refinement.  Cheap enough to run in a few minutes.
``--de``
    The full section 8.4 objective: differential evolution over
    ``{beta, mu, theta, dw, w_TD, w_BU, noise, memory, select-interval}``
    minimising, summed over cells, the RMSE of the .1/.3/.5/.7/.9 RT quantiles
    plus 10 times the absolute error-rate difference.

Tier 1 targets
--------------
``search.bwh.harvard.edu`` did not respond on 2026-09-04 (and does not now),
so the trial-level Wolfe, Palmer and Horowitz (2010) distributions are not
available and the targets below are the published summary slopes for those
three tasks.  ``reference/cgs.py`` reproduces them from the Competitive Guided
Search fits, which is the closest independent check available offline.  When
the raw data becomes reachable, replace :data:`TIER1_SLOPES` and
:data:`TIER1_QUANTILES` with values read from it; nothing else changes.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from dataclasses import replace

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference.gs_hybrid import DEFAULTS, GSParams, run_cells, slopes  # noqa: E402
from harness.tasks import SET_SIZES, TASKS                             # noqa: E402

# Published slopes, ms/item, (target present, target absent).
TIER1_SLOPES = {
    "feature": (1.0, 3.0),
    "conjunction": (20.0, 45.0),
    "spatial": (43.0, 95.0),
}
# Published mean correct RT intercepts, ms, same order.
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
            ok = [r["rt"] * 1000.0 for r in sel if r["correct"]]
            out[(n, present)] = {
                "q": _quantiles(ok),
                "err": (sum(1 for r in sel if not r["correct"]) / len(sel)) if sel else np.nan,
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
    target = target or synthetic_target(task)
    rows = run_cells(params, tasks=(task,), n_per_cell=n_per_cell, seed=seed)
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
        total += rmse + 10.0 * derr * 100.0     # error rates in points, not fractions
    return total, per_cell


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
    return {k: getattr(p, k) for k in PHASE1_SPACE if getattr(p, k) != getattr(base, k)}


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
    ("choice_beta", 1.0, 20.0),
    ("id_drift", 0.10, 0.60),
    ("id_threshold", 0.005, 0.10),
    ("quit_delta", 0.002, 0.20),
    ("w_td", 0.2, 3.0),
    ("w_bu", 0.0, 2.0),
    ("noise", 0.02, 0.5),
    ("memory", 2.0, 18.0),
    ("select_interval", 0.02, 0.15),
]


def de_fit(tasks=TASKS, n_per_cell: int = 60, maxiter: int = 12, popsize: int = 8,
           seed: int = 0, base: GSParams = DEFAULTS, verbose: bool = True):
    """Differential evolution over the section 8.4 parameter set, shared across tasks."""
    from scipy.optimize import differential_evolution

    def unpack(x) -> GSParams:
        d = {}
        for (name, _lo, _hi), v in zip(DE_BOUNDS, x):
            d[name] = int(round(v)) if name == "memory" else float(v)
        return replace(base, **d)

    def obj(x):
        p = unpack(x)
        return sum(quantile_cost(t, p, n_per_cell, seed)[0] for t in tasks)

    res = differential_evolution(
        obj, [(lo, hi) for _n, lo, hi in DE_BOUNDS], seed=seed, maxiter=maxiter,
        popsize=popsize, tol=0.01, polish=False, disp=verbose, init="sobol")
    return unpack(res.x), float(res.fun), res


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
    ap.add_argument("-o", "--out", default=str(ROOT / "data" / "model" / "fit.json"))
    args = ap.parse_args()

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
                         maxiter=args.iters, seed=args.seed)
        result["_de"] = {"cost": c, "params": _jsonable(p)}
        print("DE best:", params_delta(p), "cost", c)

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, default=str))
    print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
