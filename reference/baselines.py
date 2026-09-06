"""Comparison models for the Wolfe, Palmer and Horowitz (2010) benchmark.

Every model here is a *trial-level* simulation: it takes a task, a set size
and target presence and returns a response and an RT.  None of them has a
display, an eye or an acuity function, so none of them can be asked about
fixations; what they can be asked is the question the project's validation
asks of gs-vision, namely how well the correct-RT quantiles and the error
rates of the three benchmark tasks are reproduced.  They exist so that the
gs-vision numbers in ``docs/RESULTS*.md`` can be read against the models the
literature already has, fitted to the same participants with the same
objective (``harness.fit.quantile_cost``) and scored with the same code
(``harness.evaluate.compare``).

The families:

``serial_fit``
    Serial self-terminating search with a preattentive feature stage
    (Treisman and Gelade 1980; the textbook model).  Feature search is one
    detection stage regardless of set size; conjunction and spatial search
    inspect items one at a time in random order with perfect memory, stop at
    the target and are exhaustive on absent trials.  A per-inspection miss
    probability and a motor error are its only error sources.  Its structural
    predictions are an absent-to-present slope ratio of 2 and flat miss rates.
``parallel_race``
    A parallel race with a capacity exponent (Townsend and Ashby 1983; the
    parallel competitor CGS beat in Moran et al. 2016).  Every item starts at
    once; item finishing times are Wald with rate ``mu * g / N**kappa`` for
    the target (``g`` is per-task guidance) and ``mu / N**kappa`` for
    distractors.  Present responses fire when the target finishes;
    absent responses wait for the slowest distractor.
``cgs``
    Competitive Guided Search (Moran, Zehetleitner, Mueller and Usher 2013),
    the published best fit to these data.  Luce-choice selection with target
    weight ``w_t``, Wald identification, full inhibition of rejected items and
    a quit unit that gains ``dw`` per rejection.  ``cgs`` shares the timing
    parameters across tasks and fits guidance and quitting per task;
    ``cgs_task`` is the paper's own protocol, all eight parameters per task.
``fixation_ho``
    The fixation-based account of Hulleman and Olivers (2017).  The unit is a
    250 ms fixation that examines up to ``k`` items (the functional visual
    field, per task); recently fixated items are remembered for ``memory``
    fixations and then forgotten; search stops when a fraction ``coverage``
    of the display has been examined.  Misses come from quitting early and
    from a per-fixation detection probability.
``gs6_pure``
    Wolfe's posted Guided Search 6 simulation (``reference/gs6_sim.py``),
    with a per-task target selection weight in place of the priority map,
    plus a response stage.  ``gs6_pure_posted`` keeps every engine value as
    posted and fits only guidance and the response stage; ``gs6_pure`` also
    fits the engine's rates.
``actr_stock``
    A timing mirror of ACT-R 7.31's own vision module driven by the usual
    find/attend/test production loop: a visual-location request (0 ms) and
    an attention shift (85 ms) inside three 50 ms productions, four finsts of
    3 s, random choice among unattended items, and the same measured response
    stage as gs-vision.  It is what a modeller gets without a search module.
    ``actr_stock`` is unfitted with the default four finsts (and a counting
    strategy so absent trials terminate); ``actr_stock_finst20`` raises the
    finst count so that memory is perfect; ``actr_stock_fit`` lets the
    attention latency, the number of productions per item, the finst count
    and the response times vary.  It is a mirror, not a run in ACT-R.

``simulate`` runs any of them through the same observer plan as the mirror
(``harness.protocol.observer_plan``: interleaved cells, synthetic practice),
and returns rows that ``harness.evaluate.model_frame(mirror=True)`` accepts.
"""
from __future__ import annotations

import math
import pathlib
import sys
from collections import deque
from typing import Sequence

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from harness.tasks import SET_SIZES, TASKS  # noqa: E402
from reference import gs6_sim  # noqa: E402

SIGMA = 0.1     # Wald noise, fixed as in CGS (Moran et al. 2013)
_HIT, _MISS, _FA, _TN = "hit", "miss", "fa", "tn"
MEASURED_RESPONSE = dict(t_nondecision=0.160, first_extra=0.150, switch_extra=0.100)


def _gamma(mean: float, cv: float, rng: np.random.Generator) -> float:
    """Gamma variate with the given mean and coefficient of variation."""
    if cv <= 1e-6:
        return mean
    shape = 1.0 / cv ** 2
    return float(rng.gamma(shape, mean / shape))


