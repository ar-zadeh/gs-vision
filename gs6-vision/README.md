# gs6-vision

The Guided Search 6 variant of [gs-vision](../gs-vision/README.md): the same
ACT-R 7.31.4 vision-module subclass, the same buffer API, the same acuity,
iconic memory, functional visual fields and EMMA saccades, but with Wolfe's
own identification and quitting engine in place of Competitive Guided Search,
and with two Guided Search 2 priority-map rules that gs-vision simplified.

It lives in its own folder so that the frozen gs-vision validation is never
touched. The two modules define the same class and parameter names and cannot
be loaded into one Lisp image; pick one load file.

```
sbcl --load G:/VisualSearchModeling/gs6-vision/load-gs6-vision.lisp
```

Models turn it on exactly as before: `(sgp :emma t :gs-enabled t)`. Every
request, query and command documented for gs-vision works unchanged
(`gs-search`, `gs-feedback`, `:guided` location requests, `gs-search-stats`,
`gs-fixation-log`, `gs-event-log`, `gs-reset-search`, `gs-benchmark-gaze`).
`gs-state` returns a fourth value, the start-point offset. The default `stop`
policy is `adaptive`, the GS6 quit signal alone; `cgs` and `both` add the
competitive unit as an ablation.

## What Wolfe specifies, and how it is implemented

The engine follows `GS6publicAsPostedJan2021.m` (Wolfe 2021, OSF 9n4hf;
`reference/gs6_sim.py` is the line-by-line port). The text of Wolfe (2021)
and Wolfe (1994) supplies the rest.

| Mechanism | GS6 | Here |
|---|---|---|
| Selection | one item every 50 ms into a diffuser of 5 | unchanged from gs-vision: Luce choice on the priority map inside the attentional field |
| Identification | two-bound diffusion per item, stepped every 10 ms: `evidence += sign * (N(0,1) * 0.05 * 2.5 + 0.05)`, bounds +1 and -1 | `gs-diffuser-tick`, one scheduled event per `:gs-diff-step` at priority -10 so that a same-millisecond selection is stepped on the tick that follows it, as in the MATLAB |
| Errors | emergent: a distractor reaching +1 is a false alarm, a target reaching -1 is rejected | the same; `:gs-similarity-drift` optionally slows a distractor in proportion to its template similarity, which the paper describes and the code fixes |
| Start point | `prevalence/2 - 0.25`, +0.0008 after a hit, -0.05 after a false alarm | `gs-start-point`: the prevalence term uses the module's running estimate; the offset persists across trials |
| Quitting | a quit signal, started by the first rejection, growing `N(0,1) * 0.018 * 2.5 + 0.018` per step, against `1.5 * SS / 10` | the same, scaled by the effective set size (items with TD >= 0.5, at least 1) instead of the raw set size, because this module has guidance |
| Feedback | TN: threshold -= 0.005 * prev; miss: threshold += 0.005 / (0.08 * prev * 2) * (1 - prev) | `gs-feedback`, both prevalence factors restored |
| Memory | the diffuser only | `:gs-memory 0`; the IOR ring is available for the few-item memory GS4/GS6 allow |
| Orientation channels (GS2) | an item drives steep/shallow and left/right at once | `:gs-orient-dual`: two dimensions, `orient` and `tilt`, derived from the `orient` feature |
| Top-down guidance (GS2) | the channel that best separates target from distractors | `:gs-best-channel`: per dimension, the template channel whose template response exceeds its mean display response by the most |

Not in GS6, kept from gs-vision because Wolfe does not specify them: EPIC
acuity, the 8 degree attentional and 12 degree exploratory fields, EMMA
saccade timing, the saccade policy (`:gs-explore-proximity` is on by default
here), and the response stage in the harness.

Two departures from the posted code are deliberate. When an item crosses the
target bound and the quit signal crosses its threshold on the same step, the
hit wins; the MATLAB's quit test overwrites the yes response, an artefact of
two independent `if` blocks. And a selected item whose template features are
not yet visible asks for a saccade at selection time rather than after a
timer; it is rejected only if its features are still unavailable at the fovea.

## Parameters

Parameters shared with gs-vision keep their names and meanings; see that
README. Removed: `:gs-id-drift`, `:gs-id-threshold`, `:gs-id-sigma`,
`:gs-id-error`, `:gs-adaptive-quit-delta`. Changed defaults: `:gs-memory` 0,
`:gs-qt-init` 1.5, `:gs-qt-step` 0.005, `:gs-explore-proximity` t. New:

| Name | Default | GS6 name | Meaning |
|---|---|---|---|
| `:gs-diff-step` | 0.010 | RTstep | seconds between diffuser updates |
| `:gs-diff-inc` | 0.05 | adifInc | evidence per step toward the correct bound |
| `:gs-diff-noise` | 2.5 | adifNoise / adifInc | step noise SD as a multiple of the increment |
| `:gs-targ-thresh` | 1.0 | TargThresh | accept bound |
| `:gs-dist-thresh` | -1.0 | DistThresh | reject bound |
| `:gs-similarity-drift` | 0.0 | (paper text) | distractor drift is `inc * (1 - this * similarity)` |
| `:gs-start-prevalence` | t | StartPoint(1) | start at `prevalence/2 - 0.25` plus the offset |
| `:gs-start-inc` | 0.0008 | StartInc | start-point rise per hit |
| `:gs-start-dec` | 0.05 | StartDec | start-point fall per false alarm |
| `:gs-quit-inc` | 0.018 | quitInc | quit signal per step |
| `:gs-quit-noise` | 2.5 | quitNoiseSD / quitInc | quit step noise SD as a multiple |
| `:gs-qt-init` | 1.5 | quitThresh(1) | threshold at `:gs-quit-ss-ref` effective items |
| `:gs-quit-ss-ref` | 10.0 | max(SS) * 0.5 | threshold is `qt * N_eff / this` |
| `:gs-qt-step` | 0.005 | quitDownStep | threshold fall per true negative, times prevalence |
| `:gs-error-goal` | 0.08 | missDesired | miss rate the controller converges on |
| `:gs-orient-dual` | t | GS2 | steep/shallow and left/right at once |
| `:gs-best-channel` | t | GS2 | best-channel top-down rule |

## Trace events

```
GS-SEARCH start template (COLOR RED) n-eff 1. qt 0.150 start 0.000
GS-SELECT VISICON-ID2 priority 1.415
GS-DECIDE VISICON-ID9 pending (SHAPE)
GS-DECIDE VISICON-ID9 reject
GS-DECIDE VISICON-ID2 hit
GS-QUIT THRESHOLD after 6 rejections, 3 fixations, 971 ms, quit signal 0.912 of 0.900
GS-FEEDBACK TN qt 1.498 start-offset 0.0008 prevalence 0.50
```

## Mirror, tests and fit

`reference/gs6_hybrid.py` is the Python mirror (a subclass of the gs-vision
mirror); `harness/parameters.py` recognises its parameter set by its keys, so
`run_batch.py --module gs6 --params <file> --params-key gs6` drives the Lisp
module and `harness/gs6_fit.py` runs the fit, selection, ACT-R final runs and
evaluation. `tests/test_gs6_events.lisp` and `tests/test_gs6.py` are the unit
tests. Results are in [docs/RESULTS-GS6-20260905.md](../docs/RESULTS-GS6-20260905.md).
