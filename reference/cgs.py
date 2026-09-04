"""Competitive Guided Search (Moran, Zehetleitner, Mueller and Usher 2013).

Reference simulation of the model in *Journal of Vision* 13(8):24, following
the handoff document section 7.1.  It is deliberately a *trial-level* model:
there is no display geometry, no eye, and no acuity.  A trial is a weighted
sampling-without-replacement race between the items and a quitting unit.

One trial at set size N
-----------------------
1. Every distractor gets weight 1, the target gets weight ``w_T``.  The quit
   unit starts at weight 0.
2. Repeatedly draw one unit with probability proportional to its weight.
   Drawing the quit unit ends the trial with an "absent" response.
3. Drawing an item costs an identification time drawn from an inverse
   Gaussian with mean ``theta/mu`` and shape ``theta**2 / sigma**2``
   (sigma fixed at 0.1).  Drawing the target ends the trial with a "present"
   response; drawing a distractor sets its weight to 0 and adds ``dw`` to the
   quit weight.
4. RT is the sum of the identification times plus a non-decision constant
   ``t_min`` (separate values for present and absent responses) plus an
   exponential residual with rate ``c``.  With probability ``m`` the response
   is flipped, which is the model's only source of error besides quitting.

Since a distractor's weight goes to zero once identified, a target-absent
trial always terminates: when every distractor is spent the quit unit is the
only unit with weight left.

Parameter provenance
--------------------
The published fits below were transcribed into the handoff document from
memory and the handoff flags them as unverified ("verify them against the
paper's parameter table before asserting them in tests").  They have *not*
been re-checked against Moran et al. (2013) here, because the paper was not
available offline.  So:

* :data:`PARAMS` carries them as ``PUBLISHED_UNVERIFIED``.
* ``reference/test_reference.py`` asserts the *behavioural* targets from the
  handoff (2-vs-5 slopes near 43 ms/item present and 95 ms/item absent,
  feature slopes near 1 ms/item, miss rate rising with set size, false alarms
  under 2 percent), not the parameter values themselves.

``mu``, ``theta``, ``t_min``, ``c`` and ``m`` are given in the handoff only
for the 2-vs-5 task; the same values are reused for the conjunction and
feature tasks, which differ only in ``w_T`` and ``dw``.  That reuse is an
assumption of this file, not something the handoff states.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

SIGMA = 0.1  # fixed by the model


@dataclass(frozen=True)
class CGSParams:
    """One parameter set.  Times in seconds."""

    w_t: float        # target weight
    dw: float         # quit-weight increment per rejection
    mu: float = 0.252     # drift
    theta: float = 0.029  # threshold
    t_min_yes: float = 0.413
    t_min_no: float = 0.410
    c: float = 11.8       # rate of the exponential residual
    m: float = 0.012      # motor error probability

    @property
    def id_mean(self) -> float:
        return self.theta / self.mu

    @property
    def id_shape(self) -> float:
        return self.theta ** 2 / SIGMA ** 2


# Moran et al. (2013), averaged observer.  See "Parameter provenance" above:
# these are the handoff's transcription and have not been re-verified.
PUBLISHED_UNVERIFIED = {
    "spatial": CGSParams(w_t=1.51, dw=0.019),
    "conjunction": CGSParams(w_t=4.96, dw=0.162),
    "feature": CGSParams(w_t=600.0, dw=870.0),
}
PARAMS = PUBLISHED_UNVERIFIED


def _inverse_gaussian(mean: float, shape: float, rng: np.random.Generator,
                      size=None) -> np.ndarray | float:
    return rng.wald(mean, shape, size=size)


def run_trial(p: CGSParams, set_size: int, target_present: bool,
              rng: np.random.Generator) -> dict:
    """Simulate one trial.  Returns response, correctness, RT and item count."""
    n_dist = set_size - (1 if target_present else 0)
    dist_left = n_dist
    w_quit = 0.0
    total_id = 0.0
    n_ident = 0
    found = False

    while True:
        w_target = p.w_t if (target_present and not found) else 0.0
        w_sum = dist_left + w_target + w_quit
        if w_sum <= 0.0:
            break  # nothing left to draw: treat as a quit
        r = rng.random() * w_sum
        if r < w_quit:
            break  # quit unit won
        r -= w_quit
        total_id += float(_inverse_gaussian(p.id_mean, p.id_shape, rng))
        n_ident += 1
        if r < w_target:
            found = True
            break
        dist_left -= 1
        w_quit += p.dw

    resp_present = found
    if rng.random() < p.m:  # motor error flips the response
        resp_present = not resp_present

    t_min = p.t_min_yes if resp_present else p.t_min_no
    rt = total_id + t_min + rng.exponential(1.0 / p.c)

    return {
        "set_size": set_size,
        "target_present": target_present,
        "response": resp_present,
        "correct": resp_present == target_present,
        "rt": rt,
        "n_identified": n_ident,
    }


def run_block(p: CGSParams, set_sizes=(3, 6, 12, 18), n_per_cell: int = 5000,
              seed: int = 0) -> dict:
    """Run every set size x presence cell and summarise it.

    Returns a dict keyed ``(set_size, target_present)`` with mean correct RT,
    error rate and mean identification count.
    """
    rng = np.random.default_rng(seed)
    out = {}
    for n in set_sizes:
        for present in (True, False):
            rts, errs, ids = [], 0, []
            for _ in range(n_per_cell):
                t = run_trial(p, n, present, rng)
                if t["correct"]:
                    rts.append(t["rt"])
                else:
                    errs += 1
                ids.append(t["n_identified"])
            out[(n, present)] = {
                "mean_rt": float(np.mean(rts)) if rts else float("nan"),
                "error_rate": errs / n_per_cell,
                "mean_identified": float(np.mean(ids)),
                "n": n_per_cell,
            }
    return out


def slope_intercept(cells: dict, target_present: bool):
    """Least-squares slope (ms/item) and intercept (ms) over the cell means."""
    xs = np.array([k[0] for k in cells if k[1] == target_present], dtype=float)
    ys = np.array([cells[(int(x), target_present)]["mean_rt"] for x in xs]) * 1000.0
    order = np.argsort(xs)
    slope, intercept = np.polyfit(xs[order], ys[order], 1)
    return float(slope), float(intercept)


def summarise(task: str, n_per_cell: int = 5000, seed: int = 0,
              params: CGSParams | None = None) -> dict:
    p = params or PARAMS[task]
    cells = run_block(p, n_per_cell=n_per_cell, seed=seed)
    tp_slope, tp_int = slope_intercept(cells, True)
    ta_slope, ta_int = slope_intercept(cells, False)
    misses = {k[0]: v["error_rate"] for k, v in cells.items() if k[1]}
    fas = {k[0]: v["error_rate"] for k, v in cells.items() if not k[1]}
    return {
        "task": task,
        "cells": cells,
        "tp_slope": tp_slope, "tp_intercept": tp_int,
        "ta_slope": ta_slope, "ta_intercept": ta_int,
        "ratio": ta_slope / tp_slope if tp_slope else float("nan"),
        "miss_rate": misses,
        "fa_rate": fas,
    }


def fit_w_t_dw(task: str, target_tp_slope: float, target_ta_slope: float,
               n_per_cell: int = 2000, seed: int = 0,
               grid_w=None, grid_dw=None) -> tuple[CGSParams, dict]:
    """Coarse grid search over ``w_T`` and ``dw`` for a slope pair.

    Only used to document how far the unverified published values are from the
    values that actually reproduce the Wolfe et al. (2010) slopes; the fit is
    not part of the deliverable model.
    """
    base = PARAMS[task]
    grid_w = grid_w if grid_w is not None else np.geomspace(0.5, 20.0, 12)
    grid_dw = grid_dw if grid_dw is not None else np.geomspace(0.005, 1.0, 12)
    best, best_cost, best_summary = base, float("inf"), None
    for w in grid_w:
        for d in grid_dw:
            p = replace(base, w_t=float(w), dw=float(d))
            s = summarise(task, n_per_cell=n_per_cell, seed=seed, params=p)
            cost = (s["tp_slope"] - target_tp_slope) ** 2 + \
                   (s["ta_slope"] - target_ta_slope) ** 2
            if cost < best_cost:
                best, best_cost, best_summary = p, cost, s
    return best, best_summary


if __name__ == "__main__":
    for task in ("feature", "conjunction", "spatial"):
        s = summarise(task, n_per_cell=4000, seed=7)
        print(f"{task:12s} TP {s['tp_slope']:7.2f} ms/item (int {s['tp_intercept']:6.0f})"
              f"   TA {s['ta_slope']:7.2f} ms/item (int {s['ta_intercept']:6.0f})"
              f"   ratio {s['ratio']:4.2f}")
        print(f"{'':12s} miss " +
              " ".join(f"n{k}={v:.3f}" for k, v in sorted(s["miss_rate"].items())) +
              "   FA " +
              " ".join(f"n{k}={v:.3f}" for k, v in sorted(s["fa_rate"].items())))