class Baseline:
    """One comparison model.

    ``bounds`` lists the fitted parameters as ``(name, low, high)``;
    ``defaults`` gives every parameter a value, fitted or not.  ``per_task``
    models are fitted separately per task and keep one value dict per task;
    the others keep one dict and address per-task parameters with a task
    suffix (``w_t_feature``).
    """
    name = "baseline"
    title = "baseline"
    bounds: list = []
    defaults: dict = {}
    per_task = False
    has_learning = False

    def __init__(self, values: dict | None = None):
        if self.per_task:
            self.v = {t: dict(self.defaults) | dict((values or {}).get(t, {})) for t in TASKS}
        else:
            shared = dict(self.defaults) | dict(values or {})
            self.v = {t: shared for t in TASKS}

    # -- helpers ------------------------------------------------------------
    @classmethod
    def n_fitted(cls) -> int:
        return len(cls.bounds) * (len(TASKS) if cls.per_task else 1)

    def values(self) -> dict:
        return self.v if self.per_task else self.v[TASKS[0]]

    def start_observer(self, task: str, rng: np.random.Generator) -> dict:
        return {"last_response": None}

    def respond(self, v: dict, search: float, found: bool, present: bool,
                rng: np.random.Generator, state: dict) -> dict:
        say = found
        if rng.random() < v.get("m", 0.0):
            say = not say
        rt = search + (v["t0_yes"] if say else v["t0_no"])
        if v.get("c", 0.0) > 0:
            rt += float(rng.exponential(1.0 / v["c"]))
        state["last_response"] = say
        return dict(response=say, correct=say == present, rt=rt,
                    label=(_HIT if say else _MISS) if present else (_FA if say else _TN))

    def run_trial(self, task: str, n: int, present: bool, rng: np.random.Generator,
                  state: dict) -> dict:
        raise NotImplementedError


# --------------------------------------------------------------------------
# Serial self-terminating search (Feature Integration Theory)
# --------------------------------------------------------------------------

class SerialFIT(Baseline):
    name = "serial_fit"
    title = "Serial self-terminating (FIT)"
    bounds = [("t_feature", 0.01, 0.30), ("t_item_conjunction", 0.005, 0.20),
              ("t_item_spatial", 0.01, 0.30), ("cv", 0.05, 1.5), ("p_miss", 0.0, 0.3),
              ("t0_yes", 0.15, 0.60), ("t0_no", 0.15, 0.60), ("c", 2.0, 60.0), ("m", 0.0, 0.05)]
    defaults = dict(t_feature=0.05, t_item_conjunction=0.03, t_item_spatial=0.08, cv=0.5,
                    p_miss=0.02, t0_yes=0.35, t0_no=0.35, c=12.0, m=0.01)

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        found, search, inspected = False, 0.0, 0
        if task == "feature":
            search = _gamma(v["t_feature"], v["cv"], rng)
            inspected = 1
            found = present and rng.random() >= v["p_miss"]
        else:
            order = rng.permutation(n)
            target = 0 if present else -1
            for i in order:
                search += _gamma(v[f"t_item_{task}"], v["cv"], rng)
                inspected += 1
                if i == target and rng.random() >= v["p_miss"]:
                    found = True
                    break
        out = self.respond(v, search, found, present, rng, state)
        return out | dict(search_time=search, n_fixations=inspected, n_rejected=inspected - int(found))


# --------------------------------------------------------------------------
# Parallel race with a capacity exponent
# --------------------------------------------------------------------------

class ParallelRace(Baseline):
    name = "parallel_race"
    title = "Parallel race (capacity exponent)"
    bounds = [("mu", 0.05, 2.0), ("theta", 0.01, 0.10), ("kappa", 0.0, 1.5),
              ("g_feature", 1.0, 50.0), ("g_conjunction", 1.0, 50.0), ("g_spatial", 1.0, 50.0),
              ("r_feature", 0.1, 20.0), ("r_conjunction", 0.1, 20.0), ("r_spatial", 0.1, 20.0),
              ("p_miss", 0.0, 0.3), ("t0_yes", 0.15, 0.60), ("t0_no", 0.15, 0.60),
              ("c", 2.0, 60.0), ("m", 0.0, 0.05)]
    defaults = dict(mu=0.25, theta=0.03, kappa=0.5, g_feature=10.0, g_conjunction=3.0,
                    g_spatial=1.0, r_feature=1.0, r_conjunction=1.0, r_spatial=1.0,
                    p_miss=0.02, t0_yes=0.35, t0_no=0.35, c=12.0, m=0.01)

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        # ``r`` is the task's processing rate for every item (how hard the
        # discrimination is), ``g`` the target's advantage over distractors.
        rates = np.full(n, v["mu"] * v[f"r_{task}"] / n ** v["kappa"])
        target_missed = present and rng.random() < v["p_miss"]
        if present and not target_missed:
            rates[0] *= v[f"g_{task}"]
        finish = rng.wald(v["theta"] / rates, v["theta"] ** 2 / SIGMA ** 2)
        if present and not target_missed:
            found, search = True, float(finish[0])
        else:
            found, search = False, float(finish.max())
        out = self.respond(v, search, found, present, rng, state)
        return out | dict(search_time=search, n_fixations=0, n_rejected=0 if found else n)


