"""Python mirror of the gs6-vision module: Wolfe's Guided Search 6 engine on
the gs-vision spatial layer.

This file is to ``gs6-vision/`` what ``gs_hybrid.py`` is to ``gs-vision/``:
the same mechanisms in Python, run on the same displays, so that parameters
can be fitted quickly and the Lisp module can be checked against it cell by
cell.  It reuses the frozen mirror's acuity, priority-map, EMMA and response
code by subclassing ``GSHybrid`` and replaces the parts where gs-vision used
Competitive Guided Search (Moran et al. 2013) instead of Wolfe (2021):

* **Identification is the asynchronous diffuser of the posted GS6 MATLAB.**
  Every ``diff_step`` (10 ms) each in-flight item moves by
  ``sign * (N(0,1) * diff_inc * diff_noise + drift)`` between the bounds
  ``dist_thresh`` (-1, reject) and ``targ_thresh`` (+1, accept).  Outcomes
  are emergent: a distractor that reaches +1 is a false alarm and a target
  that reaches -1 is a miss.  ``similarity_drift`` slows a distractor's drift
  in proportion to its similarity to the full template, which the GS6 paper
  describes and the posted simulation fixes (default 0 = posted behaviour).
* **An item starts at GS6's start point**: ``prevalence / 2 - 0.25`` plus an
  adaptive offset that rises by ``start_inc`` after a hit and falls by
  ``start_dec`` after a false alarm.
* **Quitting is GS6's quit-signal diffuser.**  After the first rejection the
  signal grows by ``N(0,1) * quit_inc * quit_noise + quit_inc`` every step and
  the search quits when it exceeds ``qt_scale * n_eff / quit_ss_ref``.  The
  rejection counter, the draining rule and the competitive quit unit of
  gs-vision are gone (``stop="cgs"`` still adds the competitive unit for
  ablations).  Feedback follows the MATLAB exactly: a true negative lowers the
  scale by ``qt_step * prevalence``; a miss raises it by
  ``qt_step / (error_goal * prevalence * 2) * (1 - prevalence)``.
* **Memory is the diffuser** (``memory=0``): a rejected item is selectable
  again at once, as in the posted simulation.  The IOR ring is still there
  for the few-item memory GS4/GS6 allow in the text.
* **GS2 orientation channels.**  With ``orient_dual`` an item drives a
  steep/shallow channel and a left/right channel at the same time (two
  dimensions, ``orient`` and ``tilt``); with ``best_channel`` top-down
  guidance uses, per dimension, the template channel that best separates the
  template from the display (GS2's rule, GS6's relational guidance).
* A selected item whose template features are not yet available asks for a
  saccade at selection time rather than after a timer, and is rejected only
  if the features are still unavailable at the fovea.

Eye movements, acuity, the attentional and exploratory fields and the
response stage are unchanged from gs_hybrid.py: GS6 does not specify them.

One deliberate departure from the MATLAB: when an item crosses the target
bound and the quit signal crosses its threshold on the same 10 ms step, the
hit wins.  In the MATLAB the quit test overwrites the yes response; Wolfe's
own comments treat that as an artefact and ``gs6_sim.py`` reproduces it only
so that it matches the posted code.
"""

from __future__ import annotations

import heapq
import math
import pathlib
import sys
from collections import deque
from dataclasses import dataclass, replace
from typing import Sequence

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from harness.tasks import SCREEN_CENTER_PX, SET_SIZES, TASKS, TEMPLATES, Display, px2deg, deg2px  # noqa: E402
from reference import gs_hybrid as base  # noqa: E402
from reference.gs_hybrid import (GSHybrid, GUIDING_DEFAULT, LUM_NAMES, SIZE_NAMES, _HIT, _MISS,  # noqa: E402
                                 _FA, _TN, _Item, _tercile_channel, channel_distance,
                                 channel_overlap, color_channels, orient_channels)


