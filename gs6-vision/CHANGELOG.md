# gs6-vision changelog

## GS6-1.0 (2026-09-05)

Forked from gs-vision GS-1.0 (post-refit source) as a separate module folder.
Everything the two modules share is byte-identical apart from comments; the
list below is what differs.

### Engine (gs-diffuser.lisp)

- Identification is Wolfe's asynchronous two-bound diffuser, stepped by a
  `gs-diffuser-tick` event every `:gs-diff-step` (10 ms) at scheduler priority
  -10. Replaces the one-shot Wald completion time of gs-vision. Outcomes are
  emergent: distractors can cross the target bound (false alarms) and targets
  the distractor bound (rejections).
- Each item starts at GS6's start point (`prevalence/2 - 0.25` plus a
  persistent adaptive offset). Hits raise the offset, false alarms lower it.
- Quitting is the GS6 quit-signal diffuser against `qt * N_eff / :gs-quit-ss-ref`,
  started by the first rejection. The rejection counter, the adaptive draining
  rule and the default competitive quit unit are gone; `stop cgs` and `both`
  keep the competitive unit as an ablation.
- Feedback restores both prevalence factors of the posted MATLAB.
- A selected item whose template features are unavailable is handled at
  selection time (pending, saccade, activation after landing, or rejection at
  the fovea) instead of after a timer.
- `:gs-memory` defaults to 0: rejected items are reselectable at once.

### Priority map (gs-priority.lisp, gs-eye.lisp)

- `:gs-orient-dual`: Guided Search 2 orientation, a steep/shallow and a
  left/right (`tilt`) dimension driven by the same feature. Iconic memory
  stores the `tilt` channel; a numeric template drives both dimensions.
- `:gs-best-channel`: top-down guidance per dimension uses the template
  channel whose template response exceeds its mean display response by the
  most, relative to the template's own response.
- `gs-available-p` maps `tilt` onto the `orient` feature's availability.

### Parameters (gs-params.lisp)

- Removed `:gs-id-drift`, `:gs-id-threshold`, `:gs-id-sigma`, `:gs-id-error`,
  `:gs-adaptive-quit-delta`.
- Added `:gs-diff-step`, `:gs-diff-inc`, `:gs-diff-noise`, `:gs-targ-thresh`,
  `:gs-dist-thresh`, `:gs-similarity-drift`, `:gs-start-prevalence`,
  `:gs-start-inc`, `:gs-start-dec`, `:gs-quit-inc`, `:gs-quit-noise`,
  `:gs-quit-ss-ref`, `:gs-orient-dual`, `:gs-best-channel`.
- Changed defaults: `:gs-qt-init` 1.5, `:gs-qt-step` 0.005, `:gs-memory` 0,
  `:gs-explore-proximity` t.
- Version string GS6-1.0.

### Module glue (gs-vision.lisp)

- Default `stop` policy `adaptive`.
- Reset clears the quit signal, the start-point offset and the tick event.
- `gs-state` returns the start-point offset as a fourth value.

### Harness and mirror

- `reference/gs6_hybrid.py`: Python mirror, a `GSHybrid` subclass with its
  own `GS6Params`; registered with `gs_hybrid.MODEL_CLASSES` so every batch
  helper dispatches on the parameter type.
- `harness/parameters.py`: recognises both parameter schemas by their keys and
  records `model` in configurations. Frozen gs-vision configurations load
  unchanged.
- `harness/run_batch.py --module gs6`; `harness/gs6_fit.py` (fit, select,
  final, evaluate); `harness/refit_report.py --run-dirs`.
- Tests: `tests/test_gs6_events.lisp` (88 checks), `tests/test_gs6.py`.
