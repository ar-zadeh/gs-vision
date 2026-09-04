"""Python mirror of the gs-vision module specified in the handoff, sections 5.2 to 5.6.

Why this file exists
--------------------
Neither Competitive Guided Search (``cgs.py``) nor the GS6 diffuser simulation
(``gs6_sim.py``) is the architecture being built, so neither predicts what the
handoff's defaults will do.  This is a trial-level simulation of *this*
module: same parameter names, same channel rules, same EPIC acuity, same
centred Luce weights, same IOR ring, same two quit rules, same EMMA saccade
arithmetic, run on the displays from ``harness/tasks.py``.  It is the fitting
target of section 8.4 and the cross-check for the Lisp port at the end of
phase 4.

Three places where the handoff underdetermines the model
--------------------------------------------------------
Recorded here rather than resolved silently; the Lisp module makes the same
three choices, and the module README repeats them.

1. **Adaptive quitting threshold, units.**  Section 5.6 says the threshold is
   "in units of rejections", that its initial value is ``qt_init * N_eff``,
   and that the step is ``qt_step * N_eff``.  Taken literally the state would
   drift whenever ``N_eff`` changes between trials.  We keep a persistent
   unitless ``qt_scale`` (initially ``qt_init``) and test
   ``rejections >= qt_scale * N_eff``, moving ``qt_scale`` by ``qt_step``.
   That is algebraically the handoff's rule at fixed ``N_eff`` and is also
   what the GS6 MATLAB does: a persistent threshold scaled by set size at test
   time.
2. **Which items enter the CGS quit denominator.**  Section 5.6 says "the
   centred weights of section 5.4 step 1", and step 1 restricts eligibility to
   items inside the attentional functional visual field and outside the
   diffuser.  Either filter can empty the denominator while the search is
   still going, which makes ``p_quit`` exactly 1 and quits the trial instead
   of saccading or waiting.  Competitive Guided Search zeroes an item's weight
   when the item is *rejected*, so we read the phrase as naming the weight
   formula and take the denominator over every item not in the IOR ring,
   display-wide, items being identified included.  With the literal reading
   the spatial-configuration miss rate at set size 3 is over 40 percent.
3. **What "entry in iconic memory" means.**  A feature is in iconic memory for
   ``iconic_span`` seconds after it was last available.  The *location* entry
   persists for as long as the item is in the visicon, so that an item all of
   whose features have decayed still contributes the 0.5 "unknown" term to the
   top-down map rather than vanishing.
4. **Peripheral guidance needs a fourth saccade trigger.**  Section 5.4 step 1
   restricts covert selection to items inside the attentional functional
   visual field, and section 5.6's own worked example requires feature search
   to find the target *before* rejecting anything (its effective set size is 1,
   so one rejection ends the trial).  Those two are inconsistent whenever the
   target sits outside the 8 deg field, which is 60 percent of the 22.5 deg
   benchmark display: the model is forced to grab a nearby distractor, reject
   it, and quit.  So selection consults the priority map *globally*: if the
   highest-priority eligible item is outside the attentional field, no covert
   selection happens on that cycle and a saccade to that item is requested
   instead.  The attentional field keeps its meaning (covert identification is
   limited to 8 deg); what changes is that the winner of the priority
   competition is always what happens next, which is what Guided Search means
   by guidance.  Without this the feature-search miss rate is about 30 percent
   at set size 18 and its RT falls with set size.
5. **A dead end is only a dead end when the diffuser is empty.**  Section 5.5
   ends "if still none, quit".  Items already being identified are not
   nothing, so the quit fires only when there is also nothing in flight.

Two things that are deliberately not in the Lisp module
-------------------------------------------------------
``motor_error`` and ``t_nondecision`` model the response stage, which in ACT-R
belongs to the productions and the motor module, not to vision.  They are here
because this file has to produce comparable RTs and non-zero false-alarm rates
on its own.  Slopes do not depend on either.
"""

from __future__ import annotations

import heapq
import math
from collections import deque
from dataclasses import dataclass, field, replace
from typing import Sequence

import numpy as np

import sys
import pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from harness.tasks import (SCREEN_CENTER_PX, SET_SIZES, TASKS, TEMPLATES,  # noqa: E402
                           Display, make_display, px2deg)

GUIDING_DEFAULT = ("color", "orient", "size", "lum")