# --------------------------------------------------------------------------
# Parameters (names match the :gs-* parameters of gs6-vision)
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class GS6Params:
    guiding_features: tuple = GUIDING_DEFAULT
    select_interval: float = 0.050      # GS6: a new item every 50 ms
    diffuser_capacity: int = 5          # GS6: five items in the carwash
    choice_beta: float = 4.0
    saccade_margin: float = 0.25
    saccade_proximity: float = 0.10
    revised_saccades: bool = True
    quit_noise_free: bool = True        # competitive unit only (stop cgs/both)
    recognition_extra: bool = False
    onset_latency: float = 0.0
    explore_proximity: bool = True      # distance-penalised destination when the field is empty
    saccade_trigger: float = 0.0
    quit_delta: float = 0.02            # competitive unit only (stop cgs/both)
    memory: int = 0                     # GS6: memory is the diffuser
    attn_fvf: float = 8.0
    explore_fvf: float = 12.0
    max_fixation: float = 0.4
    iconic_span: float = 4.0
    acuity_theta: tuple = (("color", 0.10), ("orient", 0.20), ("shape", 0.40),
                           ("size", 0.20), ("lum", 0.10))
    acuity_sigma: float = 0.5
    w_bu: float = 0.5
    w_td: float = 1.0
    w_h: float = 0.3
    w_v: float = 0.0
    w_s: float = 1.0
    w_e: float = 0.02
    noise: float = 0.2
    priming_tau: float = 10.0
    # --- the GS6 diffuser (GS6publicAsPostedJan2021.m) --------------------
    diff_step: float = 0.010            # RTstep
    diff_inc: float = 0.05              # adifInc: 20 noiseless steps to a bound
    diff_noise: float = 2.5             # adifNoise = adifInc * 2.5
    targ_thresh: float = 1.0            # TargThresh
    dist_thresh: float = -1.0           # DistThresh
    similarity_drift: float = 0.0       # distractor drift * (1 - s * similarity); 0 = posted
    start_prevalence: bool = True       # start point prev/2 - 0.25 (+ adaptive offset)
    start_inc: float = 0.0008           # StartInc after a hit
    start_dec: float = 0.05             # StartDec after a false alarm
    # --- the GS6 quit signal -----------------------------------------------
    quit_inc: float = 0.018             # quitInc per step
    quit_noise: float = 2.5             # quitNoiseSD = quitInc * 2.5
    qt_init: float = 1.5                # quitThresh(1)
    quit_ss_ref: float = 10.0           # quitThresh * SS / (max(SS) * 0.5) with max(SS) = 20
    qt_step: float = 0.005              # quitDownStep
    error_goal: float = 0.08            # missDesired
    feedback_window: int = 50
    # --- GS2 priority-map rules ---------------------------------------------
    orient_dual: bool = True
    best_channel: bool = True
    emma: bool = True
    saccade_feat_time: float = 0.050
    saccade_init_time: float = 0.050
    saccade_base_time: float = 0.020
    eye_saccade_rate: float = 0.002
    visual_encoding_factor: float = 0.006
    visual_encoding_exponent: float = 0.4
    vis_obj_freq: float = 0.1
    visual_attention_latency: float = 0.085
    # response stage and protocol: harness-only, as in gs_hybrid.py
    motor_error: float = 0.0
    t_nondecision: float = 0.160
    response_first_extra: float = 0.150
    response_switch_extra: float = 0.100
    trial_gap: float = 2.0
    max_trial_s: float = 20.0

    def __post_init__(self):
        for name in ("select_interval", "max_fixation", "iconic_span", "visual_attention_latency",
                     "onset_latency", "diff_step"):
            object.__setattr__(self, name, round(getattr(self, name) * 1000) / 1000)

    @property
    def theta_map(self) -> dict:
        return dict(self.acuity_theta)

    @property
    def diff_sd(self) -> float:
        return self.diff_inc * self.diff_noise

    @property
    def quit_sd(self) -> float:
        return self.quit_inc * self.quit_noise


DEFAULTS = GS6Params()