# --------------------------------------------------------------------------
# Competitive Guided Search (Moran et al. 2013)
# --------------------------------------------------------------------------

def _cgs_trial(w_t, dw, mu, theta, n, present, rng):
    """One CGS trial; returns (found, search_time, n_identified)."""
    dist_left = n - (1 if present else 0)
    w_quit, total, n_id, found = 0.0, 0.0, 0, False
    mean, shape = theta / mu, theta ** 2 / SIGMA ** 2
    while True:
        w_target = w_t if (present and not found) else 0.0
        w_sum = dist_left + w_target + w_quit
        if w_sum <= 0.0:
            break
        r = rng.random() * w_sum
        if r < w_quit:
            break
        r -= w_quit
        total += float(rng.wald(mean, shape))
        n_id += 1
        if r < w_target:
            found = True
            break
        dist_left -= 1
        w_quit += dw
    return found, total, n_id


class CGS(Baseline):
    name = "cgs"
    title = "Competitive Guided Search, shared timing"
    bounds = [("mu", 0.05, 2.0), ("theta", 0.01, 0.10), ("t0_yes", 0.15, 0.60), ("t0_no", 0.15, 0.60),
              ("c", 2.0, 60.0), ("m", 0.0, 0.05),
              ("w_t_feature", 0.5, 1000.0), ("dw_feature", 0.001, 1000.0),
              ("w_t_conjunction", 0.5, 50.0), ("dw_conjunction", 0.001, 5.0),
              ("w_t_spatial", 0.5, 20.0), ("dw_spatial", 0.001, 1.0)]
    # The handoff's transcription of the published values (reference/cgs.py).
    defaults = dict(mu=0.252, theta=0.029, t0_yes=0.413, t0_no=0.410, c=11.8, m=0.012,
                    w_t_feature=600.0, dw_feature=870.0, w_t_conjunction=4.96, dw_conjunction=0.162,
                    w_t_spatial=1.51, dw_spatial=0.019)

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        found, search, n_id = _cgs_trial(v[f"w_t_{task}"], v[f"dw_{task}"], v["mu"], v["theta"],
                                         n, present, rng)
        out = self.respond(v, search, found, present, rng, state)
        return out | dict(search_time=search, n_fixations=0, n_rejected=n_id - int(found))


class CGSTask(CGS):
    name = "cgs_task"
    title = "Competitive Guided Search, per task"
    per_task = True
    bounds = [("mu", 0.05, 2.0), ("theta", 0.01, 0.10), ("t0_yes", 0.15, 0.60), ("t0_no", 0.15, 0.60),
              ("c", 2.0, 60.0), ("m", 0.0, 0.05), ("w_t", 0.5, 1000.0), ("dw", 0.001, 1000.0)]
    defaults = dict(mu=0.252, theta=0.029, t0_yes=0.413, t0_no=0.410, c=11.8, m=0.012, w_t=1.51, dw=0.019)

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        found, search, n_id = _cgs_trial(v["w_t"], v["dw"], v["mu"], v["theta"], n, present, rng)
        out = self.respond(v, search, found, present, rng, state)
        return out | dict(search_time=search, n_fixations=0, n_rejected=n_id - int(found))


# --------------------------------------------------------------------------
# Fixation-based search (Hulleman and Olivers 2017)
# --------------------------------------------------------------------------

class FixationHO(Baseline):
    name = "fixation_ho"
    title = "Fixation-based (Hulleman and Olivers)"
    bounds = [("t_fix", 0.10, 0.40), ("cv", 0.05, 1.0),
              ("k_feature", 1.0, 30.0), ("k_conjunction", 1.0, 30.0), ("k_spatial", 1.0, 12.0),
              ("memory", 0.0, 8.0), ("coverage", 0.5, 1.0), ("d", 0.6, 1.0),
              ("t0_yes", 0.10, 0.60), ("t0_no", 0.10, 0.60), ("c", 2.0, 60.0), ("m", 0.0, 0.05)]
    defaults = dict(t_fix=0.25, cv=0.3, k_feature=30.0, k_conjunction=7.0, k_spatial=1.5,
                    memory=4.0, coverage=0.9, d=0.95, t0_yes=0.25, t0_no=0.25, c=12.0, m=0.01)
    max_fixations = 80

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        k = max(1, int(round(v[f"k_{task}"])))
        mem = int(round(v["memory"]))
        recent: deque | None = deque(maxlen=mem) if mem > 0 else None
        examined: set = set()
        found, search, n_fix = False, 0.0, 0
        target = 0 if present else -1
        while True:
            n_fix += 1
            search += _gamma(v["t_fix"], v["cv"], rng)
            excluded = set().union(*recent) if recent else set()
            cand = [i for i in range(n) if i not in excluded] or list(range(n))
            sample = rng.choice(cand, min(k, len(cand)), replace=False)
            sample = set(int(i) for i in sample)
            if recent is not None:
                recent.append(sample)
            examined |= sample
            if target in sample and rng.random() < v["d"]:
                found = True
                break
            if len(examined) >= v["coverage"] * n - 1e-9 or n_fix >= self.max_fixations:
                break
        out = self.respond(v, search, found, present, rng, state)
        return out | dict(search_time=search, n_fixations=n_fix, n_rejected=len(examined) - int(found))