# --------------------------------------------------------------------------
# Parameters (section 6 of the handoff; names match the :gs-* parameters)
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class GSParams:
    guiding_features: tuple = GUIDING_DEFAULT
    select_interval: float = 0.050
    diffuser_capacity: int = 5
    choice_beta: float = 4.0
    id_drift: float = 0.25          # Wald mu
    id_threshold: float = 0.03      # Wald theta; sigma fixed at 0.1
    quit_delta: float = 0.02
    memory: int = 4                 # IOR ring size
    attn_fvf: float = 8.0           # deg
    explore_fvf: float = 12.0       # deg
    max_fixation: float = 0.4       # s
    iconic_span: float = 4.0        # s
    acuity_theta: tuple = (("color", 0.10), ("orient", 0.20), ("shape", 0.40),
                           ("size", 0.20), ("lum", 0.10))
    acuity_sigma: float = 0.5
    w_bu: float = 0.5
    w_td: float = 1.0
    w_h: float = 0.3
    w_v: float = 0.0
    w_s: float = 1.0
    w_e: float = 0.02
    noise: float = 0.2              # logistic scale
    priming_tau: float = 10.0
    qt_init: float = 1.0
    qt_step: float = 0.05
    error_goal: float = 0.08
    feedback_window: int = 50
    emma: bool = True
    # EMMA (extras/emma/emma.lisp defaults)
    saccade_feat_time: float = 0.050
    saccade_init_time: float = 0.050
    saccade_base_time: float = 0.020
    eye_saccade_rate: float = 0.002
    visual_encoding_factor: float = 0.006
    visual_encoding_exponent: float = 0.4
    vis_obj_freq: float = 0.1
    visual_attention_latency: float = 0.085
    # response stage: harness-only, see the module docstring
    motor_error: float = 0.012
    t_nondecision: float = 0.45
    max_trial_s: float = 15.0

    @property
    def theta_map(self) -> dict:
        return dict(self.acuity_theta)

    @property
    def id_mean(self) -> float:
        return self.id_threshold / self.id_drift

    @property
    def id_shape(self) -> float:
        return self.id_threshold ** 2 / 0.1 ** 2


DEFAULTS = GSParams()


# --------------------------------------------------------------------------
# Channels (section 5.1)
# --------------------------------------------------------------------------

ORIENT_RAMP = 10.0   # deg of linear ramp either side of a channel boundary
ORIENT_EDGES = (-67.5, -22.5, 22.5, 67.5)


def color_channels(color: str, hue) -> dict:
    """Categorical colour channel.  ``color`` wins if ``hue`` is absent."""
    if hue is not None:
        h = float(hue) % 360.0
        for lo, hi, name in ((330, 30, "red"), (30, 90, "yellow"),
                             (90, 150, "green"), (150, 270, "blue")):
            if lo > hi:
                if h >= lo or h < hi:
                    return {name: 1.0}
            elif lo <= h < hi:
                return {name: 1.0}
        return {"blue": 1.0}
    return {str(color): 1.0}


def orient_channels(theta) -> dict:
    """steep / shallow / left / right with a ``+-ORIENT_RAMP`` soft boundary.

    Guided Search 2 lets an item drive a steep/shallow channel and a left/right
    channel at once.  The exclusive binning here is the simplification the
    handoff records in section 5.1; only the boundaries are softened.
    """
    if theta is None:
        return {}
    t = ((float(theta) + 90.0) % 180.0) - 90.0

    def hard(x):
        a = abs(x)
        if a < 22.5:
            return "steep"
        if a > 67.5:
            return "shallow"
        return "right" if x > 0 else "left"

    for edge in ORIENT_EDGES:
        d = t - edge
        if abs(d) < ORIENT_RAMP:
            below, above = hard(edge - ORIENT_RAMP), hard(edge + ORIENT_RAMP)
            if below != above:
                w = (d + ORIENT_RAMP) / (2 * ORIENT_RAMP)   # 0 at low side
                return {below: 1.0 - w, above: w}
    return {hard(t): 1.0}


def _tercile_channel(v, lo, hi, names) -> dict:
    if v is None:
        return {}
    if hi <= lo:
        return {names[1]: 1.0}
    f = (float(v) - lo) / (hi - lo)
    if f < 1 / 3:
        return {names[0]: 1.0}
    if f < 2 / 3:
        return {names[1]: 1.0}
    return {names[2]: 1.0}


SIZE_NAMES = ("small", "medium", "large")
LUM_NAMES = ("dark", "mid", "bright")


def channel_overlap(a: dict, b: dict) -> float:
    """1.0 when two channel vectors coincide, 0.0 when they are disjoint."""
    if not a or not b:
        return 0.0
    keys = set(a) | set(b)
    return 1.0 - 0.5 * sum(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in keys)


