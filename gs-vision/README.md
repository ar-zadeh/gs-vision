# gs-vision

A replacement vision module for ACT-R 7.31.4 that models visual search:
Guided Search 6 for the architecture, Competitive Guided Search for the
selection, identification and quitting arithmetic, PAAV for acuity and iconic
memory, EMMA for eye movements.

It is a **subclass** of `vision-module`, not a fork. `:vision` is undefined and
redefined with the same buffer names, so the motor module, the AGI devices,
the Environment and EMMA all keep working, and every existing model runs
unchanged.

## Loading

Load the module before creating a model.

```
sbcl --load G:/VisualSearchModeling/gs-vision/load-gs-vision.lisp
```

That loads ACT-R, then EMMA, then the five module files, and installs the
subclass. It must run before any `clear-all` or `define-model`:
`undefine-module` prints a warning and does nothing once a model exists.

A model then turns the pieces on:

```lisp
(sgp :emma t :gs-enabled t)
```

Files, in load order:

| File | What is in it |
|---|---|
| `gs-params.lisp` | the `gs-vision-module` class, the `gs-icon`/`gs-diff` records, every `:gs-*` parameter |
| `gs-priority.lisp` | feature channels, the priority map, the numeric helpers |
| `gs-diffuser.lisp` | covert selection, identification, both quit rules, feedback |
| `gs-eye.lisp` | acuity, iconic memory, functional visual fields, saccades |
| `gs-vision.lisp` | creation, reset, request and query dispatch, `define-module-fct` |

The class lives in `gs-params.lisp` rather than `gs-vision.lisp` because the
three middle files use its accessors and are loaded first;
`gs-vision.lisp` has to be last because it calls `define-module-fct` at load
time and that needs the parameter list.

## What a model writes

Use the following requests and queries in productions.

```lisp
;; Guided location request.  Slot values are channel constraints, not equality
;; tests: a symbol names a channel (red, steep, small) and a number is mapped
;; to the channel it falls in.  Only guiding features affect the ranking.
;; screen-x, :nearest and :center still filter exactly as they always did.
;; Costs one :gs-select-interval rather than 0 ms.
+visual-location> isa visual-location color red orient steep :guided t

;; Full search.  The module runs selection, identification, saccades and
;; quitting on its own events.  The target object arrives in the visual buffer,
;; or the search quits and the buffer is left empty with state error.
+visual> isa gs-search color red orient steep
+visual> isa gs-search shape two                ; no guiding feature: unguided
+visual> isa gs-search color red guide color    ; restrict guidance
+visual> isa gs-search color red stop cgs       ; adaptive | cgs | both (default)

;; Feedback, needed for adaptive quitting and priming.
+visual> isa gs-feedback outcome hit            ; hit | miss | fa | tn

;; Queries
?visual> state busy / free / error
?visual> search-result found / failed / none
```

`guide` takes a single slot name; repeat the slot to name several
(`guide color guide orient`). A production cannot write a list as a slot
value, so the `guide (color)` form of the handoff works only when the request
is built with `define-chunk-spec-fct`.

Counts are not buffer queries, because ACT-R queries test symbol equality.
Read them with the commands below.

## Extended visicon features

`add-visicon-features` accepts these in addition to the standard slots. They
are declared by the chunk-type `gs-feature`, so nothing else has to be set up.

| Slot | Type | Meaning |
|---|---|---|
| `hue` | 0-360 | continuous colour; `color` is used when `hue` is absent |
| `orient` | -90..90 | orientation, 0 is vertical |
| `lum` | 0-1 | luminance |
| `shape` | symbol | categorical shape; identification-only |
| `salience` | number | externally computed bottom-up salience; replaces the internal computation |
| `prior` | 0-1 | scene prior |

**Guiding versus identification-only.** `:gs-guiding-features`
(default `color orient size lum`) may guide selection: they are subject to
acuity, they enter the bottom-up and top-down maps, and they can be used in a
`:guided` request. Everything else, `shape` above all, is compared only once
an item is inside the diffuser. That one rule is what makes feature search
efficient and 2-vs-5 inefficient with a single set of mechanisms.