# --------------------------------------------------------------------------
# Wolfe's posted GS6 engine with a target selection weight
# --------------------------------------------------------------------------

class GS6Pure(Baseline):
    name = "gs6_pure"
    title = "GS6 engine as posted, rates fitted"
    has_learning = True
    ENGINE = [("adif_inc", 0.02, 0.20), ("adif_noise_mult", 1.0, 4.0), ("quit_inc", 0.005, 0.10),
              ("quit_thresh0", 0.2, 6.0), ("quit_down_step", 0.0005, 0.05), ("miss_desired", 0.01, 0.15)]
    GUIDANCE = [("w_feature", 1.0, 1000.0), ("w_conjunction", 1.0, 50.0), ("w_spatial", 1.0, 20.0),
                ("t0_yes", 0.10, 0.60), ("t0_no", 0.10, 0.60), ("c", 2.0, 60.0)]
    bounds = ENGINE + GUIDANCE
    defaults = dict(adif_inc=0.05, adif_noise_mult=2.5, quit_inc=0.018, quit_thresh0=1.5,
                    quit_down_step=0.005, miss_desired=0.08, w_feature=100.0, w_conjunction=5.0,
                    w_spatial=1.0, t0_yes=0.30, t0_no=0.30, c=12.0)
    prevalence = 0.5

    def engine(self, v: dict) -> gs6_sim.GS6Params:
        return gs6_sim.GS6Params(adif_inc=v["adif_inc"], adif_noise_mult=v["adif_noise_mult"],
                                 quit_inc=v["quit_inc"], quit_thresh0=v["quit_thresh0"],
                                 quit_down_step=v["quit_down_step"], miss_desired=v["miss_desired"])

    def start_observer(self, task, rng):
        v = self.v[task]
        p = self.engine(v)
        return dict(last_response=None, p=p, quit_thresh=p.quit_thresh0,
                    start_point=self.prevalence / 2.0 - 0.25,
                    quit_up_step=p.quit_down_step / (p.miss_desired * (self.prevalence * 2.0)),
                    gauss=gs6_sim._Gauss(rng))

    def _trial(self, p, w, n, present, quit_thresh, start_point, rng, g):
        """gs6_sim.run_trial with weighted selection (target weight ``w``)."""
        stim = [-1.0] * n
        if present:
            stim[0] = 1.0
        diff = [0.0] * n
        n_in, quit_sig, qstart, rt = 0, 0.0, False, 0
        scaled_qt = quit_thresh * (n / (max(gs6_sim.SET_SIZES) * 0.5))
        n_selected = n_rejected = 0
        while True:
            rt += gs6_sim.RT_STEP
            if rt > p.max_rt_ms:
                return gs6_sim.MISS if present else gs6_sim.TNEG, rt, n_rejected, True
            if rt % gs6_sim.SELECT_TIME == 0 and n_in < p.adif_capacity:
                free = [i for i in range(n) if diff[i] == 0.0]
                if free:
                    if present and free[0] == 0 and w != 1.0:
                        total = w + len(free) - 1
                        r = rng.random() * total
                        pick = 0 if r < w else free[1 + int((r - w))] if len(free) > 1 else 0
                    else:
                        pick = free[int(rng.integers(len(free)))]
                    diff[pick] = start_point + 0.0001
                    n_in += 1
                    n_selected += 1
            idx = [i for i in range(n) if diff[i] != 0.0]
            if idx:
                noise = g.take(len(idx))
                for j, i in enumerate(idx):
                    diff[i] += (noise[j] * p.adif_noise + p.adif_inc) * stim[i]
            rejected_now = False
            for i in idx:
                if diff[i] < p.dist_thresh:
                    diff[i] = 0.0
                    n_in -= 1
                    n_rejected += 1
                    rejected_now = True
            if rejected_now:
                qstart = True
            if qstart:
                quit_sig += float(g.take(1)[0]) * p.quit_noise + p.quit_inc
            resp = 0
            if idx and max(diff[i] for i in idx) > p.targ_thresh:
                resp = gs6_sim.HIT if present else gs6_sim.FA
            if quit_sig > scaled_qt:
                resp = gs6_sim.MISS if present else gs6_sim.TNEG
            if resp:
                return resp, rt, n_rejected, False

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        p = state["p"]
        resp, rt_ms, n_rej, timed_out = self._trial(p, v[f"w_{task}"], n, present, state["quit_thresh"],
                                                    state["start_point"], rng, state["gauss"])
        say = resp in (gs6_sim.HIT, gs6_sim.FA)
        if not timed_out:
            if resp == gs6_sim.HIT:
                state["start_point"] += p.start_inc
            elif resp == gs6_sim.FA:
                state["start_point"] -= p.start_dec
            elif resp == gs6_sim.MISS:
                state["quit_thresh"] += state["quit_up_step"] * (1.0 - self.prevalence)
            else:
                state["quit_thresh"] -= p.quit_down_step * self.prevalence
        search = rt_ms / 1000.0
        rt = search + (v["t0_yes"] if say else v["t0_no"]) + float(rng.exponential(1.0 / v["c"]))
        state["last_response"] = say
        return dict(response=say, correct=say == present, rt=rt, search_time=search,
                    label=(_HIT if say else _MISS) if present else (_FA if say else _TN),
                    n_fixations=0, n_rejected=n_rej, timed_out=timed_out)