def channel_distance(a: dict, b: dict) -> float:
    if not a or not b:
        return 0.0
    keys = set(a) | set(b)
    return 0.5 * sum(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in keys)


# --------------------------------------------------------------------------
# Model
# --------------------------------------------------------------------------

_HIT, _MISS, _FA, _TN = "hit", "miss", "fa", "tn"


@dataclass
class _Item:
    """Per-trial view of one display element."""
    idx: int
    x: float
    y: float
    size_deg: float          # mean of width and height, degrees
    raw: dict                # feature name -> raw value
    channels: dict           # feature name -> channel dict
    is_target: bool
    salience: float | None = None
    prior: float = 0.0


class GSHybrid:
    """One simulated observer.  Adaptive state persists across trials."""

    def __init__(self, params: GSParams = DEFAULTS, seed: int = 0):
        self.p = params
        self.rng = np.random.default_rng(seed)
        self.qt_scale = params.qt_init
        self.priming: dict = {}            # (dim, channel) -> [trace, tstamp]
        self.feedback: deque = deque(maxlen=params.feedback_window)
        self.clock = 0.0                   # a running clock for priming decay
        self.last_saccade = None           # (amplitude_deg, direction_rad)

    # -- priming ----------------------------------------------------------
    def _trace(self, key) -> float:
        v = self.priming.get(key)
        if v is None:
            return 0.0
        tr, ts = v
        return tr * math.exp(-(self.clock - ts) / self.p.priming_tau)

    def _bump(self, key):
        self.priming[key] = [self._trace(key) + 1.0, self.clock]

    @property
    def prevalence(self) -> float:
        """Proportion of target-present feedbacks; 0.5 until 10 exist."""
        if len(self.feedback) < 10:
            return 0.5
        present = sum(1 for f in self.feedback if f in (_HIT, _MISS))
        return max(0.02, min(0.98, present / len(self.feedback)))

    def feedback_outcome(self, outcome: str, n_eff: float):
        """The ``gs-feedback`` request: update adaptive threshold and priming."""
        p = self.p
        if outcome == _TN:
            self.qt_scale = max(0.0, self.qt_scale - p.qt_step)
        elif outcome == _MISS:
            denom = p.error_goal * self.prevalence * 2.0
            self.qt_scale += p.qt_step / max(1e-6, denom)
        self.feedback.append(outcome)

    # -- display preparation ----------------------------------------------
    def _prepare(self, display: Display) -> list:
        sizes = [it.size_deg2 for it in display.items]
        lums = [it.lum for it in display.items]
        s_lo, s_hi = min(sizes), max(sizes)
        l_lo, l_hi = min(lums), max(lums)
        out = []
        for i, it in enumerate(display.items):
            raw = {"color": it.color, "orient": it.orient, "size": it.size_deg2,
                   "lum": it.lum, "shape": it.shape}
            ch = {
                "color": color_channels(it.color, it.hue),
                "orient": orient_channels(it.orient),
                "size": _tercile_channel(it.size_deg2, s_lo, s_hi, SIZE_NAMES),
                "lum": _tercile_channel(it.lum, l_lo, l_hi, LUM_NAMES),
                "shape": {str(it.shape): 1.0},
            }
            out.append(_Item(idx=i, x=float(it.x_px), y=float(it.y_px),
                             size_deg=0.5 * (it.w_deg + it.h_deg),
                             raw=raw, channels=ch, is_target=it.is_target))
        return out

    def _template_channels(self, template: dict, items: list) -> dict:
        """Map template values onto channels using the display's terciles."""
        sizes = [i.raw["size"] for i in items]
        lums = [i.raw["lum"] for i in items]
        out = {}
        for k, v in template.items():
            if k == "color":
                out[k] = color_channels(v, None if isinstance(v, str) else v)
            elif k == "orient":
                out[k] = orient_channels(v)
            elif k == "size":
                out[k] = _tercile_channel(v, min(sizes), max(sizes), SIZE_NAMES)
            elif k == "lum":
                out[k] = _tercile_channel(v, min(lums), max(lums), LUM_NAMES)
            else:
                out[k] = {str(v): 1.0}
        return out

    # -- acuity (section 5.2) ---------------------------------------------
    def _ecc(self, it: _Item, eye) -> float:
        return px2deg(math.hypot(it.x - eye[0], it.y - eye[1]))

    def _draw_availability(self, items, eye, iconic, t):
        """One availability draw per fixation per item per feature."""
        theta = self.p.theta_map
        sig = self.p.acuity_sigma
        for it in items:
            e = self._ecc(it, eye)
            for f, val in it.raw.items():
                if val is None:
                    continue
                th = theta.get(f)
                if th is None:
                    continue
                # P(s > N(theta*e, sigma)) = Phi((s - theta*e)/sigma)
                z = (it.size_deg - th * e) / sig
                pav = 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))
                if self.rng.random() < pav:
                    iconic[it.idx][f] = t

    def _available(self, iconic, idx, t) -> set:
        span = self.p.iconic_span
        return {f for f, ts in iconic[idx].items() if t - ts <= span}

    # -- priority map (section 5.3) ---------------------------------------
    def _priority(self, items, iconic, eye, tmpl_ch, t) -> dict:
        p = self.p
        guiding = [g for g in p.guiding_features]
        n = len(items)
        avail = {it.idx: self._available(iconic, it.idx, t) for it in items}

        # -- bottom-up over the 8 nearest neighbours, in degrees ----------
        bu = {}
        if items[0].salience is not None:
            smax = max(abs(i.salience or 0.0) for i in items) or 1.0
            bu = {i.idx: (i.salience or 0.0) / smax for i in items}
        else:
            deg = {}
            for a in items:
                for b in items:
                    if a.idx < b.idx:
                        d = px2deg(math.hypot(a.x - b.x, a.y - b.y))
                        deg[(a.idx, b.idx)] = deg[(b.idx, a.idx)] = d
            for a in items:
                nb = sorted((deg[(a.idx, b.idx)], b.idx) for b in items if b.idx != a.idx)[:8]
                tot = 0.0
                for d, j in nb:
                    other = items[j]
                    s = 0.0
                    for k in guiding:
                        if k in avail[a.idx] and k in avail[j]:
                            s += channel_distance(a.channels[k], other.channels[k])
                    tot += s / max(1.0, d)
                bu[a.idx] = tot / max(1, len(nb))

        # -- top-down, guiding template features only ---------------------
        guide_keys = [k for k in tmpl_ch if k in guiding]
        td = {}
        if not guide_keys:
            td = {i.idx: 1.0 for i in items}       # no guidance available
        else:
            for it in items:
                s = 0.0
                for k in guide_keys:
                    if k not in avail[it.idx]:
                        s += 0.5                    # PAAV uncertainty rule
                    else:
                        s += channel_overlap(it.channels[k], tmpl_ch[k])
                td[it.idx] = s / len(guide_keys)

        # -- history / priming --------------------------------------------
        hist = {}
        for it in items:
            s = 0.0
            for k in guiding:
                if k in avail[it.idx]:
                    for cname, act in it.channels[k].items():
                        s += act * self._trace((k, cname))
            hist[it.idx] = s

        def _norm(d):
            m = max(d.values()) if d else 0.0
            return {k: (v / m if m > 0 else 0.0) for k, v in d.items()}

        bu, td_n, hist = _norm(bu), _norm(td), _norm(hist)

        out = {}
        for it in items:
            eps = p.noise * math.log(max(1e-12, u := self.rng.random()) / max(1e-12, 1.0 - u))
            out[it.idx] = (p.w_bu * bu[it.idx] + p.w_td * td_n[it.idx]
                           + p.w_h * hist[it.idx] + p.w_v * 0.0
                           + p.w_s * it.prior - p.w_e * self._ecc(it, eye) + eps)
        return out, td

    # -- EMMA arithmetic (section 5.5) ------------------------------------
    def _saccade_time(self, amplitude_deg: float, direction: float) -> float:
        p = self.p
        if self.last_saccade is None:
            nfeat = 3                                   # style change
        else:
            r0, th0 = self.last_saccade
            nfeat = 0
            if abs(amplitude_deg - r0) > 2.0:           # distances match within 2 deg
                nfeat += 1
            dth = abs((direction - th0 + math.pi) % (2 * math.pi) - math.pi)
            if dth > math.pi / 2:                       # directions within 90 deg
                nfeat += 1
        prep = p.saccade_feat_time * nfeat
        exe = p.saccade_init_time + p.saccade_base_time + p.eye_saccade_rate * amplitude_deg
        self.last_saccade = (amplitude_deg, direction)
        return prep + exe

    def _raw_encoding(self, ecc_deg: float) -> float:
        p = self.p
        return (p.visual_encoding_factor * (-math.log(p.vis_obj_freq))
                * math.exp(p.visual_encoding_exponent * ecc_deg))

    def _encoding_time(self, ecc_deg: float, direction: float = 0.0):
        """Encoding cost of a hit, with EMMA's remaining-proportion rule.

        EMMA computes ``K (-ln f) exp(k eps)`` at the current eccentricity.
        When that exceeds the time to saccade there, the eye moves and the
        encoding restarts at the new, foveal eccentricity, keeping only the
        proportion that was left (``emma.lisp``, ``complete-eye-move``).
        Without the second half a covert hit at 8 deg would cost 340 ms and at
        12 deg 1.7 s, which is EMMA's peripheral estimate, not its behaviour.

        Returns ``(total_seconds, moved_eye)``.
        """
        p = self.p
        if not p.emma:
            return p.visual_attention_latency, False
        enc = self._raw_encoding(ecc_deg)
        sacc = (p.saccade_init_time + p.saccade_base_time
                + p.eye_saccade_rate * ecc_deg)
        if enc <= sacc:
            return enc, False
        sacc = self._saccade_time(ecc_deg, direction)
        remaining = max(0.0, 1.0 - sacc / enc)
        return sacc + remaining * self._raw_encoding(0.5), True

    # -- one trial ---------------------------------------------------------
    def run_trial(self, display: Display, template: dict | None = None,
                  stop: str = "both") -> dict:
        p = self.p
        rng = self.rng
        template = template if template is not None else TEMPLATES[display.task]
        items = self._prepare(display)
        tmpl_ch = self._template_channels(template, items)

        eye = [float(SCREEN_CENTER_PX[0]), float(SCREEN_CENTER_PX[1])]
        iconic = {i.idx: {} for i in items}
        diffuser: dict = {}
        ior: deque = deque(maxlen=p.memory)
        quit_weight = 0.0
        rejections = 0
        t = 0.0
        fixations = [];  fix_start = 0.0
        saccade_flight = False
        last_landed_on = None
        self.last_saccade = None

        self._draw_availability(items, eye, iconic, t)
        prio, td = self._priority(items, iconic, eye, tmpl_ch, t)
        n_eff = max(1.0, sum(1 for v in td.values() if v >= 0.5))
        qt = self.qt_scale * n_eff

        queue: list = []
        seq = 0

        def push(when, kind, payload=None):
            nonlocal seq
            seq += 1
            heapq.heappush(queue, (when, seq, kind, payload))

        def eligible(fvf=None):
            out = []
            for it in items:
                if it.idx in ior or it.idx in diffuser:
                    continue
                if fvf is not None and self._ecc(it, eye) > fvf:
                    continue
                out.append(it.idx)
            return out

        def centred_weights(idxs):
            if not idxs:
                return []
            pbar = sum(prio[i] for i in idxs) / len(idxs)
            return [math.exp(min(50.0, p.choice_beta * (prio[i] - pbar))) for i in idxs]

        outcome = {"result": None, "reason": None, "item": None}

        def request_saccade(to=None):
            nonlocal saccade_flight
            if saccade_flight:
                return
            pend = [i for i, d in diffuser.items() if d["pending"]]
            if pend:
                tgt = pend[0]
            elif to is not None:
                tgt = to
            else:
                cand = eligible(p.explore_fvf) or eligible(None)
                if not cand:
                    # Nothing left to look at.  Only a genuine dead end if the
                    # diffuser is also empty; otherwise the in-flight items
                    # still have to finish.
                    if not diffuser:
                        outcome["result"], outcome["reason"] = "quit", "no-candidate"
                    return
                tgt = max(cand, key=lambda i: prio[i])
            it = items[tgt]
            dx, dy = it.x - eye[0], it.y - eye[1]
            amp = px2deg(math.hypot(dx, dy))
            push(t + self._saccade_time(amp, math.atan2(-dy, dx)), "land", tgt)
            saccade_flight = True

        def do_reject(i):
            nonlocal quit_weight, rejections
            diffuser.pop(i, None)
            ior.append(i)
            quit_weight += p.quit_delta
            rejections += 1
            if stop in ("cgs", "both"):
                # Competitive Guided Search zeroes an item's weight when it is
                # *rejected*, not while it is being identified, so items in the
                # diffuser stay in the denominator.  See deviation 2.
                w = centred_weights([it.idx for it in items if it.idx not in ior])
                denom = sum(w) + quit_weight
                if denom > 0 and rng.random() < quit_weight / denom:
                    outcome["result"], outcome["reason"] = "quit", "cgs"
                    return
            if stop in ("adaptive", "both") and rejections >= qt:
                outcome["result"], outcome["reason"] = "quit", "threshold"

        push(p.select_interval, "select")
        push(p.max_fixation, "fixtimeout")

        while outcome["result"] is None and queue:
            t, _, kind, payload = heapq.heappop(queue)
            if t > p.max_trial_s:
                outcome["result"], outcome["reason"] = "quit", "timeout"
                break

            if kind == "select":
                if len(diffuser) < p.diffuser_capacity:
                    everywhere = eligible(None)
                    winner = max(everywhere, key=lambda i: prio[i]) if everywhere else None
                    near = eligible(p.attn_fvf)
                    if winner is not None and winner not in near:
                        # Peripheral guidance (deviation 4 in the docstring):
                        # the priority winner cannot be selected covertly, so
                        # look at it instead of covertly grabbing a loser.
                        request_saccade(to=winner)
                    elif near:
                        w = np.array(centred_weights(near), float)
                        pick = near[int(rng.choice(len(near), p=w / w.sum()))]
                        diffuser[pick] = {"pending": False, "foveated": False}
                        dt = float(rng.wald(p.id_mean, p.id_shape))
                        push(t + dt, "decide", pick)
                    else:
                        request_saccade()
                push(t + p.select_interval, "select")

            elif kind == "decide":
                i = payload
                if i not in diffuser:
                    continue
                avail = self._available(iconic, i, t)
                missing = [k for k in template if k not in avail]
                if missing:
                    if diffuser[i]["foveated"] or last_landed_on == i:
                        do_reject(i)                     # still invisible at the fovea
                    else:
                        diffuser[i]["pending"] = True
                        request_saccade()
                else:
                    ok = all(channel_overlap(items[i].channels[k], tmpl_ch[k]) > 0.5
                             for k in template)
                    if ok:
                        outcome["result"], outcome["item"] = "found", i
                        outcome["reason"] = "hit"
                        dx, dy = items[i].x - eye[0], items[i].y - eye[1]
                        enc, moved = self._encoding_time(
                            self._ecc(items[i], eye), math.atan2(-dy, dx))
                        if moved:
                            eye = [items[i].x, items[i].y]
                            fixations.append((fix_start, eye[0], eye[1], t - fix_start))
                            fix_start = t
                        t = t + enc
                    else:
                        do_reject(i)

            elif kind == "land":
                saccade_flight = False
                tgt = items[payload]
                dist_px = math.hypot(tgt.x - eye[0], tgt.y - eye[1])
                sd = 0.1 * dist_px
                eye = [tgt.x + rng.normal(0.0, sd), tgt.y + rng.normal(0.0, sd)]
                fixations.append((fix_start, eye[0], eye[1], t - fix_start))
                fix_start = t
                last_landed_on = payload
                self._draw_availability(items, eye, iconic, t)
                prio, _ = self._priority(items, iconic, eye, tmpl_ch, t)
                push(t + p.max_fixation, "fixtimeout")
                for i, d in diffuser.items():
                    if d["pending"]:
                        d["pending"] = False
                        if i == payload:
                            d["foveated"] = True
                        push(t + 0.050, "decide", i)

            elif kind == "fixtimeout":
                if t - fix_start >= p.max_fixation - 1e-9:
                    request_saccade()

        if outcome["result"] is None:
            outcome["result"], outcome["reason"] = "quit", "exhausted"

        # -- response stage ---------------------------------------------------
        found = outcome["result"] == "found"
        say_present = found
        if rng.random() < p.motor_error:
            say_present = not say_present
        rt = t + p.t_nondecision
        correct = say_present == display.target_present
        if display.target_present:
            label = _HIT if say_present else _MISS
        else:
            label = _FA if say_present else _TN

        if label == _HIT and outcome["item"] is not None:
            self.clock += rt
            for k in p.guiding_features:
                for cname in items[outcome["item"]].channels.get(k, {}):
                    self._bump((k, cname))
        else:
            self.clock += rt

        self.feedback_outcome(label, n_eff)

        return {
            "task": display.task, "set_size": display.set_size,
            "target_present": display.target_present,
            "response": say_present, "correct": correct, "label": label,
            "rt": rt, "search_time": t,
            "n_fixations": len(fixations), "n_rejected": rejections,
            "quit_reason": outcome["reason"], "n_eff": n_eff,
            "qt": qt, "fixations": fixations,
        }


