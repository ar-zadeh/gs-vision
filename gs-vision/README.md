# gs-vision

A replacement vision module for ACT-R 7.31.4 that searches the way people do:
Guided Search 6 for the architecture, Competitive Guided Search for the
selection, identification and quitting arithmetic, PAAV for acuity and iconic
memory, EMMA for eye movements.

It is a **subclass** of `vision-module`, not a fork. `:vision` is undefined and
redefined with the same buffer names, so the motor module, the AGI devices,
the Environment and EMMA all keep working, and every existing model runs
unchanged.

## Loading

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

| Command | Returns |
|---|---|
| `gs-search-stats` | `(fixations rejections elapsed-ms quit-reason)` for the last search |
| `gs-fixation-log` | oldest-first list of `(time-ms x y duration-ms)` |
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

Defaults are the handoff's section 6 values; `tests/test_module_events.lisp`
asserts every one of them.

| Name | Default | Notes |
|---|---|---|
| `:gs-enabled` | `t` | `nil` refuses the new API; the module is then the stock one |
| `:gs-guiding-features` | `(color orient size lum)` | everything else is identification-only |
| `:gs-select-interval` | 0.050 | seconds between covert selections |
| `:gs-diffuser-capacity` | 5 | items identified at once |
| `:gs-choice-beta` | 4.0 | Luce temperature on centred priorities |
| `:gs-id-drift` | 0.25 | Wald mu; mean identification time is theta/mu |
| `:gs-id-threshold` | 0.03 | Wald theta; sigma is fixed at 0.1 |
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

Six places. The Python mirror `reference/gs_hybrid.py` makes the same six
choices, so the two implementations stay comparable.

1. **The adaptive quitting threshold is a persistent unitless scale**, and the
   per-trial threshold is that scale times the effective set size. Section 5.6
   describes it as a value "in units of rejections" whose step also scales with
   the effective set size, which drifts whenever the set size changes between
   trials. The scale form is algebraically the same at fixed set size, and it
   is what the GS6 MATLAB does.

2. **The competitive quit denominator runs over every item not yet rejected**,
   including items being identified. The literal reading of section 5.6 uses
   the eligibility filter of section 5.4 step 1, which excludes the diffuser
   and everything outside the attentional field; that empties the denominator
   mid-search and makes `p(quit)` exactly 1. With the literal reading the
   spatial-configuration miss rate at set size 3 is over 40 percent.

3. **Selection consults the priority map globally.** When the winner is outside
   the attentional field the module looks at it instead of covertly selecting a
   nearby loser. Section 5.4 step 1 restricts covert selection to the
   attentional field, and section 5.6's own worked example requires feature
   search to find the target before anything is rejected; on the 22.5 degree
   benchmark display the target is outside the 8 degree field on 60 percent of
   trials, so the two cannot both hold. The field keeps its meaning; what
   changes is that the winner of the competition is always what happens next.

4. **A dead end is only a dead end when the diffuser is empty.** Section 5.5
   ends "if still none, quit"; items still being identified are not none.

5. **A guided location request takes the maximum priority, not a Luce sample.**
   Section 5.7 says it returns the highest-priority matching location. The
   noise term keeps it stochastic; the soft competition of section 5.4 belongs
   to covert selection, and with it the target wins only 87 percent of feature
   trials, under the 95 percent phase 3 asks for.

6. **The location entry in iconic memory outlives its features.** Features
   expire after `:gs-iconic-span`; the entry stays while the item is in the
   visicon, so an item whose features have all decayed still contributes the
   0.5 "unknown" term to the top-down map rather than vanishing.

Two smaller corrections to the handoff's summary of ACT-R, both taken from the
source: EMMA counts two saccade directions as the same within pi/4, not 90
degrees (`direction=`, `core-modules/motor.lisp` line 894); and EMMA's
peripheral encoding estimate is not its encoding time, because
`complete-eye-move` restarts the encoding at the fovea keeping only the
remaining proportion. Without the second half a covert hit at 12 degrees would
cost 1.7 seconds.

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