class GS6PurePosted(GS6Pure):
    name = "gs6_pure_posted"
    title = "GS6 engine as posted, guidance and response fitted"
    bounds = GS6Pure.GUIDANCE


# --------------------------------------------------------------------------
# ACT-R's stock vision module (timing mirror)
# --------------------------------------------------------------------------

class ACTRStock(Baseline):
    """Find/attend/test loop on the default vision module, at default timing."""
    name = "actr_stock"
    title = "ACT-R stock vision module, 4 finsts (mirror)"
    bounds: list = []
    max_trial_s = 20.0       # harness.run_batch.TIMEOUT_S
    defaults = dict(attn_latency=0.085, productions=3.0, finsts=4.0, count_strategy=1.0,
                    t0_yes=MEASURED_RESPONSE["t_nondecision"], t0_no=MEASURED_RESPONSE["t_nondecision"],
                    measured_extras=1.0, c=0.0, m=0.0)

    def run_trial(self, task, n, present, rng, state):
        v = self.v[task]
        per_item = round(v["productions"]) * 0.050 + v["attn_latency"]
        finsts = max(1, int(round(v["finsts"])))
        # Candidate set after the visual-location filter: the stock module
        # filters on any slot, so colour is free and orientation/shape cost an
        # attention shift each.
        if task == "feature":
            cand = [0] if present else []
        elif task == "conjunction":
            n_red_distractors = int(rng.binomial(n - (1 if present else 0), 0.5))
            cand = ([0] if present else []) + list(range(1, 1 + n_red_distractors))
        else:
            cand = list(range(n))
        recent: deque = deque(maxlen=finsts)
        search, attends, found, timed_out = 0.0, 0, False, False
        while True:
            avail = [i for i in cand if i not in recent]
            if not avail or (v["count_strategy"] and attends >= len(cand)):
                search += 0.050          # the production that notices the failed request
                break
            if search >= self.max_trial_s:
                # Fewer finsts than candidates and no counting strategy: the
                # loop revisits forever, and the harness's 20 s trial limit
                # ends it, exactly as it would in ACT-R.
                timed_out = True
                break
            pick = avail[int(rng.integers(len(avail)))]
            attends += 1
            search += per_item
            recent.append(pick)
            if present and pick == 0:
                found = True
                break
        say = found
        extra = 0.0
        if v["measured_extras"]:
            last = state["last_response"]
            extra = (MEASURED_RESPONSE["first_extra"] if last is None else
                     MEASURED_RESPONSE["switch_extra"] if say != last else 0.0)
        rt = search + (v["t0_yes"] if say else v["t0_no"]) + extra
        if v.get("c", 0.0) > 0:
            rt += float(rng.exponential(1.0 / v["c"]))
        if timed_out:
            return dict(response=None, correct=False, rt=float("nan"), search_time=search,
                        label="timeout", n_fixations=attends, n_rejected=attends, timed_out=True)
        state["last_response"] = say
        return dict(response=say, correct=say == present, rt=rt, search_time=search,
                    label=(_HIT if say else _MISS) if present else (_FA if say else _TN),
                    n_fixations=attends, n_rejected=attends - int(found))