# --------------------------------------------------------------------------
# Batch helpers
# --------------------------------------------------------------------------

def run_cells(params: GSParams = DEFAULTS, tasks: Sequence[str] = TASKS,
              set_sizes: Sequence[int] = SET_SIZES, n_per_cell: int = 300,
              seed: int = 0, keep_fixations: bool = False,
              burn_in: float = 0.25) -> list:
    """Run every task x set size x presence cell and return trial records.

    One simulated observer per task, trials interleaved in random order so the
    adaptive quitting threshold sees a realistic mixture.  The first
    ``burn_in`` fraction of each observer's trials is run but discarded, since
    the threshold starts at ``qt_init`` and has to converge.
    """
    rows = []
    for task in tasks:
        model = GSHybrid(params, seed=seed)                 # one observer per task
        rng = np.random.default_rng(seed + 1000)
        order = [(n, pr) for n in set_sizes for pr in (True, False)] * n_per_cell
        rng.shuffle(order)
        cut = int(len(order) * burn_in)
        for k, (n, present) in enumerate(order):
            d = make_display(task, n, present, rng)
            r = model.run_trial(d)
            if k < cut:
                continue
            if not keep_fixations:
                r.pop("fixations", None)
            rows.append(r)
    return rows


def run_prevalence(params: GSParams = DEFAULTS, task: str = "conjunction",
                   prevalence: float = 0.5, n_trials: int = 2000, seed: int = 0,
                   set_sizes: Sequence[int] = SET_SIZES,
                   burn_in: float = 0.3) -> list:
    """One observer at a given target prevalence (phase 6).

    The adaptive quitting threshold is the only thing that can respond to
    prevalence, and it needs a long burn-in to settle, so the default here
    discards the first 30 percent of trials.
    """
    model = GSHybrid(params, seed=seed)
    rng = np.random.default_rng(seed + 500)
    rows = []
    cut = int(n_trials * burn_in)
    for k in range(n_trials):
        n = int(set_sizes[int(rng.integers(len(set_sizes)))])
        present = bool(rng.random() < prevalence)
        r = model.run_trial(make_display(task, n, present, rng))
        r.pop("fixations", None)
        r["prevalence"] = prevalence
        if k >= cut:
            rows.append(r)
    return rows