# --------------------------------------------------------------------------
# GS2 orientation channels
# --------------------------------------------------------------------------

STEEP_EDGE = 45.0      # steep/shallow boundary, degrees from vertical
STEEP_RAMP = 10.0      # linear ramp either side of it
TILT_ON = 5.0          # no left/right response within this of vertical or horizontal
TILT_FULL = 22.5       # full left/right response from here


def _clamp01(x):
    return 0.0 if x <= 0.0 else 1.0 if x >= 1.0 else x


def orient_channels_dual(theta):
    """GS2 orientation: (steep/shallow dict, left/right dict).

    An item drives a steep-or-shallow channel and, if tilted, a left-or-right
    channel at the same time.  Steep is 1 up to 35 degrees from vertical and 0
    from 55; the tilt response is 0 within 5 degrees of vertical or horizontal
    and 1 between 22.5 and 67.5.  Vertical and horizontal items have an empty
    tilt dict, so they neither match nor mismatch a tilt template channel.
    """
    if theta is None:
        return {}, {}
    t = ((float(theta) + 90.0) % 180.0) - 90.0
    a = abs(t)
    steep = _clamp01((STEEP_EDGE + STEEP_RAMP - a) / (2 * STEEP_RAMP))
    orient = {}
    if steep > 0:
        orient["steep"] = steep
    if steep < 1:
        orient["shallow"] = 1.0 - steep
    strength = _clamp01((a - TILT_ON) / (TILT_FULL - TILT_ON)) * \
        _clamp01((90.0 - TILT_ON - a) / (TILT_FULL - TILT_ON))
    tilt = {("right" if t > 0 else "left"): strength} if strength > 0 else {}
    return orient, tilt


# The raw feature whose availability a channel dimension depends on.
AVAIL_OF = {"tilt": "orient"}