class ACTRStockFinst20(ACTRStock):
    name = "actr_stock_finst20"
    title = "ACT-R stock vision module, 20 finsts (mirror)"
    defaults = ACTRStock.defaults | dict(finsts=20.0, count_strategy=0.0)


class ACTRStockFit(ACTRStock):
    name = "actr_stock_fit"
    title = "ACT-R stock vision module, timing fitted (mirror)"
    bounds = [("attn_latency", 0.0, 0.30), ("productions", 2.0, 3.0), ("finsts", 4.0, 20.0),
              ("t0_yes", 0.10, 0.60), ("t0_no", 0.10, 0.60), ("c", 2.0, 60.0)]
    defaults = ACTRStock.defaults | dict(finsts=20.0, count_strategy=0.0, measured_extras=0.0,
                                         t0_yes=0.30, t0_no=0.30, c=12.0)


# --------------------------------------------------------------------------
# PAAV (Nyamsuren and Taatgen 2013): timing mirror of the ACT-R 6 module
# --------------------------------------------------------------------------

class PAAV(Baseline):
    """The Pre-Attentive And Attentive Vision module, mirrored from its source.

    PAAV runs only on ACT-R 6, so this is a display-level mirror of
    ``paav-visual-module_2014.01.15.lisp`` driven by the request/attend/test
    production loop its search models use, with the same displays as
    gs-vision (``harness.tasks.make_display``).  What is mirrored:

    * acuity: feature ``f`` of an item of angular size ``s`` (the ``size``
      slot, square degrees) at eccentricity ``e`` is visible iff
      ``s > a_f e^2 - b_f e`` (Kieras 2010 as modified by PAAV; the noise
      term is disabled in the posted code), with the posted ``a``, ``b`` per
      feature; visible features enter iconic memory and persist 4 s;
    * bottom-up activation: for each item, the sum over the other items in
      iconic memory of the binary feature dissimilarity (both visible and
      different) divided by ``1 + sqrt(pixel distance)``, summed over the five
      feature dimensions (GS4 as simplified by PAAV);
    * top-down activation: per template feature, 1 if visible and matching,
      0.5 if not visible, 0 if visible and different, summed;
    * selection: ``1.1 * BU + 0.45 * TD + noise`` (logistic, scale
      ``:vis-act-s``), clamped at zero, highest wins, ties at random, among
      items not yet attended (attended marks are permanent in PAAV's
      abstract-location registry; the finst count is not enforced);
    * the visual decision threshold (``:relevancy higher``): once an object
      has been attended, candidates whose top-down sum is zero are removed,
      as are candidates no farther from gaze than that object was whose
      top-down sum does not exceed its top-down sum; an empty candidate set
      is an abstract-location failure and the model answers "absent";
    * timing: 0 ms for the abstract-location request, a saccade of
      20 ms + 2 ms/deg with Gaussian landing noise of SD 0.5 x item width and
      height, 50 ms encoding (``:move-attn-latency-new``), and one 50 ms
      production for each of request, attend and test.  (The posted
      ``calc-sacc-exec-time`` measures the saccade against ``(gaze-x, gaze-x)``
      rather than ``(gaze-x, gaze-y)``; the mirror uses the documented
      formula.)

    ``paav`` keeps the posted values and the measured response stage;
    ``paav_fit`` frees the noise, the map weights, the encoding time, the
    production count, an acuity scale and the response stage.
    """
    name = "paav"
    title = "PAAV, posted values (mirror)"
    bounds: list = []
    max_trial_s = 20.0
    ACUITY = dict(color=(0.104, 0.85), shape=(0.142, 0.96), shading=(0.147, 0.96),
                  orient=(0.1, 0.601), size=(0.14, 0.96))
    FEATURES = ("color", "shape", "shading", "orient", "size")
    TEMPLATE = {"feature": (("color", "red"),), "conjunction": (("color", "red"), ("orient", 0.0)),
                "spatial": (("shape", "two"),)}
    defaults = dict(productions=3.0, encoding=0.050, bu_w=1.1, td_w=0.45, s=0.0, acuity_scale=1.0,
                    persistence=4.0, gaze_noise=0.5, sacc_base=0.020, sacc_rate=0.002,
                    t0_yes=MEASURED_RESPONSE["t_nondecision"], t0_no=MEASURED_RESPONSE["t_nondecision"],
                    measured_extras=1.0, c=0.0, m=0.0)

    def run_trial(self, task, n, present, rng, state):
        from harness.tasks import SCREEN_CENTER_PX, deg2px, make_display, px2deg
        v = self.v[task]
        d = make_display(task, n, present, rng)
        items = d.items
        x = np.array([it.x_px for it in items], float)
        y = np.array([it.y_px for it in items], float)
        w = np.array([deg2px(it.w_deg) for it in items], float)
        h = np.array([deg2px(it.h_deg) for it in items], float)
        size = np.array([it.size_deg2 for it in items], float)
        vals = dict(color=np.array([it.color for it in items], object),
                    shape=np.array([it.shape for it in items], object),
                    shading=np.array([it.lum for it in items], float),
                    orient=np.array([it.orient for it in items], float),
                    size=size)
        target = d.target_index if present else -1
        pair_px = np.hypot(x[:, None] - x[None, :], y[:, None] - y[None, :])
        pair_factor = 1.0 + np.sqrt(pair_px)
        seen = {f: np.full(n, -np.inf) for f in self.FEATURES}
        attended = np.zeros(n, bool)
        gaze = np.array(SCREEN_CENTER_PX, float)
        t, attends, found, timed_out = 0.0, 0, False, False
        threshold = None            # (top-down sum, distance factor) of the last attended object
        prod = 0.050
        per_iter_prod = round(v["productions"]) * prod

        def refresh():
            ecc = np.array([px2deg(e) for e in np.hypot(x - gaze[0], y - gaze[1])])
            for f in self.FEATURES:
                a, b = self.ACUITY[f]
                thr = v["acuity_scale"] * (a * ecc ** 2 - b * ecc)
                seen[f][size > thr] = t

        refresh()
        while True:
            t += prod                                  # the request production
            known = {f: (t - seen[f]) <= v["persistence"] for f in self.FEATURES}
            in_memory = np.any(np.stack([known[f] for f in self.FEATURES]), axis=0)
            cand = np.flatnonzero(in_memory & ~attended)
            gaze_px = np.hypot(x - gaze[0], y - gaze[1])
            dist_factor = 1.0 + np.sqrt(gaze_px)
            td = np.zeros(n)
            for f, want in self.TEMPLATE[task]:
                match = vals[f] == want
                td += np.where(known[f], np.where(match, 1.0, 0.0), 0.5)
            if threshold is not None and len(cand):
                thr_td, thr_df = threshold
                keep = (td[cand] > 0) & ~((dist_factor[cand] <= thr_df) & (td[cand] <= thr_td))
                cand = cand[keep]
            if len(cand) == 0:
                t += prod                              # the production that notices the failure
                break
            if t >= self.max_trial_s:
                timed_out = True
                break
            mem = np.flatnonzero(in_memory)
            bu = np.zeros(n)
            for f in self.FEATURES:
                kf = known[f]
                differ = (vals[f][:, None] != vals[f][None, :]) & kf[:, None] & kf[None, :]
                contrib = np.where(differ, 1.0 / pair_factor, 0.0)
                contrib[:, ~in_memory] = 0.0
                np.fill_diagonal(contrib, 0.0)
                bu += contrib.sum(axis=1)
            act = v["bu_w"] * bu[cand] + v["td_w"] * td[cand]
            if v["s"] > 0:
                act = act + rng.logistic(0.0, v["s"], size=len(cand))
            act = np.maximum(act, 0.0)
            best = np.flatnonzero(act >= act.max() - 1e-12)
            pick = int(cand[best[int(rng.integers(len(best)))]])
            # attend: production, saccade, landing, encoding, test production
            t += per_iter_prod - prod
            ecc = px2deg(gaze_px[pick])
            t += v["sacc_base"] + v["sacc_rate"] * ecc
            gaze = np.array([x[pick] + rng.normal(0.0, v["gaze_noise"] * w[pick]),
                             y[pick] + rng.normal(0.0, v["gaze_noise"] * h[pick])])
            refresh()
            t += v["encoding"]
            attends += 1
            attended[pick] = True
            threshold = (float(td[pick]), float(dist_factor[pick]))
            if pick == target:
                found = True
                break
        search = t
        say = found
        extra = 0.0
        if v["measured_extras"]:
            last = state["last_response"]
            extra = (MEASURED_RESPONSE["first_extra"] if last is None else
                     MEASURED_RESPONSE["switch_extra"] if say != last else 0.0)
        rt = search + (v["t0_yes"] if say else v["t0_no"]) + extra
        if v.get("c", 0.0) > 0:
            rt += float(rng.exponential(1.0 / v["c"]))
        if timed_out:
            return dict(response=None, correct=False, rt=float("nan"), search_time=search,
                        label="timeout", n_fixations=attends, n_rejected=attends, timed_out=True)
        state["last_response"] = say
        return dict(response=say, correct=say == present, rt=rt, search_time=search,
                    label=(_HIT if say else _MISS) if present else (_FA if say else _TN),
                    n_fixations=attends, n_rejected=attends - int(found))