def run_priming(params: GSParams = DEFAULTS, n_trials: int = 2000, seed: int = 0,
                set_sizes: Sequence[int] = SET_SIZES, burn_in: float = 0.2) -> list:
    """Feature search whose target colour holds for runs of 1 to 4 trials.

    A trial is a *repeat* when its target colour matches the previous trial's.
    The priming traces of section 5.3 should make repeats faster.
    """
    model = GSHybrid(params, seed=seed)
    rng = np.random.default_rng(seed + 700)
    rows = []
    cut = int(n_trials * burn_in)
    cur, left, prev = "red", 0, None
    for k in range(n_trials):
        if left == 0:
            cur = "green" if cur == "red" else "red"
            left = int(rng.integers(1, 5))
        left -= 1
        n = int(set_sizes[int(rng.integers(len(set_sizes)))])
        present = bool(rng.random() < 0.5)
        d = make_display("feature", n, present, rng, target_color=cur)
        r = model.run_trial(d, template={"color": cur})
        r.pop("fixations", None)
        r["target_color"] = cur
        r["color_repeat"] = int(prev == cur)
        prev = cur
        if k >= cut:
            rows.append(r)
    return rows


def slopes(rows, task: str, set_sizes: Sequence[int] = SET_SIZES) -> dict:
    """Least-squares slope and intercept (ms) over correct-trial cell means."""
    out = {}
    for present in (True, False):
        xs, ys = [], []
        for n in set_sizes:
            sel = [r["rt"] for r in rows
                   if r["task"] == task and r["set_size"] == n
                   and r["target_present"] == present and r["correct"]]
            if sel:
                xs.append(n)
                ys.append(np.mean(sel) * 1000.0)
        if len(xs) >= 2:
            s, i = np.polyfit(np.array(xs, float), np.array(ys, float), 1)
        else:
            s = i = float("nan")
        out["tp" if present else "ta"] = (float(s), float(i))
    tp, ta = out["tp"][0], out["ta"][0]
    out["ratio"] = ta / tp if tp else float("nan")
    for present, key in ((True, "miss"), (False, "fa")):
        errs = {}
        for n in set_sizes:
            sel = [r for r in rows if r["task"] == task and r["set_size"] == n
                   and r["target_present"] == present]
            errs[n] = (sum(1 for r in sel if not r["correct"]) / len(sel)) if sel else float("nan")
        out[key] = errs
    fx = [r["n_fixations"] for r in rows if r["task"] == task]
    out["mean_fixations"] = float(np.mean(fx)) if fx else float("nan")
    return out