class GS6Hybrid(GSHybrid):
    """One simulated GS6 observer.  Adaptive state persists across trials."""

    def __init__(self, params: GS6Params = DEFAULTS, seed: int = 0):
        super().__init__(params, seed=seed)
        self.qt_scale = params.qt_init
        self.start_offset = 0.0
        self._nbuf = np.empty(0)
        self._ni = 0

    # -- normals ----------------------------------------------------------
    def _normal(self) -> float:
        if self._ni >= len(self._nbuf):
            self._nbuf = self.rng.standard_normal(4096)
            self._ni = 0
        v = float(self._nbuf[self._ni])
        self._ni += 1
        return v

    # -- adaptive state ------------------------------------------------------
    @property
    def start_point(self) -> float:
        p = self.p
        s = (self.prevalence / 2.0 - 0.25 if p.start_prevalence else 0.0) + self.start_offset
        return min(p.targ_thresh - 1e-3, max(p.dist_thresh + 1e-3, s))

    def feedback_outcome(self, outcome: str, n_eff: float):
        """GS6 feedback: threshold scale on absent responses, start point on present ones."""
        p = self.p
        prev = self.prevalence
        if outcome == _TN:
            self.qt_scale = max(0.0, self.qt_scale - p.qt_step * prev)
        elif outcome == _MISS:
            up = p.qt_step / max(1e-6, p.error_goal * prev * 2.0)
            self.qt_scale += up * (1.0 - prev)
        elif outcome == _HIT:
            self.start_offset += p.start_inc
        elif outcome == _FA:
            self.start_offset -= p.start_dec
        self.feedback.append(outcome)

    # -- channels -------------------------------------------------------------
    def _guiding(self) -> list:
        g = list(self.p.guiding_features)
        if self.p.orient_dual and "orient" in g and "tilt" not in g:
            g.append("tilt")
        return g

    def _prepare(self, display: Display) -> list:
        items = super()._prepare(display)
        if self.p.orient_dual:
            for it in items:
                it.channels["orient"], it.channels["tilt"] = orient_channels_dual(it.raw["orient"])
        return items

    def _template_channels(self, template: dict, items: list) -> dict:
        """Template values to channel dicts keyed by dimension.

        A numeric orientation drives ``orient`` and, when tilted, ``tilt``; the
        channel names steep/shallow name the ``orient`` dimension and
        left/right the ``tilt`` dimension when ``orient_dual`` is on.
        """
        out = super()._template_channels(template, items)
        if self.p.orient_dual and "orient" in template:
            v = template["orient"]
            out.pop("orient")
            if isinstance(v, str):
                if v in ("left", "right"):
                    out["tilt"] = {v: 1.0}
                else:
                    out["orient"] = {v: 1.0}
            else:
                orient, tilt = orient_channels_dual(v)
                out["orient"] = orient
                if tilt:
                    out["tilt"] = tilt
        return out

    @staticmethod
    def _dim_available(avail: set, k: str) -> bool:
        return AVAIL_OF.get(k, k) in avail

    # -- priority map with GS2's best-channel rule ----------------------------
    def _priority(self, items, iconic, eye, tmpl_ch, t):
        p = self.p
        guiding = self._guiding()
        avail = {it.idx: self._available(iconic, it.idx, t) for it in items}

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
                        if self._dim_available(avail[a.idx], k) and self._dim_available(avail[j], k):
                            s += channel_distance(a.channels.get(k, {}), other.channels.get(k, {}))
                    tot += s / max(1.0, d)
                bu[a.idx] = tot / max(1, len(nb))

        guide_keys = [k for k in tmpl_ch if k in guiding]
        td = {}
        if not guide_keys:
            td = {i.idx: 1.0 for i in items}
        else:
            best = {}
            if p.best_channel:
                for k in guide_keys:
                    known = [it for it in items if self._dim_available(avail[it.idx], k)]
                    scores = []
                    for cname, tact in tmpl_ch[k].items():
                        mean_resp = (sum(it.channels.get(k, {}).get(cname, 0.0) for it in known)
                                     / len(known)) if known else 0.0
                        scores.append((tact - mean_resp, cname, tact))
                    # first channel on ties, as in the Lisp
                    top = max(range(len(scores)), key=lambda i: (scores[i][0], -i))
                    best[k] = (scores[top][1], scores[top][2])
            for it in items:
                s = 0.0
                for k in guide_keys:
                    if not self._dim_available(avail[it.idx], k):
                        s += 0.5
                    elif p.best_channel:
                        cname, tact = best[k]
                        s += min(1.0, it.channels.get(k, {}).get(cname, 0.0) / tact) if tact > 0 else 0.0
                    else:
                        s += channel_overlap(it.channels.get(k, {}), tmpl_ch[k])
                td[it.idx] = s / len(guide_keys)

        hist = {}
        for it in items:
            s = 0.0
            for k in guiding:
                if self._dim_available(avail[it.idx], k):
                    for cname, act in it.channels.get(k, {}).items():
                        s += act * self._trace((k, cname))
            hist[it.idx] = s

        def _norm(d):
            m = max(d.values()) if d else 0.0
            return {k: (v / m if m > 0 else 0.0) for k, v in d.items()}

        bu, td_n, hist = _norm(bu), _norm(td), _norm(hist)
        out = {}
        self.guidance = {}
        for it in items:
            eps = p.noise * math.log(max(1e-12, u := self.rng.random()) / max(1e-12, 1.0 - u))
            self.guidance[it.idx] = (p.w_bu * bu[it.idx] + p.w_td * td_n[it.idx]
                                     + p.w_h * hist[it.idx] + p.w_v * 0.0 + p.w_s * it.prior)
            out[it.idx] = self.guidance[it.idx] - p.w_e * self._ecc(it, eye) + eps
        return out, td

    # -- one trial ---------------------------------------------------------------
    def run_trial(self, display: Display, template: dict | None = None,
                  stop: str = "adaptive") -> dict:
        p = self.p
        rng = self.rng
        trial_onset = self.clock
        self.clock += .050
        template = template if template is not None else TEMPLATES[display.task]
        items = self._prepare(display)
        tmpl_ch = self._template_channels(template, items)
        similarity = {it.idx: sum(channel_overlap(it.channels.get(k, {}), tmpl_ch[k]) for k in tmpl_ch)
                      / len(tmpl_ch) for it in items}
        matches = {it.idx: all(channel_overlap(it.channels.get(k, {}), tmpl_ch[k]) > 0.5 for k in tmpl_ch)
                   for it in items}

        eye = [float(SCREEN_CENTER_PX[0]), float(SCREEN_CENTER_PX[1])]
        iconic = {i.idx: {} for i in items}
        diffuser: dict = {}                 # idx -> {"evidence", "active", "pending", "foveated"}
        order: list = []                    # diffuser insertion order for the tick
        ior: deque = deque(maxlen=p.memory) if p.memory > 0 else deque(maxlen=0)
        quit_weight = 0.0
        quit_sig = 0.0
        quit_started = False
        rejections = 0
        t = 0.0
        fixations = [];  fix_start = 0.0
        saccade_flight = False
        eye_moving = False
        last_landed_on = None
        self.last_saccade = None
        events = [(0.0, "request", None)]
        start_point = self.start_point

        self._draw_availability(items, eye, iconic, t)
        prio, td = self._priority(items, iconic, eye, tmpl_ch, t)
        n_eff = max(1.0, sum(1 for v in td.values() if v >= 0.5))
        qt = self.qt_scale * n_eff / p.quit_ss_ref

        queue: list = []
        seq = 0

        def push(when, kind, payload=None):
            # ticks run after every other event scheduled for the same time
            nonlocal seq
            seq += 1
            heapq.heappush(queue, (round(when * 1000) / 1000, 1 if kind == "tick" else 0, seq, kind, payload))

        def eligible(fvf=None):
            out = []
            for it in items:
                if it.idx in ior or it.idx in diffuser:
                    continue
                if fvf is not None and self._ecc(it, eye) > fvf:
                    continue
                out.append(it.idx)
            return out

        def centred_weights(idxs, quitting=False):
            if not idxs:
                return []
            signal = self.guidance if quitting and p.quit_noise_free else prio
            beta = min(4.0, p.choice_beta) if quitting and p.quit_noise_free else p.choice_beta
            pbar = sum(signal[i] for i in idxs) / len(idxs)
            return [math.exp(min(50.0, beta * (signal[i] - pbar))) for i in idxs]

        outcome = {"result": None, "reason": None, "item": None}

        def request_saccade(to=None):
            nonlocal saccade_flight
            if saccade_flight:
                return
            pend = [i for i in order if i in diffuser and diffuser[i]["pending"]]
            if pend:
                tgt = pend[0]
            elif to is not None:
                tgt = to
            else:
                cand = eligible(p.explore_fvf) or eligible(None)
                if not cand:
                    if not diffuser:
                        outcome["result"], outcome["reason"] = "quit", "no-candidate"
                    return
                tgt = max(cand, key=lambda i: self.guidance[i] - p.saccade_proximity *
                          self._ecc(items[i], eye)) if p.revised_saccades else max(cand, key=lambda i: prio[i])
            it = items[tgt]
            dx, dy = it.x - eye[0], it.y - eye[1]
            amp = px2deg(math.hypot(dx, dy))
            self._saccade_time(amp, math.atan2(-dy, dx))
            push(t + self.saccade_prep, "execute", (tgt, self.saccade_execution))
            saccade_flight = True

        def remove(i):
            diffuser.pop(i, None)
            if i in order:
                order.remove(i)

        def do_reject(i):
            nonlocal quit_weight, rejections, quit_started
            remove(i)
            if p.memory > 0:
                ior.append(i)
            rejections += 1
            quit_started = True
            events.append((t, "decision", i))
            if stop in ("cgs", "both"):
                quit_weight += p.quit_delta
                w = centred_weights([it.idx for it in items if it.idx not in ior], quitting=True)
                denom = sum(w) + quit_weight
                if denom > 0 and rng.random() < quit_weight / denom:
                    outcome["result"], outcome["reason"] = "quit", "cgs"

        def check_item(i):
            """Activate a diffuser item whose template features are available,
            or ask for a saccade, or reject it if the fovea could not help."""
            d = diffuser.get(i)
            if d is None or d["active"]:
                return
            avail = self._available(iconic, i, t)
            missing = [k for k in template if k not in avail]
            if not missing:
                d["active"] = True
            elif d["foveated"] or last_landed_on == i:
                do_reject(i)
            else:
                d["pending"] = True
                request_saccade()

        push(p.onset_latency + p.select_interval, "select")
        push(p.diff_step, "tick")
        push(p.max_fixation, "fixtimeout")

        while outcome["result"] is None and queue:
            t, _, _, kind, payload = heapq.heappop(queue)
            if t > p.max_trial_s:
                t = p.max_trial_s
                outcome["result"], outcome["reason"] = "quit", "timeout"
                break

            if kind == "select":
                if not eye_moving and len(diffuser) < p.diffuser_capacity:
                    everywhere = eligible(None)
                    signal = self.guidance if p.revised_saccades else prio
                    winner = max(everywhere, key=lambda i: signal[i]) if everywhere else None
                    near = eligible(p.attn_fvf)
                    if (p.saccade_trigger > 0 and near and not saccade_flight and
                            min(self._ecc(items[i], eye) for i in near) > p.saccade_trigger):
                        request_saccade()
                    if winner is not None and winner not in near and (
                            not p.revised_saccades or not near or
                            signal[winner] > max(signal[i] for i in near) + p.saccade_margin):
                        request_saccade(to=None if (p.explore_proximity and not near) else winner)
                        if p.revised_saccades:
                            near = []
                    if near and (p.revised_saccades or winner in near):
                        w = np.array(centred_weights(near), float)
                        pick = near[int(rng.choice(len(near), p=w / w.sum()))]
                        diffuser[pick] = {"evidence": start_point, "active": False,
                                          "pending": False, "foveated": False}
                        order.append(pick)
                        events.append((t, "select", pick))
                        check_item(pick)
                    elif not near:
                        request_saccade()
                push(t + p.select_interval, "select")

            elif kind == "tick":
                hit = None
                for i in list(order):
                    d = diffuser.get(i)
                    if d is None or not d["active"]:
                        continue
                    if matches[i]:
                        drift = p.diff_inc
                        sign = 1.0
                    else:
                        drift = p.diff_inc * (1.0 - p.similarity_drift * similarity[i])
                        sign = -1.0
                    d["evidence"] += sign * (self._normal() * p.diff_sd + drift)
                for i in list(order):
                    d = diffuser.get(i)
                    if d is not None and d["active"] and d["evidence"] < p.dist_thresh:
                        do_reject(i)
                        if outcome["result"] is not None:
                            break
                if outcome["result"] is not None:
                    break
                if quit_started:
                    quit_sig += self._normal() * p.quit_sd + p.quit_inc
                for i in order:
                    d = diffuser[i]
                    if d["active"] and d["evidence"] > p.targ_thresh and (
                            hit is None or d["evidence"] > diffuser[hit]["evidence"]):
                        hit = i
                if hit is not None:
                    outcome["result"], outcome["item"], outcome["reason"] = "found", hit, "hit"
                    events.append((t, "decision", hit))
                    events.append((t, "identified", hit))
                    if p.recognition_extra:
                        ecc = self._ecc(items[hit], eye)
                        enc = self._raw_encoding(ecc)
                        sacc = p.saccade_init_time + p.saccade_base_time + p.eye_saccade_rate * ecc
                        t += round((enc if enc <= sacc else sacc +
                                   max(0, 1 - sacc / enc) * self._raw_encoding(.5)) * 1000) / 1000
                    break
                if stop in ("adaptive", "both") and quit_started and quit_sig > qt:
                    outcome["result"], outcome["reason"] = "quit", "threshold"
                    break
                push(t + p.diff_step, "tick")

            elif kind == "check":
                check_item(payload)

            elif kind == "execute":
                if fix_start is not None:
                    fixations.append((fix_start, eye[0], eye[1], t - fix_start))
                    fix_start = None
                eye_moving = True
                events.append((t, "saccade-execute", payload[0]))
                push(t + payload[1], "land", payload[0])

            elif kind == "land":
                saccade_flight = False
                eye_moving = False
                tgt = items[payload]
                dist_px = math.hypot(tgt.x - eye[0], tgt.y - eye[1])
                sd = 0.1 * dist_px
                scale = math.sqrt(3) * sd / math.pi
                eye = [tgt.x + rng.logistic(0.0, scale), tgt.y + rng.logistic(0.0, scale)]
                fix_start = t
                events.append((t, "landing", payload))
                last_landed_on = payload
                self.clock = trial_onset + .050 + t
                self._draw_availability(items, eye, iconic, t)
                prio, _ = self._priority(items, iconic, eye, tmpl_ch, t)
                push(t + p.max_fixation, "fixtimeout")
                for i in order:
                    d = diffuser[i]
                    if d["pending"]:
                        d["pending"] = False
                        if i == payload:
                            d["foveated"] = True
                        push(t + 0.050, "check", i)

            elif kind == "fixtimeout":
                if fix_start is not None and t - fix_start >= p.max_fixation - 1e-9:
                    request_saccade()
                    push(t + p.max_fixation, "fixtimeout")

        if outcome["result"] is None:
            outcome["result"], outcome["reason"] = "quit", "exhausted"
        if fix_start is not None:
            fixations.append((fix_start, eye[0], eye[1], max(0, t - fix_start)))
        events.append((t, "buffer" if outcome["result"] == "found" else "failure", outcome["item"]))

        found = outcome["result"] == "found"
        say_present = found
        if rng.random() < p.motor_error:
            say_present = not say_present
        response_extra = (p.response_first_extra if self.last_response is None else
                          p.response_switch_extra if say_present != self.last_response else 0)
        rt = t + p.t_nondecision + response_extra
        timed_out = outcome["reason"] == "timeout"
        correct = say_present == display.target_present
        if display.target_present:
            label = _HIT if say_present else _MISS
        else:
            label = _FA if say_present else _TN

        self.clock = trial_onset + rt + .050
        if label == _HIT and outcome["item"] is not None:
            for k in self._guiding():
                for cname in items[outcome["item"]].channels.get(k, {}):
                    self._bump((k, cname))
        if not timed_out:
            self.feedback_outcome(label, n_eff)
            self.last_response = say_present
        self.clock = trial_onset + (p.max_trial_s if timed_out else rt) + p.trial_gap

        return {
            "task": display.task, "set_size": display.set_size,
            "target_present": display.target_present,
            "response": say_present if not timed_out else None,
            "correct": correct and not timed_out, "label": label if not timed_out else "timeout",
            "rt": rt if not timed_out else float("nan"), "search_time": t,
            "timed_out": timed_out, "events": events, "qt_scale": self.qt_scale,
            "start_point": start_point, "quit_sig": quit_sig,
            "n_fixations": len(fixations), "n_rejected": rejections,
            "quit_reason": outcome["reason"], "n_eff": n_eff,
            "qt": qt, "fixations": fixations,
        }


base.MODEL_CLASSES[GS6Params] = GS6Hybrid


def run_cells(params: GS6Params = DEFAULTS, **kw) -> list:
    """``gs_hybrid.run_cells`` for a GS6 observer (dispatch is by parameter type)."""
    return base.run_cells(params, **kw)


def report(params: GS6Params = DEFAULTS, n_per_cell: int = 200, seed: int = 0,
           tasks: Sequence[str] = TASKS) -> dict:
    rows = base.run_cells(params, tasks=tasks, n_per_cell=n_per_cell, seed=seed)
    return {t: base.slopes(rows, t) for t in tasks}


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