class PAAVFit(PAAV):
    name = "paav_fit"
    title = "PAAV, fitted (mirror)"
    bounds = [("s", 0.0, 1.0), ("bu_w", 0.0, 3.0), ("td_w", 0.0, 3.0), ("encoding", 0.02, 0.30),
              ("productions", 2.0, 3.0), ("acuity_scale", 0.3, 3.0),
              ("t0_yes", 0.10, 0.60), ("t0_no", 0.10, 0.60), ("c", 2.0, 60.0)]
    defaults = PAAV.defaults | dict(s=0.2, measured_extras=0.0, t0_yes=0.30, t0_no=0.30, c=12.0)


MODELS = {cls.name: cls for cls in (SerialFIT, ParallelRace, CGS, CGSTask, FixationHO, GS6Pure,
                                    GS6PurePosted, ACTRStock, ACTRStockFinst20, ACTRStockFit,
                                    PAAV, PAAVFit)}


# --------------------------------------------------------------------------
# Batch simulation and objective
# --------------------------------------------------------------------------

def simulate(model: Baseline, tasks: Sequence[str] = TASKS, set_sizes: Sequence[int] = SET_SIZES,
             n_per_cell: int = 300, seed: int = 0, practice: int = 30) -> list:
    """Every cell of every task through the shared observer plan.

    One observer per task, cells interleaved, synthetic practice discarded, as
    in ``reference.gs_hybrid.run_cells``; rows carry the fields
    ``harness.evaluate.model_frame(mirror=True)`` reads.
    """
    from harness.protocol import observer_plan
    rows = []
    for task in tasks:
        rng = np.random.default_rng(seed + TASKS.index(task) * 100003)
        state = model.start_observer(task, rng)
        order, _ = observer_plan(task, set_sizes, n_per_cell, seed, practice)
        for k, (n, present, is_practice, block) in enumerate(order):
            r = model.run_trial(task, int(n), bool(present), rng, state)
            if is_practice:
                continue
            r.setdefault("timed_out", False)
            r.update(task=task, set_size=int(n), target_present=bool(present),
                     subject_seed=seed, trial=k, practice=False, block=block)
            rows.append(r)
    return rows


