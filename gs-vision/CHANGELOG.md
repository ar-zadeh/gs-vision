# Changelog

## GS-1.0 (2026-09-04)

First working version. Built against ACT-R **7.31.4** (`framework/version-string.lisp`
major 31, minor 4; `core-modules/vision.lisp` version 11.1, 4666 lines;
`extras/emma/emma.lisp` version 8.2a3), SBCL 2.6.3, Python 3.12 in `.venv`.

### Integration

Subclass, not fork, as handoff section 4 directs. `gs-vision-module` extends
`vision-module`; `:vision` is undefined and redefined with the same buffer
names and the stock parameter list, plus `:guided` on the `visual-location`
buffer and `search-result` on the `visual` buffer. Overridden by CLOS method
specialisation: `pm-module-request`, `find-location`, and an `:after` on
`encoding-complete`. The fallback companion-module route in section 4 was not
needed.

The stock parameter list is **not copied** from `vision.lisp`.
`gs-capture-vision-parameters` rebuilds it from the live parameter table
before `undefine-module` drops it. That keeps the module in step with upstream
and avoids making the file a derivative of ACT-R's LGPL source
(section 12, decision 4).

### Deviations from the handoff, all deliberate

Six readings, each recorded in the README with the reason and, where it
matters, the number that forced it. The Python mirror `reference/gs_hybrid.py`
makes the same six choices.

1. The adaptive quitting threshold is a persistent unitless scale multiplied by
   the effective set size at test time, as the GS6 MATLAB does, rather than a
   value in rejections shifted by a set-size-dependent step.
2. The competitive quit denominator covers every item not yet rejected,
   including items in the diffuser. The literal reading empties the denominator
   mid-search and forces `p(quit)` to 1; spatial-configuration misses at set
   size 3 then exceed 40 percent.
3. Selection consults the priority map globally; when the winner is outside the
   attentional field the module saccades to it instead of covertly selecting a
   nearby loser. Without this, feature search misses about 30 percent of
   targets at set size 18 and its RT falls with set size, because on the 22.5
   degree benchmark display the target is outside the 8 degree field on 60
   percent of trials.
4. A dead end quits only when the diffuser is also empty.
5. A `:guided` location request takes the maximum priority rather than a Luce
   sample, which is what section 5.7's wording says and what phase 3's 95
   percent criterion needs.
6. An iconic-memory *entry* outlives its features, so an item whose features
   have decayed still contributes the 0.5 "unknown" term to the top-down map.

Two corrections to the handoff's summary of ACT-R, read from the source:

* EMMA treats two saccade directions as the same within pi/4, not 90 degrees
  (`direction=`, `core-modules/motor.lisp` line 894).
* EMMA's peripheral encoding estimate is not its encoding time.
  `complete-eye-move` restarts the encoding at the new eccentricity keeping
  only the remaining proportion; `gs-encoding-time` reproduces that. Without it
  a covert hit at 12 degrees costs 1.7 s.

### Bugs found and fixed while building

* Request slot-value pairs were assembled in reverse, so the template read
  `(RED COLOR)` and nothing guided. Every task looked like 2-vs-5.
* `GS-QUIT` was scheduled as a maintenance event, so a failed search never woke
  conflict resolution and no production ever responded to it.
* The gaze started at EMMA's default marker, the screen origin, which opened
  every first search with a 23 degree saccade out of the top-left corner. An
  unset gaze now centres on the visicon, as a fixation cross would; an
  experiment that calls `set-eye-location` first keeps control.
* `gs-reset-search` left the module in the busy state when a trial was
  abandoned mid-search, so every later trial's search production was blocked on
  `?visual> state free`. One timed-out trial silently took the rest of the
  block with it.
* A hit left the raw visicon chunk as the attended-location marker.
  `:delete-visicon-chunks` deletes and uninterns it at the next display change,
  after which ACT-R's own buffer stuffing warned on every trial. The marker is
  now cleared when a search starts or the trial is reset.
* `gs-search` did not declare the standard feature slots, so
  `+visual> isa gs-search color red` drew a "slot invalid for type" warning.

### Verification

* `tests/test_module_events.lisp`: 95 assertions, all passing. Installation,
  every parameter default, channels, acuity, the Wald and normal samplers,
  hits, quits, inhibition of return, both quit rules separately, eye
  movements, guidance, feedback, priming, the guided location request and the
  legacy path.
* `tests/test_backcompat.py`: 15 cases passing. `models/legacy-check-model.lisp`
  and four tutorial unit 2 and unit 3 models produce trace-identical runs under
  stock ACT-R, under gs-vision with `:gs-enabled t`, and with `:gs-enabled nil`.
* `reference/test_reference.py`: the Competitive Guided Search and GS6
  reference simulations reproduce their published behaviour.

### Known limitations

* Identification is error-free, as Competitive Guided Search has it. False
  alarms come from the response stage, not from the item diffuser. GS6's
  adjustable identification start point is not implemented; it is section 12
  decision 5 and remains open.
* The RT intercepts sit 200 to 350 ms above the human values at every fitted
  parameter set. `docs/RESULTS.md` reports the residual per cell rather than
  absorbing it into the module, as section 11 requires.
* Orientation channels are exclusive with soft boundaries. Guided Search 2
  proper lets one item drive a steep/shallow and a left/right channel at once;
  the handoff records the simplification in section 5.1 and it is kept.
* Tier 3 (COCO-Search18) and Tier 4 (VSGUI10K) are report-only and were not
  run. They need an external priority front end feeding the `salience` and
  `prior` slots.