# --------------------------------------------------------------------------
# Phase 1 parameter sets
# --------------------------------------------------------------------------
# Found by ``python harness/fit.py --phase1`` (per task) and
# ``--shared`` (one set for all three), 120 trials per cell, seed 0, scoring
# squared slope error against the published Wolfe, Palmer and Horowitz (2010)
# slopes with a light intercept term.  Section 12 decision 6 asks whether the
# selection interval and diffuser capacity may differ per task; both branches
# are recorded so the cost of insisting on one set is visible.
#
# Slopes each set produces, ms/item, present/absent (target in brackets):
#
#     task          per-task set        shared set        target
#     feature        1.0 /   1.5         see SHARED_FIT    1 /  3
#     conjunction   19.0 /  49.8                          20 / 45
#     spatial       38.7 / 100.7                          43 / 95
#
# Every set leaves the intercepts 200 to 350 ms above the human values.  That
# residual is real and is reported in docs/RESULTS.md rather than absorbed:
# the response stage the handoff says not to tune into the module accounts for
# about 400 ms of it, and the module's own floor -- one selection interval, a
# 120 ms identification and usually one saccade -- accounts for the rest.

PHASE1: dict = {
    "feature": {"memory": 8, "noise": 0.05, "choice_beta": 2.0,
                "select_interval": 0.03, "diffuser_capacity": 2,
                "attn_fvf": 16.0, "max_fixation": 0.25},
    "conjunction": {"memory": 16, "w_e": 0.10, "noise": 0.3, "choice_beta": 2.0,
                    "select_interval": 0.03, "diffuser_capacity": 3,
                    "attn_fvf": 16.0, "max_fixation": 0.20},
    "spatial": {"memory": 12, "w_e": 0.05, "choice_beta": 16.0,
                "select_interval": 0.03, "diffuser_capacity": 8,
                "attn_fvf": 12.0, "max_fixation": 0.20},
}