## Commands

These commands expose trial control and diagnostics.

| Command | Returns |
|---|---|
| `gs-search-stats` | `(fixations rejections elapsed-ms quit-reason)` for the last search |
| `gs-fixation-log` | oldest-first stationary intervals `(time-ms x y duration-ms)` |
| `gs-event-log` | timestamped requests, selections, decisions, movement, and results |
| `gs-benchmark-gaze` | place an untimed fixation cross gaze at `x y`; retain learning |
| `gs-cancel-search` | close a timeout and preserve its diagnostics |
| `gs-reset-search` | clears the per-trial state and frees the module; keeps the adaptive state |
| `gs-state` | `(quit-threshold prevalence n-feedbacks)` |
| `gs-quit-lisp` | exits SBCL (defined by `load-gs-vision.lisp`) |

`gs-reset-search` is what an experiment should call between trials. A full
`reset` would wipe the adaptive quitting threshold, the priming traces and the
prevalence window, and those must persist: one model run is one simulated
subject.

## Trace events

All at `:output medium`, so they appear in the standard trace.

```
GS-SEARCH start template (COLOR RED) n-eff 1. qt 1.00
GS-SELECT VISICON-ID2 priority 1.415
GS-DECIDE VISICON-ID2 hit
GS-DECIDE VISICON-ID9 pending (SHAPE)
GS-DECIDE VISICON-ID9 reject
GS-SACCADE 512. 384. -> 700. 500. amp 11.0
GS-FIXATE 706. 495.
GS-QUIT THRESHOLD after 6 rejections, 8 fixations, 1971 ms
GS-FEEDBACK TN qt 0.950 prevalence 0.50
```

## Parameters

Original numeric defaults are retained; the repair adds the policy settings
below. Fixed-parameter ablations did not justify globally promoting bottom-up
weight 3.0 or threshold step 0.005. See [the results](../docs/RESULTS.md).

| Name | Default | Notes |
|---|---|---|
| `:gs-enabled` | `t` | `nil` refuses the new API; the module is then the stock one |
| `:gs-guiding-features` | `(color orient size lum)` | everything else is identification-only |
| `:gs-select-interval` | 0.050 | seconds between covert selections |
| `:gs-diffuser-capacity` | 5 | items identified at once |
| `:gs-choice-beta` | 4.0 | Luce temperature on centred covert priorities |
| `:gs-saccade-margin` | 0.25 | required distant guidance advantage, in priority units |
| `:gs-saccade-proximity` | 0.10 | destination penalty in priority units per degree |
| `:gs-revised-saccades` | `t` | guidance/margin/distance policy; `nil` is the old-policy ablation |
| `:gs-quit-noise-free` | `t` | guidance-only quit weights with beta capped at four |
| `:gs-recognition-extra` | `nil` | `t` restores the historical extra delay for ablations |
| `:gs-id-drift` | 0.25 | Wald mu; mean identification time is theta/mu |
| `:gs-id-threshold` | 0.03 | Wald theta |
| `:gs-id-sigma` | 0.1 | Wald noise; the shape is theta squared over sigma squared, so the CV is sigma / sqrt(theta mu) |
| `:gs-id-error` | 0.0 | probability that an identification decision flips (a rejected target or an accepted distractor) |
| `:gs-onset-latency` | 0.0 | seconds after the request before the first covert selection |
| `:gs-adaptive-quit-delta` | `nil` | `t` divides the competitive quit increment by the adaptive threshold scale, so feedback controls both quit rules |
| `:gs-explore-proximity` | `nil` | `t` chooses the saccade destination by guidance minus distance when nothing is selectable inside `:gs-attn-fvf` |
| `:gs-saccade-trigger` | 0.0 | degrees; when positive, the eye starts moving as soon as the nearest selectable item is farther than this, while covert selection continues |
| `:gs-quit-delta` | 0.02 | competitive quit weight per rejection |
| `:gs-memory` | 4 | inhibition-of-return ring size |
| `:gs-attn-fvf` | 8.0 | degrees within which an item can be selected covertly |
| `:gs-explore-fvf` | 12.0 | degrees within which the next saccade target is chosen |
| `:gs-max-fixation` | 0.4 | seconds before a fixation is abandoned |
| `:gs-iconic-span` | 4.0 | seconds a feature stays available after it was last seen |
| `:gs-acuity-theta` | `(color 0.10 orient 0.20 shape 0.40 size 0.20 lum 0.10)` | EPIC availability slope per feature |
| `:gs-acuity-sigma` | 0.5 | SD of the availability threshold |
| `:gs-w-bu` `:gs-w-td` `:gs-w-h` `:gs-w-v` `:gs-w-s` `:gs-w-e` | 0.5, 1.0, 0.3, 0, 1.0, 0.02 | priority map weights |
| `:gs-noise` | 0.2 | logistic scale on every priority |
| `:gs-priming-tau` | 10.0 | seconds |
| `:gs-qt-init` `:gs-qt-step` `:gs-error-goal` | 1.0, 0.05, 0.08 | adaptive quitting |
| `:gs-feedback-window` | 50 | feedbacks used for the prevalence estimate |
| `:gs-value-hook` | `nil` | function or remote command, called with a location chunk |
| `:gs-log-fixations` | `t` | keep the fixation log |

