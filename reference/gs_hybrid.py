"""Python mirror of the repaired gs-vision module.

Shape remains identification-only. Covert choice uses noisy priorities;
saccade triggering uses noise-free guidance and a margin, with a separate
destination distance penalty. Preparation permits useful covert work, while
execution pauses new selection. Fixations record occupied stationary intervals
from request to visual result, including initial/final closures.

Wald completes recognition once required features are available. Missing
features still require foveation. Peripheral recognition does not move gaze or
add another encoding stage. The initial selection interval remains a cost.

Competitive quit weights include unresolved diffuser items, omit noise and
eccentricity, and cap their beta at four. Adaptive stopping drains outstanding
identifications. Threshold scale, priming, and feedback persist within each
observer; benchmark gaze/preparation reset at the untimed fixation cross.

GSParams separates vision from the measured keyboard response approximation
(160/260/310 ms on repeat/switch/first responses) and trial protocol. These
response settings are fixed from ACT-R events, never fitted to human RT.
Milliseconds are normalized at construction. run_cells uses the same task
blocks, synthetic practice, feedback timing, and display plan as the runner.

The independent gs6_sim.py remains the original posted-MATLAB replication.
Scientific misfits and historical ablations are documented in docs/RESULTS.md.
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
                           Display, make_display, px2deg, deg2px)

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
    saccade_margin: float = 0.25    # noise-free guidance advantage
    saccade_proximity: float = 0.10 # guidance penalty per degree, eye choice only
    revised_saccades: bool = True
    quit_noise_free: bool = True
    recognition_extra: bool = False # historical recognition-delay ablation
    id_drift: float = 0.25          # Wald mu
    id_threshold: float = 0.03      # Wald theta
    id_sigma: float = 0.1           # Wald noise; CV^2 = sigma^2 / (theta mu)
    id_error: float = 0.0           # P(an identification decision flips): misses and false alarms
    onset_latency: float = 0.0      # s from the request to the first covert selection
    adaptive_quit_delta: bool = False  # scale the competitive increment by the adaptive threshold
    explore_proximity: bool = False    # distance-penalised destination when the attentional field is empty
    saccade_trigger: float = 0.0       # deg; > 0 moves the eye once the nearest selectable item is farther
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
    motor_error: float = 0.0
    t_nondecision: float = 0.160   # measured repeated j/f key response stage
    response_first_extra: float = 0.150
    response_switch_extra: float = 0.100
    trial_gap: float = 2.0        # feedback 500 + ITI 1000 + warning interval 500 ms
    max_trial_s: float = 20.0

    def __post_init__(self):
        # These ACT-R parameter slots store integer milliseconds. Normalize
        # before simulation, serialization, and readback comparison.
        for name in ("select_interval", "max_fixation", "iconic_span", "visual_attention_latency",
                     "onset_latency"):
            object.__setattr__(self, name, round(getattr(self, name) * 1000) / 1000)

    @property
    def theta_map(self) -> dict:
        return dict(self.acuity_theta)

    @property
    def id_mean(self) -> float:
        return self.id_threshold / self.id_drift

    @property
    def id_shape(self) -> float:
        return self.id_threshold ** 2 / self.id_sigma ** 2

    @property
    def id_cv(self) -> float:
        """Coefficient of variation of the identification time."""
        return self.id_sigma / math.sqrt(self.id_threshold * self.id_drift)


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
        self.last_response = None

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
                             size_deg=0.5 * (px2deg(deg2px(it.w_deg)) + px2deg(deg2px(it.h_deg))),
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
                    iconic[it.idx][f] = t
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
        self.guidance = {}
        for it in items:
            eps = p.noise * math.log(max(1e-12, u := self.rng.random()) / max(1e-12, 1.0 - u))
            self.guidance[it.idx] = (p.w_bu * bu[it.idx] + p.w_td * td_n[it.idx]
                           + p.w_h * hist[it.idx] + p.w_v * 0.0
                           + p.w_s * it.prior)
            out[it.idx] = self.guidance[it.idx] - p.w_e * self._ecc(it, eye) + eps
        return out, td

    # -- EMMA arithmetic (section 5.5) ------------------------------------
    def _saccade_time(self, amplitude_deg: float, direction: float) -> float:
        p = self.p
        if self.last_saccade is None:
            nfeat = 3                                   # style change
        else:
            r0, th0 = self.last_saccade
            nfeat = 0
            if abs(amplitude_deg - r0) >= 2.0:          # ACT-R strict boundary
                nfeat += 1
            dth = abs((direction - th0 + math.pi) % (2 * math.pi) - math.pi)
            if dth >= math.pi / 4:                      # ACT-R directions within 45 deg
                nfeat += 1
        prep = p.saccade_feat_time * nfeat
        exe = p.saccade_init_time + p.saccade_base_time + p.eye_saccade_rate * amplitude_deg
        self.last_saccade = (amplitude_deg, direction)
        self.saccade_prep = round(prep * 1000) / 1000
        self.saccade_execution = round(exe * 1000) / 1000
        return self.saccade_prep + self.saccade_execution

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
        trial_onset = self.clock
        self.clock += .050                 # search production before request
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
        eye_moving = False
        last_landed_on = None
        self.last_saccade = None
        events = [(0.0, "request", None)]

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
                tgt = max(cand, key=lambda i: self.guidance[i] - p.saccade_proximity *
                          self._ecc(items[i], eye)) if p.revised_saccades else max(cand, key=lambda i: prio[i])
            it = items[tgt]
            dx, dy = it.x - eye[0], it.y - eye[1]
            amp = px2deg(math.hypot(dx, dy))
            self._saccade_time(amp, math.atan2(-dy, dx))
            push(t + self.saccade_prep, "execute", (tgt, self.saccade_execution))
            saccade_flight = True

        def do_reject(i):
            nonlocal quit_weight, rejections
            diffuser.pop(i, None)
            ior.append(i)
            # With adaptive_quit_delta the competitive increment is divided by
            # the persistent adaptive scale, so feedback that raises the
            # threshold after a miss also makes competitive quitting rarer.
            # Without it the two quit rules are independent and the controller
            # cannot reach its error goal once competitive quits dominate.
            quit_weight += (p.quit_delta / max(0.05, self.qt_scale)
                            if p.adaptive_quit_delta else p.quit_delta)
            rejections += 1
            if stop in ("cgs", "both"):
                # Competitive Guided Search zeroes an item's weight when it is
                # *rejected*, not while it is being identified, so items in the
                # diffuser stay in the denominator.  See deviation 2.
                w = centred_weights([it.idx for it in items if it.idx not in ior], quitting=True)
                denom = sum(w) + quit_weight
                if denom > 0 and rng.random() < quit_weight / denom:
                    outcome["result"], outcome["reason"] = "quit", "cgs"
                    return
            if stop in ("adaptive", "both") and not diffuser and rejections >= qt:
                outcome["result"], outcome["reason"] = "quit", "threshold"

        push(p.onset_latency + p.select_interval, "select")
        push(p.max_fixation, "fixtimeout")

        while outcome["result"] is None and queue:
            t, _, kind, payload = heapq.heappop(queue)
            if t > p.max_trial_s:
                t = p.max_trial_s
                outcome["result"], outcome["reason"] = "quit", "timeout"
                break

            if kind == "select":
                draining = stop in ("adaptive", "both") and rejections >= qt and diffuser
                if not eye_moving and not draining and len(diffuser) < p.diffuser_capacity:
                    everywhere = eligible(None)
                    signal = self.guidance if p.revised_saccades else prio
                    winner = max(everywhere, key=lambda i: signal[i]) if everywhere else None
                    near = eligible(p.attn_fvf)
                    if (p.saccade_trigger > 0 and near and not saccade_flight and
                            min(self._ecc(items[i], eye) for i in near) > p.saccade_trigger):
                        # Everything close has been dealt with: start moving the
                        # eye (distance-penalised destination) while covert
                        # selection continues during the preparation.
                        request_saccade()
                    if winner is not None and winner not in near and (
                            not p.revised_saccades or not near or
                            signal[winner] > max(signal[i] for i in near) + p.saccade_margin):
                        # Peripheral guidance (deviation 4 in the docstring):
                        # the priority winner cannot be selected covertly, so
                        # look at it instead of covertly grabbing a loser.
                        # With explore_proximity and nothing selectable inside
                        # the attentional field, the destination is chosen by
                        # guidance minus distance (request_saccade's own rule)
                        # rather than by guidance with icon-order tie-breaking.
                        request_saccade(to=None if (p.explore_proximity and not near) else winner)
                        if p.revised_saccades:
                            near = []
                    if near and (p.revised_saccades or winner in near):
                        w = np.array(centred_weights(near), float)
                        pick = near[int(rng.choice(len(near), p=w / w.sum()))]
                        diffuser[pick] = {"pending": False, "foveated": False}
                        dt = round(float(rng.wald(p.id_mean, p.id_shape)) * 1000) / 1000
                        events.append((t, "select", pick))
                        push(t + dt, "decide", pick)
                    elif not near:
                        request_saccade()
                push(t + p.select_interval, "select")

            elif kind == "decide":
                i = payload
                if i not in diffuser:
                    continue
                events.append((t, "decision", i))
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
                    if p.id_error > 0 and rng.random() < p.id_error:
                        ok = not ok            # second decision boundary: miss or false alarm
                    if ok:
                        outcome["result"], outcome["item"] = "found", i
                        outcome["reason"] = "hit"
                        events.append((t, "identified", i))
                        if p.recognition_extra:
                            # Historical Lisp delay; no unmodeled gaze relocation.
                            ecc = self._ecc(items[i], eye)
                            enc = self._raw_encoding(ecc)
                            sacc = p.saccade_init_time + p.saccade_base_time + p.eye_saccade_rate * ecc
                            t += round((enc if enc <= sacc else sacc +
                                       max(0, 1 - sacc / enc) * self._raw_encoding(.5)) * 1000) / 1000
                    else:
                        do_reject(i)

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
                for i, d in diffuser.items():
                    if d["pending"]:
                        d["pending"] = False
                        if i == payload:
                            d["foveated"] = True
                        push(t + 0.050, "decide", i)

            elif kind == "fixtimeout":
                if fix_start is not None and t - fix_start >= p.max_fixation - 1e-9:
                    request_saccade()
                    push(t + p.max_fixation, "fixtimeout")

        if outcome["result"] is None:
            outcome["result"], outcome["reason"] = "quit", "exhausted"
        if fix_start is not None:
            fixations.append((fix_start, eye[0], eye[1], max(0, t - fix_start)))
        events.append((t, "buffer" if outcome["result"] == "found" else "failure", outcome["item"]))

        # -- response stage ---------------------------------------------------
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

        self.clock = trial_onset + rt + .050  # feedback production
        if label == _HIT and outcome["item"] is not None:
            for k in p.guiding_features:
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
            "n_fixations": len(fixations), "n_rejected": rejections,
            "quit_reason": outcome["reason"], "n_eff": n_eff,
            "qt": qt, "fixations": fixations,
        }


# --------------------------------------------------------------------------
# Batch helpers
# --------------------------------------------------------------------------

# Parameter type -> observer class.  reference/gs6_hybrid.py registers its own
# pair on import, so every batch helper below runs the model that matches the
# parameters it is given without this file importing the variant.
MODEL_CLASSES: dict = {GSParams: GSHybrid}


def model_for(params, seed: int):
    """The observer class registered for ``type(params)``."""
    try:
        return MODEL_CLASSES[type(params)](params, seed=seed)
    except KeyError:
        raise TypeError(f"No observer registered for {type(params).__name__}") from None


def run_cells(params: GSParams = DEFAULTS, tasks: Sequence[str] = TASKS,
              set_sizes: Sequence[int] = SET_SIZES, n_per_cell: int = 300,
              seed: int = 0, keep_fixations: bool = False,
              burn_in: float = 0.0, practice: int = 30) -> list:
    """Run every task x set size x presence cell and return trial records.

    One simulated observer per task, trials interleaved in random order so the
    adaptive quitting threshold sees a realistic mixture.  The first
    ``burn_in`` fraction of each observer's trials is run but discarded, since
    the threshold starts at ``qt_init`` and has to converge.
    """
    rows = []
    from harness.protocol import observer_plan
    for task in tasks:
        model = model_for(params, seed)                     # one observer per task
        order, rng = observer_plan(task, set_sizes, n_per_cell, seed, practice)
        cut = int(len(order) * burn_in)
        for k, (n, present, is_practice, block) in enumerate(order):
            d = make_display(task, n, present, rng)
            r = model.run_trial(d)
            if k < cut or is_practice:
                continue
            if not keep_fixations:
                r.pop("fixations", None)
                r.pop("events", None)
            r.update(subject_seed=seed, trial=k, practice=False, block=block)
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
    model = model_for(params, seed)
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
    model = model_for(params, seed)
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
    model = model_for(params, seed)
    rng = np.random.default_rng(seed + 900)
    palette = ("red", "blue")   # both differ from the green background items
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