# One set for all three tasks; see data/model/shared.json for its per-task
# slopes and docs/RESULTS.md for the misfit it costs.
SHARED_DELTA: dict = {
    "memory": 12, "w_e": 0.10, "noise": 0.2, "choice_beta": 16.0,
    "select_interval": 0.03, "diffuser_capacity": 8, "attn_fvf": 12.0,
    "max_fixation": 0.20,
}


def phase1_params(task: str) -> GSParams:
    """The per-task phase 1 set for ``task``."""
    return replace(DEFAULTS, **PHASE1[task])


def shared_params() -> GSParams:
    """The single set used across all three tasks."""
    return replace(DEFAULTS, **SHARED_DELTA)


SHARED: GSParams = replace(DEFAULTS, **SHARED_DELTA)


def report(params: GSParams = DEFAULTS, n_per_cell: int = 200, seed: int = 0,
           tasks: Sequence[str] = TASKS) -> dict:
    rows = run_cells(params, tasks=tasks, n_per_cell=n_per_cell, seed=seed)
    return {t: slopes(rows, t) for t in tasks}


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--n-per-cell", type=int, default=200)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    res = report(n_per_cell=args.n_per_cell, seed=args.seed)
    print(f"{'task':12s} {'TP ms/item':>11s} {'TA ms/item':>11s} {'ratio':>6s} "
          f"{'miss18':>7s} {'fa18':>6s} {'fix':>5s}")
    for t, s in res.items():
        print(f"{t:12s} {s['tp'][0]:11.1f} {s['ta'][0]:11.1f} {s['ratio']:6.2f} "
              f"{s['miss'][18]:7.3f} {s['fa'][18]:6.3f} {s['mean_fixations']:5.1f}")