Every stock vision parameter still exists and still means what it did. They
are not copied out of `vision.lisp`; `gs-capture-vision-parameters` rebuilds
the list from the live parameter table before `undefine-module` drops it,
which keeps the module in step with upstream and off the LGPL derivative
question (handoff section 12, decision 4).

## Where this module reads the handoff differently

These are explicit model revisions, mirrored in `reference/gs_hybrid.py`.

1. The adaptive threshold is a persistent scale multiplied by effective set
   size. Reaching it pauses new selection and drains outstanding evidence.
2. Competitive quit weights cover every unresolved item, including diffuser
   items. They use noise-free, eccentricity-free guidance and beta capped at
   four. Covert choice still uses the configured beta and noisy priorities.
3. Peripheral guidance with an explicit margin triggers a saccade. A separate
   proximity penalty chooses destinations. Useful near work can continue in
   preparation; new selection stops during execution. Oldest pending
   foveation has priority. Strongly guided far targets suppress weaker near
   work that could otherwise exhaust an effective set size of one.
4. A dead end quits only when the diffuser is empty. Identity completion is
   distinct from the decision to stop seeking new evidence.
5. Wald completes recognition when required features are available. The
   normal Wald variate uses Box-Muller in Lisp. No second full encoding is
   charged; stock ACT-R constructs and attends the object at the same time.
   A disappearing target or cancellation cannot deliver a stale object.
6. A guided location request takes the maximum priority; iconic location
   entries survive feature decay and retain uncertainty contributions.

The first selection interval is retained as selection cost. Benchmark gaze
placement is explicit, untimed experiment setup; generic search can continue
from current gaze. Preparation history resets at the benchmark fixation
cross. Fixation records include initial/final intervals, omit execution,
and end at visual result. A peripheral recognition never teleports gaze.

The batch parameter schema separates vision, Python response approximation,
and trial protocol. Complete configurations, units, requested settings,
ACT-R readback, and effective hashes are recorded. The measured keyboard
response approximation is fixed at 160/260/310 ms for repeat/switch/first
responses; it is not a fitted vision parameter. Times held as integer Lisp
milliseconds are normalized before Python simulation and serialization.

## Backward compatibility

`tests/test_backcompat.py` runs `models/legacy-check-model.lisp` and the
tutorial unit 2 and unit 3 models three times each: under stock ACT-R, under
gs-vision with `:gs-enabled t`, and under gs-vision with `:gs-enabled nil`. The
traces must be identical line for line.

One behaviour does change for a model that uses the new API: a `gs-search`
clears the attended-location marker when it starts. A hit otherwise leaves the
*visicon* chunk as the marker, and `:delete-visicon-chunks` deletes and
uninterns that chunk as soon as the display changes, after which ACT-R's own
buffer stuffing warns on every later trial. Clearing it is also the right
semantics: a new display has no attended location. Nothing on the legacy path
touches this.