def cell_cost(rows: list, task: str, target: dict) -> float:
    """``harness.fit.quantile_cost``'s formula on already simulated rows."""
    from harness.fit import cell_quantiles
    model = cell_quantiles(rows, task)
    total = 0.0
    for key, tgt in target.items():
        mq, tq = model[key]["q"], tgt["q"]
        rmse = 2000.0 if np.any(~np.isfinite(mq)) else float(np.sqrt(np.mean((mq - tq) ** 2)))
        derr = abs(model[key]["err"] - tgt["err"]) if np.isfinite(model[key]["err"]) else 1.0
        total += rmse + 10.0 * derr * 100.0 + 2000.0 * model[key].get("timeout_rate", 0.0)
    return total / len(target)


def cost(model: Baseline, targets: dict, n_per_cell: int, seed: int,
         tasks: Sequence[str] = TASKS) -> float:
    rows = simulate(model, tasks=tasks, n_per_cell=n_per_cell, seed=seed)
    return float(np.mean([cell_cost(rows, t, targets[t]) for t in tasks]))


def unpack(x, bounds, base: dict) -> dict:
    out = dict(base)
    for (name, _lo, _hi), val in zip(bounds, x):
        out[name] = float(val)
    return out


def _objective(x, model_name, bounds, base, targets, n_per_cell, seed, tasks):
    """Module level so that scipy's worker pool can pickle it."""
    cls = MODELS[model_name]
    values = unpack(x, bounds, base)
    model = cls({t: values for t in tasks} if cls.per_task else values)
    return cost(model, targets, n_per_cell, seed, tasks)


def de_fit(model_name: str, targets: dict, n_per_cell: int = 200, maxiter: int = 60,
           popsize: int = 8, seed: int = 0, workers: int = 1, tasks: Sequence[str] = TASKS,
           verbose: bool = False):
    """Differential evolution over the model's bounds; returns (values, cost, result)."""
    from functools import partial
    from scipy.optimize import differential_evolution

    cls = MODELS[model_name]
    base = dict(cls.defaults)
    bounds = cls.bounds
    x0 = [min(max(base[n], lo), hi) for n, lo, hi in bounds]
    obj = partial(_objective, model_name=model_name, bounds=bounds, base=base, targets=targets,
                  n_per_cell=n_per_cell, seed=seed, tasks=tuple(tasks))
    extra = dict(workers=workers, updating="deferred") if workers != 1 else {}
    res = differential_evolution(obj, [(lo, hi) for _n, lo, hi in bounds], seed=seed, maxiter=maxiter,
                                 popsize=popsize, tol=0.005, polish=False, disp=verbose,
                                 init="latinhypercube", x0=x0, **extra)
    return unpack(res.x, bounds, base), float(res.fun), res