def run_singleton(params: GSParams = DEFAULTS, n_trials: int = 3000, seed: int = 0,
                  set_sizes=(3, 4, 5, 6), burn_in: float = 0.2) -> list:
    """The additional-singleton paradigm (Adam et al. 2021, experiment 1c).

    The target is an orientation singleton; on half the trials an irrelevant
    colour singleton competes.  The distractor colour varies from trial to
    trial, matching the variable-colour condition, so nothing can be learned
    and suppressed.  The capture cost is the RT difference between
    distractor-present and distractor-absent trials.
    """
    from harness.tasks import SINGLETON_TEMPLATE, make_singleton_display
    model = GSHybrid(params, seed=seed)
    rng = np.random.default_rng(seed + 900)
    palette = ("red", "green")
    rows = []
    cut = int(n_trials * burn_in)
    for k in range(n_trials):
        n = int(set_sizes[int(rng.integers(len(set_sizes)))])
        present = bool(rng.random() < 0.5)
        col = palette[int(rng.integers(len(palette)))] if present else None
        d = make_singleton_display(n, present, rng, distractor_color=col)
        r = model.run_trial(d, template=SINGLETON_TEMPLATE)
        r.pop("fixations", None)
        r["distractor_present"] = present
        if k >= cut:
            rows.append(r)
    return rows
