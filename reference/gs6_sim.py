"""Guided Search 6 asynchronous-diffuser simulation (Wolfe 2021).

A faithful Python port of ``GS6publicAsPostedJan2021.m``, the MATLAB
simulation posted by Wolfe at https://osf.io/9n4hf/ (project "Guided Search
6.0", file ``Code/GS6publicAsPostedJan2021.m``, 506 lines, 22961 bytes,
downloaded 2026-09-04 from https://osf.io/download/3ehkt/).  Fetch it again
with ``python reference/fetch_gs6_matlab.py``; it is not committed.

What the handoff left open, and what the MATLAB actually says
-------------------------------------------------------------
Handoff section 7.2 says the exact prevalence scaling and any zROC target are
not spelled out in the paper text and instructs the implementer to take them
from the MATLAB.  Here is what the MATLAB does, recorded as instructed:

* **The quitting signal is a continuous diffuser, not a rejection counter.**
  ``quitSig += randn()*quitNoiseSD + quitInc`` on every 10 ms step, starting
  only after the first distractor has been rejected.  ``quitInc = 0.018`` and
  ``quitNoiseSD = 2.5 * quitInc``.
* **Quitting threshold scales with set size at test time**, not at trial
  start: quit when ``quitSig > quitThresh * (SS / (max(SS) * 0.5))``.  With
  ``max(SS) = 20`` that divisor is 10, so ``quitThresh = 1.5`` is the value
  for the largest set size.
* **Prevalence enters the threshold updates twice.**
  ``quitUpStep = quitDownStep / (missDesired * prev * 2)`` with
  ``quitDownStep = 0.005``; then a miss applies ``+quitUpStep * (1 - prev)``
  and a true negative applies ``-quitDownStep * prev``.  The handoff's
  section 5.6 rule for the *module* keeps only the first of those three
  factors; that difference is deliberate and is noted in the module README.
* **Start point** begins at ``prev/2 - 0.25``, rises by ``StartInc = 0.0008``
  after a hit and falls by ``StartDec = 0.05`` after a false alarm.  The
  comment in the MATLAB says the target zROC slope is about 0.6.
* **Item diffusion**: bounds at +1 (target) and -1 (distractor), step
  ``adifInc = 0.05`` with SD ``2.5 * adifInc``, sign given by whether the item
  is the target (+1) or a distractor (-1).  So 20 noiseless steps of 10 ms
  reach a bound, which is the "200 ms noiseless" of the handoff.
* **Memory is only the diffuser.**  A rejected distractor is reset to 0 and
  becomes selectable again immediately.  Selection happens every 50 ms if the
  diffuser holds fewer than 5 items.
* **A quirk that is reproduced rather than fixed**: the target-threshold test
  and the quit test are two independent ``if`` blocks in the same 10 ms step,
  and the quit block does not check whether a response has already been made.
  When both fire on the same step the quit response overwrites the yes
  response.  It is rare, and this port keeps it so the two implementations
  agree.

There is no non-decision time in the MATLAB: reported RTs are pure search
times in milliseconds.  Real RTs would add a few hundred ms.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

RT_STEP = 10          # ms per diffuser update
SELECT_TIME = 50      # ms between selections
SET_SIZES = (5, 10, 15, 20)
PREVALENCES = (0.1, 0.3, 0.5, 0.7, 0.9)

HIT, FA, TNEG, MISS = 1, 2, 3, 4


@dataclass
class GS6Params:
    adif_capacity: int = 5
    adif_inc: float = 0.05
    adif_noise_mult: float = 2.5
    targ_thresh: float = 1.0
    dist_thresh: float = -1.0
    quit_thresh0: float = 1.5
    quit_down_step: float = 0.005
    quit_inc: float = 0.018
    quit_noise_mult: float = 2.5
    start_dec: float = 0.05
    start_inc: float = 0.0008
    miss_desired: float = 0.08
    max_rt_ms: int = 20000   # guard, absent from the MATLAB

    @property
    def adif_noise(self) -> float:
        return self.adif_inc * self.adif_noise_mult

    @property
    def quit_noise(self) -> float:
        return self.quit_inc * self.quit_noise_mult


class _Gauss:
    """Chunked standard normals; the inner loop draws a few at a time."""

    __slots__ = ("_rng", "_buf", "_i", "_n")

    def __init__(self, rng: np.random.Generator, n: int = 1 << 16):
        self._rng, self._n = rng, n
        self._buf = rng.standard_normal(n)
        self._i = 0

    def take(self, k: int):
        if self._i + k > self._n:
            self._buf = self._rng.standard_normal(self._n)
            self._i = 0
        out = self._buf[self._i:self._i + k]
        self._i += k
        return out


def run_trial(p: GS6Params, set_size: int, target_present: bool,
              quit_thresh: float, start_point: float,
              rng: np.random.Generator, gauss: _Gauss | None = None) -> dict:
    """One trial of the asynchronous diffuser.  Returns response code and RT."""
    g = gauss or _Gauss(rng)
    # stim[i] is +1 for the target, -1 for a distractor; the target is index 0
    stim = [-1.0] * set_size
    if target_present:
        stim[0] = 1.0
    diff = [0.0] * set_size
    n_in = 0
    quit_sig = 0.0
    qstart = False
    rt = 0
    scaled_qt = quit_thresh * (set_size / (max(SET_SIZES) * 0.5))
    n_selected = 0
    n_rejected = 0

    while True:
        rt += RT_STEP
        if rt > p.max_rt_ms:
            return {"resp": TNEG if not target_present else MISS, "rt": rt,
                    "n_selected": n_selected, "n_rejected": n_rejected,
                    "timeout": True}

        # --- selection every SELECT_TIME ms, if there is room -------------
        if rt % SELECT_TIME == 0 and n_in < p.adif_capacity:
            free = [i for i in range(set_size) if diff[i] == 0.0]
            if free:
                diff[free[int(rng.integers(len(free)))]] = start_point + 0.0001
                n_in += 1
                n_selected += 1

        # --- advance every item in the diffuser ---------------------------
        idx = [i for i in range(set_size) if diff[i] != 0.0]
        if idx:
            noise = g.take(len(idx))
            for j, i in enumerate(idx):
                diff[i] += (noise[j] * p.adif_noise + p.adif_inc) * stim[i]

        # --- clear rejected distractors -----------------------------------
        rejected_now = False
        for i in idx:
            if diff[i] < p.dist_thresh:
                diff[i] = 0.0
                n_in -= 1
                n_rejected += 1
                rejected_now = True
        if rejected_now:
            qstart = True

        # --- quit diffuser -------------------------------------------------
        if qstart:
            quit_sig += float(g.take(1)[0]) * p.quit_noise + p.quit_inc

        # --- termination tests (two independent ifs, as in the MATLAB) ----
        resp = 0
        if idx and max(diff[i] for i in idx) > p.targ_thresh:
            resp = HIT if target_present else FA
        if quit_sig > scaled_qt:
            resp = MISS if target_present else TNEG   # overrides, as in MATLAB
        if resp:
            return {"resp": resp, "rt": rt, "n_selected": n_selected,
                    "n_rejected": n_rejected, "timeout": False}


def run_block(prevalence: float = 0.5, n_trials: int = 2000,
              p: GS6Params | None = None, set_sizes=SET_SIZES,
              seed: int = 0) -> dict:
    """Run one prevalence condition; the adaptive state carries across trials."""
    p = p or GS6Params()
    rng = np.random.default_rng(seed)
    gauss = _Gauss(rng)

    quit_thresh = p.quit_thresh0
    start_point = prevalence / 2.0 - 0.25
    quit_up_step = p.quit_down_step / (p.miss_desired * (prevalence * 2.0))

    rows = []
    for _ in range(n_trials):
        ss = int(set_sizes[int(rng.integers(len(set_sizes)))])
        present = bool(rng.random() < prevalence)
        t = run_trial(p, ss, present, quit_thresh, start_point, rng, gauss)
        r = t["resp"]
        if r == HIT:
            start_point += p.start_inc
        elif r == FA:
            start_point -= p.start_dec
        elif r == MISS:
            quit_thresh += quit_up_step * (1.0 - prevalence)
        elif r == TNEG:
            quit_thresh -= p.quit_down_step * prevalence
        rows.append({"set_size": ss, "target_present": present, "resp": r,
                     "rt": t["rt"], "n_selected": t["n_selected"],
                     "n_rejected": t["n_rejected"],
                     "quit_thresh": quit_thresh, "start_point": start_point})
    return {"prevalence": prevalence, "trials": rows,
            "quit_thresh": quit_thresh, "start_point": start_point}


def summarise(block: dict, set_sizes=SET_SIZES) -> dict:
    """Slopes, error rates and skew from one :func:`run_block` result."""
    rows = block["trials"]
    hit_rt, tneg_rt = {}, {}
    miss_n, hit_n, fa_n, tneg_n = {}, {}, {}, {}
    for n in set_sizes:
        sel = [r for r in rows if r["set_size"] == n]
        hits = [r["rt"] for r in sel if r["resp"] == HIT]
        tns = [r["rt"] for r in sel if r["resp"] == TNEG]
        hit_rt[n] = float(np.mean(hits)) if hits else float("nan")
        tneg_rt[n] = float(np.mean(tns)) if tns else float("nan")
        hit_n[n] = len(hits)
        miss_n[n] = sum(1 for r in sel if r["resp"] == MISS)
        fa_n[n] = sum(1 for r in sel if r["resp"] == FA)
        tneg_n[n] = len(tns)

    def _slope(d):
        xs = np.array([n for n in set_sizes if not math.isnan(d[n])], float)
        ys = np.array([d[n] for n in xs], float)
        if len(xs) < 2:
            return float("nan"), float("nan")
        s, i = np.polyfit(xs, ys, 1)
        return float(s), float(i)

    tp_slope, tp_int = _slope(hit_rt)
    ta_slope, ta_int = _slope(tneg_rt)
    all_hits = [r["rt"] for r in rows if r["resp"] == HIT]
    return {
        "prevalence": block["prevalence"],
        "hit_rt": hit_rt, "tneg_rt": tneg_rt,
        "tp_slope": tp_slope, "tp_intercept": tp_int,
        "ta_slope": ta_slope, "ta_intercept": ta_int,
        "ratio": ta_slope / tp_slope if tp_slope else float("nan"),
        "miss_rate": {n: miss_n[n] / max(1, miss_n[n] + hit_n[n]) for n in set_sizes},
        "fa_rate": {n: fa_n[n] / max(1, fa_n[n] + tneg_n[n]) for n in set_sizes},
        "overall_miss": sum(miss_n.values()) / max(1, sum(miss_n.values()) + sum(hit_n.values())),
        "overall_fa": sum(fa_n.values()) / max(1, sum(fa_n.values()) + sum(tneg_n.values())),
        "hit_rt_skew": float(_skew(all_hits)) if len(all_hits) > 2 else float("nan"),
        "final_quit_thresh": block["quit_thresh"],
        "final_start_point": block["start_point"],
    }


def _skew(x) -> float:
    a = np.asarray(x, float)
    m, s = a.mean(), a.std()
    return float(np.mean(((a - m) / s) ** 3)) if s > 0 else float("nan")


if __name__ == "__main__":
    print("prev  TPslope  TAslope  ratio   miss    FA    skew   QTend")
    for prev in PREVALENCES:
        s = summarise(run_block(prevalence=prev, n_trials=4000, seed=11))
        print(f"{prev:4.1f} {s['tp_slope']:8.1f} {s['ta_slope']:8.1f} "
              f"{s['ratio']:6.2f} {s['overall_miss']:6.3f} {s['overall_fa']:6.3f} "
              f"{s['hit_rt_skew']:6.2f} {s['final_quit_thresh']:6.2f}")
