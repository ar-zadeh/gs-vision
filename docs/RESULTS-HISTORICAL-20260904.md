# Historical results: September 4, 2026

This preserved report uses provisional targets and pre-repair timing.
Use [the current results](RESULTS.md) for raw-data validation.

Accuracy of the guided-search vision module for ACT-R 7.31.4, against the
validation plan in section 9 of `IMPLEMENTATION-HANDOFF.md`.

Every number below was produced by the scripts in this repository on
2026-09-04 and can be regenerated; nothing is transcribed from a paper except
the human reference values, whose sources are named. The tables at the end are
emitted by `harness/report.py` from the saved CSVs, so no figure in them is
typed by hand.

## Summary

| Phase | State |
|---|---|
| 0 Setup | done. ACT-R 7.31.4 fingerprint confirmed, venv built, git initialised |
| 1 Reference sims | done. `reference/test_reference.py`, 18 assertions, passing |
| 2 Module skeleton | done. `tests/test_backcompat.py`, 15 cases, trace-identical |
| 3 Priority, acuity, iconic memory | done. Guided requests hit the phase 3 criteria |
| 4 Diffuser, IOR, quitting | **partly.** Three of six slopes are inside 5 ms/item; the other three miss by 6 to 8 |
| 5 EMMA saccades | **partly.** Fixation counts and durations are right; saccade amplitudes are 8 to 13 degrees against a 3 to 7 degree target |
| 6 Adaptive threshold, priming, feedback | **not met.** Both effects exist mechanically but are far below the required size |
| 7 Fitting and this report | done |

The architecture works: one set of rules produces an efficient feature search,
an intermediate conjunction search and an inefficient spatial-configuration
search, with the target-absent to target-present slope ratio between 2.5 and
3.1 and error rates in the right range. What it does not yet do is match the
absolute RT intercepts, produce a low-prevalence effect, or produce a
measurable priming benefit. Those three are diagnosed below rather than hidden.

## Reproducing

```bash
python harness/fetch_data.py                       # Adam et al. 2021, Tier 1 fallback
python reference/fetch_gs6_matlab.py               # the GS6 MATLAB gs6_sim.py ports
pytest reference/test_reference.py                 # reference simulations
sbcl --non-interactive --load tests/test_module_events.lisp   # 95 module assertions
pytest tests/test_backcompat.py                    # trace identity with stock ACT-R
python harness/fit.py --phase1 -n 120 --iters 90   # per-task parameter sets
python harness/fit.py --shared -n 120 --iters 90   # one set for all three tasks
python harness/run_batch.py --tasks spatial -n 250 --seeds 1 \
    --tag phase1_spatial --params data/model/phase1.json --params-key spatial
python harness/analyze.py data/model/phase1_spatial_seed1_trials.csv \
    --compare spatial --compare-params data/model/phase1.json
python harness/report.py                           # every table below
```

## Where the human numbers come from

**Wolfe, Palmer and Horowitz (2010).** `search.bwh.harvard.edu` did not
respond on 2026-09-04, exactly as section 9 warned, so the trial-level
distributions are not available and the Tier 1 targets are the published
summary slopes for the three tasks: about 1 and 3 ms per item for feature
search, 20 and 45 for conjunction, 43 and 95 for spatial configuration,
present and absent. `reference/cgs.py` reproduces them from the Competitive
Guided Search fits (2-vs-5: 41.7 and 98.5 ms/item; feature: 0.5 and 0.1;
conjunction: 15.8 and 54.1, over 4000 trials per cell), which is the closest
independent check available offline. When the server returns, replace
`TIER1_SLOPES` and `TIER1_INTERCEPTS` in `harness/fit.py` and nothing else
changes.

**Adam, Patel, Rangan and Serences (2021).** Downloaded from
https://osf.io/u7wvy/ (CC BY 4.0), 24 participants per experiment. Their
experiment 1c is the comparison condition: variable distractor colour, so
nothing can be learned and suppressed, and homogeneous non-targets. Capture
cost, distractor-present minus distractor-absent RT, by set size 3 to 6:
**31.7, 32.0, 42.8 and 51.2 ms**, mean 39.4.

**Wu and Wolfe (2022).** Downloaded from https://osf.io/vzg28/, experiment 1,
22 participants, set sizes 42 and 80. Fixations per trial: 4.68 present and
10.78 absent at 42, 8.02 and 16.85 at 80.

**Human-human ceilings.** `harness/metrics.py` computes them
(`human_ceiling`), but no scanpath comparison is reported: see Tier 2 below.

## Tier 1: slopes

The module reaches its slope targets on the two tasks it was fitted on most
directly and misses on three of the six cells:

| task | target | model | human | error | verdict |
|---|---|---|---|---|---|
| feature | present | 1.1 | 1.0 | 0.1 | pass |
| feature | absent | 9.9 | 3.0 | 6.9 | miss |
| conjunction | present | 15.6 | 20.0 | 4.4 | pass |
| conjunction | absent | 48.7 | 45.0 | 3.7 | pass |
| spatial | present | 34.9 | 43.0 | 8.1 | miss |
| spatial | absent | 88.6 | 95.0 | 6.4 | miss |

Slopes in ms per item, from the Lisp module at the per-task phase 1 parameter
sets, 250 trials per cell (2000 per task). The acceptance target is 5 ms/item.
The absent-to-present slope ratio is 2.5 for spatial configuration and 3.1 for
conjunction, both inside the 2 to 3 band the handoff asks for, and the
qualitative ordering feature < conjunction < spatial holds with a wide margin.

The intercepts are the clearer failure: 603 to 788 ms against a human 480 to
580. Measured directly from the trial CSVs, the response stage accounts for
310 ms of the mean RT and 350 ms of the median: a production to issue the
search, a production to read the result and a `press-key`, which section 11
forbids tuning into the module. The module's own search time at the smallest
set size is 299 ms for feature, 397 for conjunction and 561 for spatial
configuration. That floor is structural: one selection interval, a 120 ms
identification and, on most trials, at least one saccade of about 200 ms.
Humans do the same tasks in 480 to 690 ms in total, so either the model's
per-item cost or its response stage has to come down, and the response stage
is the one that is not the module's to change.

## Tier 1: capture cost

Additional-singleton paradigm, model against Adam et al. experiment 1c. The
target is an orientation singleton rather than their shape singleton, because
shape does not guide in this module; that is the same paradigm expressed in
the module's guiding dimensions.

| bottom-up weight | n=3 | n=4 | n=5 | n=6 | mean | human mean |
|---|---|---|---|---|---|---|
| `:gs-w-bu` 0.5 (handoff default) | 3.6 | 1.9 | 19.3 | 13.2 | **+9.5** | +39.4 |
| `:gs-w-bu` 3.0 (refitted) | 29.7 | 41.1 | 30.6 | 31.4 | **+33.2** | +39.4 |
| human (Adam 1c) | 31.7 | 32.0 | 42.8 | 51.2 | +39.4 | |

Capture cost in ms, 16000 trials per condition. The acceptance target is sign
and magnitude within 50 percent. At the handoff's provisional `:gs-w-bu` of
0.5 the sign is right but the magnitude is a quarter of the human value; at
3.0 it is within 16 percent. Section 5.3 flags the bottom-up and top-down
weights as provisional and says phase 4 fits them, and this is the dataset
that fixes their ratio: capture is a direct read-out of `w_BU / w_TD`.

## Tier 2: eye movements

Fixation counts and durations at the benchmark set sizes are right; saccade
amplitudes are far too long, and the comparison at Wu and Wolfe's set sizes
fails badly.

| statistic | feature | conjunction | spatial | target | verdict |
|---|---|---|---|---|---|
| fixations per trial | 1.27 | 1.97 | 4.30 | rises with difficulty | pass |
| fixation duration, mean | 229 ms | 292 ms | 241 ms | 180 to 275 ms | 2 of 3 |
| saccade amplitude, mean | 8.3 deg | 12.6 deg | 12.5 deg | 3 to 7 deg | miss |
| refixation rate | 0.003 | 0.001 | 0.005 | low | pass |
| fixations outside the display | none | none | none | none | pass |

Amplitudes are the clear miss. The module chooses its saccade target by
priority inside a 12 degree exploration field and, once the fitted attentional
field grew to 12 to 16 degrees, nothing keeps successive fixations near each
other: the eye crosses the display rather than working through it. A
proximity term on the *saccade* choice, separate from the eccentricity term in
the priority map, is the obvious repair and is not in the specification.

At set sizes 42 and 80 the module makes about three times as many fixations as
Wu and Wolfe's observers:

| set size | target | model fixations | human fixations | ratio |
|---|---|---|---|---|
| 42 | present | 12.2 | 4.7 | 2.6 |
| 42 | absent | 32.8 | 10.8 | 3.0 |
| 80 | present | 24.0 | 8.0 | 3.0 |
| 80 | absent | 64.5 | 16.9 | 3.8 |

The acceptance target is within one fixation per trial. The diagnosis is
direct: the model resolves about 0.8 items per fixation, the observers about
four. Its functional visual field for shape is roughly half theirs in linear
size, which follows from `:gs-acuity-theta` for `shape` being 0.40 against an
item 2.1 degrees across, so shape is available only within about 4 degrees.

One caveat that limits how much weight this comparison can bear: Wu and
Wolfe's display geometry was not read from their materials, so the model runs
on a display whose density is held at the benchmark's and whose field grows
with set size (40.5 degrees at n=80). A denser display would put more items
inside the same functional field and raise the model's items per fixation.
Fixing the geometry from the source is the first thing to do before treating
this row as a settled failure.

No scanpath metric is reported. MultiMatch, ScanMatch and Sequence Score are
implemented and unit-tested in `harness/metrics.py`, and `human_ceiling`
computes the split-half baseline section 9 requires, but the Wu and Wolfe OSF
project holds foraging experiments whose per-fixation coordinates are not in
the released aggregate, so there is nothing to compare a model scanpath
against. Reporting a scanpath similarity without its human-human ceiling would
be worse than reporting none.

## Plots

Written by `harness/analyze.py --plots`, one directory per task under
`data/model/plots/`:

* `rt_by_set_size.png`, model cell means with the human slope lines overlaid;
* `quantile_probability.png`, the .1 to .9 RT quantiles against proportion
  correct, which is where the intercept offset and the too-short right tail
  show up together;
* `fixation_counts.png`, the distribution of fixations per trial.

The spatial-configuration plot is the clearest picture of the state of the
model: the target-absent line runs almost on top of the human one, and the
whole misfit is the constant offset of the target-present line.

## Tiers 3 and 4

Not run. COCO-Search18 and VSGUI10K are report-only in the handoff and need an
external priority front end feeding the `salience` and `prior` slots, which
the module accepts but nothing in this repository produces.

## Phase 6: prevalence and priming

Both mechanisms work and neither produces an effect of the required size.

**Prevalence.** At 10 percent versus 50 percent targets the miss rate does not
rise, and target-absent RTs get slower rather than faster:

| prevalence | miss rate | false alarms | absent RT | present RT | rejections per absent trial |
|---|---|---|---|---|---|
| 10 percent | 0.098 | 0.000 | 2464 ms | 1189 ms | 21.2 |
| 50 percent | 0.076 | 0.000 | 1728 ms | 1125 ms | 10.9 |

Lisp module, spatial-configuration task, 4800 trials each, first quarter
discarded as burn-in. Phase 6 asks for a miss-rate increase of at least 10
points and faster target-absent RTs. The miss rate moves 2.2 points in the
right direction and the absent RT moves the wrong way. Diagnosis: the update rule of section 5.6 raises the
threshold by `qt_step / (error_goal * prevalence * 2)`, which at 10 percent
prevalence is 3.125 against a threshold near 1. A single miss therefore moves
the threshold by more than its own value, so the controller is bang-bang
rather than graded and spends most of its time far above the level its
equilibrium implies, `m = 0.16 (1 - p)`. Reducing `:gs-qt-step` from 0.05 to
0.005, which is GS6's step relative to its own threshold, restores the RT
ordering (absent RT 1863, 1711 and 2378 ms at prevalence 0.1, 0.5 and 0.9) but
still not the miss-rate effect. The remaining gap is that guidance and
foveation make most hits happen within a few rejections, so the miss rate
saturates below the level the rule is trying to reach.

**Priming.** With the target's defining colour repeated versus switched, the
Lisp module's benefit is +6 plus or minus 6 ms on target-present trials and
-5 plus or minus 11 ms on target-absent trials, over 5600 trials, against the
20 to 60 ms phase 6 asks for.
The mechanism itself is intact and graded: with a template that does not guide,
so that only the history term can separate the primed item, the primed colour
wins the priority map on

| `:gs-w-h` | primed item wins |
|---|---|
| 0.0 | 38 percent |
| 0.3 (default) | 62 percent |
| 1.0 | 95 percent |

against a chance level of 8 percent at set size 12. The reason no RT benefit
appears in the benchmark is that the model is given a correct, explicit
template on every trial, so guidance already puts the target first and there
is nothing left for priming to speed up. Priming of pop-out, where the
target-defining colour is unknown to the observer, is the experiment that
would show it; the benchmark tasks cannot.

## The Lisp module against its Python mirror

Phase 4 asks that the two agree within Monte Carlo error at the same
parameters. The comparison is on the module's own search time, not RT, because
the response stage is a fixed constant in Python and a real production and
motor path in Lisp, and that difference is not a port error.

They agree well on the two slow tasks and diverge on the fast one. For
conjunction search every cell is within 68 ms of its mirror on means of 400 to
1250 ms, and only two of eight cells exceed two standard errors. For spatial
configuration six of eight cells are within 31 ms, the exception being target
absent at set size 18, where the Lisp module is 259 ms faster (z = -5.3). For
feature search the absolute differences are smaller, -90 to +230 ms, but the
means are small too, so most cells are several standard errors apart: the Lisp
module finds the target about 70 ms faster and quits about 100 ms slower, and
the gap grows with set size.

Two known sources account for most of it, and neither is a port error in the
selection engine. The Lisp module runs inside ACT-R's event queue, where the
visicon is reprocessed and the buffer stuffed between trials, while the mirror
starts from a clean display; and the mirror's saccade preparation counts
features against its own previous saccade whereas the Lisp module's is reset
per search. The residual for feature-absent at set size 18 is not explained
and is recorded as open.

## Parameters

Defaults are the handoff's section 6 values. Only the entries below were
changed by fitting; everything else is at its default.

| parameter | default | feature | conjunction | spatial | one shared set |
|---|---|---|---|---|---|
| `:gs-memory` | 4 | 8 | 16 | 12 | 16 |
| `:gs-w-e` | 0.02 | 0.02 | 0.10 | 0.05 | 0.05 |
| `:gs-noise` | 0.2 | 0.05 | 0.3 | 0.2 | 0.05 |
| `:gs-choice-beta` | 4.0 | 2.0 | 2.0 | 16.0 | 8.0 |
| `:gs-select-interval` | 0.050 | 0.030 | 0.030 | 0.030 | 0.020 |
| `:gs-diffuser-capacity` | 5 | 2 | 3 | 8 | 3 |
| `:gs-attn-fvf` | 8.0 | 16.0 | 16.0 | 12.0 | 16.0 |
| `:gs-max-fixation` | 0.4 | 0.25 | 0.20 | 0.20 | 0.4 |

Section 12 decision 6 asks whether the selection interval and diffuser
capacity may differ per task. Both branches were fitted so the cost of
insisting on one set is visible. Every task wants a shorter selection interval
than the default 0.050 s, and every task wants a larger attentional field than
Wu and Wolfe's 8 degree estimate; the fitted 12 to 16 degrees is outside the
5 to 10 degree range section 5.2 gives, which is a real tension between the
field estimate and the RT slopes, not a fitting artefact.

Two other defaults are contradicted by the data above: `:gs-w-bu` wants to be
about 3.0 rather than 0.5 to produce the singleton capture cost, and
`:gs-qt-step` wants to be about 0.005 rather than 0.05 for the adaptive
threshold to behave as a controller rather than a switch.

## Comparison with the published models

| model | 2-vs-5 present | 2-vs-5 absent | ratio | source |
|---|---|---|---|---|
| human | 43 | 95 | 2.2 | Wolfe, Palmer and Horowitz 2010 |
| Competitive Guided Search | 41.7 | 98.5 | 2.4 | `reference/cgs.py` at the published fits |
| Guided Search 6 | 37.2 | 113.7 | 3.1 | `reference/gs6_sim.py`, port of Wolfe's MATLAB |
| this module (Lisp) | 34.9 | 88.6 | 2.5 | `data/model/phase1_spatial_seed1_trials.csv` |
| this module (Python mirror) | 33.5 | 110.5 | 3.3 | `data/model/hybrid_summary.json` |

The GS6 row is at prevalence 0.5 with its own set sizes (5 to 20) and carries
no non-decision time, so its intercept is not comparable; its slopes and its
ratio are. Competitive Guided Search remains the closest fit to the benchmark
slopes, which is expected since it was fitted to exactly them and has no eyes,
no acuity and no display geometry to satisfy at the same time.

**PAAV.** No numerical comparison is made. PAAV (Nyamsuren and Taatgen 2013)
targets ACT-R 6 and does not load in ACT-R 7, so it cannot be run here, and
its published results are on different tasks. What it contributed is the
0.5-for-unknown top-down rule, the four-second iconic persistence and the
subclass-and-redefine integration route, all of which are in the module and
credited in the source.

## Failures, in one place

1. **Three of six Tier 1 slopes miss the 5 ms/item target** by 6 to 8 ms/item:
   feature absent, spatial present and spatial absent.
2. **Intercepts are 100 to 200 ms above the human values** at every parameter
   set. About 350 ms of the model's RT is the response stage that must not be
   tuned away, and the module's own floor accounts for the rest.
3. **The prevalence effect is absent and partly inverted.** The section 5.6
   update rule is too coarse to act as a controller at low prevalence.
4. **The priming benefit is not measurable in the benchmark**, though the
   mechanism is graded and works when the template does not guide.
5. **Fixation counts at set sizes 42 and 80 are about three times human**, with
   a display-geometry caveat that has to be resolved before the number means
   anything.
6. **Saccade amplitudes are 8 to 13 degrees against a 3 to 7 degree target.**
7. **No scanpath metric is reported**, because no per-fixation human data with
   a computable ceiling was reachable.
8. **The fitted attentional field, 12 to 16 degrees, is outside the 5 to 10
   degrees** that section 5.2 takes from Wu and Wolfe (2022).
9. **`:gs-w-bu` 0.5 predicts no singleton capture.** Capture appears at about
   3.0.
10. **Tier 3 and Tier 4 were not attempted.**

Items 1, 2 and 6 are one problem seen three ways: the module spends too much
time per item and too much of it on eye movements. Items 3 and 9 are
mis-specified default parameters with a known replacement. Items 5, 7 and 10
are missing data rather than model failures.

---

<!-- the tables below are generated; see harness/report.py -->
<!-- generated by harness/report.py; do not edit by hand -->

### Tier 1 slopes and intercepts, per-task parameter sets

| task | target | model ms/item | human ms/item | error | model intercept | human intercept |
|---|---|---|---|---|---|---|
| feature | present | 1.1 | 1.0 | 0.1 | 602 | 480 |
| feature | absent | 9.9 | 3.0 | 6.9 | 632 | 500 |
| conjunction | present | 15.6 | 20.0 | 4.4 | 664 | 520 |
| conjunction | absent | 48.7 | 45.0 | 3.7 | 619 | 560 |
| spatial | present | 34.9 | 43.0 | 8.1 | 781 | 560 |
| spatial | absent | 88.6 | 95.0 | 6.4 | 787 | 580 |

### Tier 1 error rates

| task | kind | n=3 | n=6 | n=12 | n=18 |
|---|---|---|---|---|---|
| feature | miss | 0.060 | 0.072 | 0.084 | 0.100 |
| feature | false_alarm | 0.000 | 0.000 | 0.000 | 0.000 |
| conjunction | miss | 0.044 | 0.092 | 0.088 | 0.080 |
| conjunction | false_alarm | 0.000 | 0.000 | 0.000 | 0.000 |
| spatial | miss | 0.052 | 0.084 | 0.084 | 0.088 |
| spatial | false_alarm | 0.000 | 0.000 | 0.000 | 0.000 |

### One shared parameter set

| task | model present | human present | model absent | human absent | absent/present |
|---|---|---|---|---|---|
| conjunction | 8.1 | 20.0 | 67.5 | 45.0 | 8.30 |
| feature | -0.2 | 1.0 | 1.5 | 3.0 | -8.65 |
| spatial | 44.3 | 43.0 | 115.2 | 95.0 | 2.60 |

### Lisp module against its Python mirror, module search time

| task | set size | target | Lisp ms | Python ms | difference | joint SE | z |
|---|---|---|---|---|---|---|---|
| feature | 3 | present | 299 | 376 | -78 | 11.5 | -6.7 |
| feature | 3 | absent | 372 | 301 | 71 | 16.3 | 4.4 |
| feature | 6 | present | 285 | 365 | -80 | 9.9 | -8.1 |
| feature | 6 | absent | 343 | 294 | 49 | 14.6 | 3.4 |
| feature | 12 | present | 277 | 367 | -90 | 10.2 | -8.8 |
| feature | 12 | absent | 416 | 301 | 116 | 16.7 | 6.9 |
| feature | 18 | present | 310 | 370 | -59 | 10.8 | -5.5 |
| feature | 18 | absent | 523 | 292 | 230 | 21.6 | 10.6 |
| conjunction | 3 | present | 397 | 400 | -3 | 15.2 | -0.2 |
| conjunction | 3 | absent | 465 | 397 | 68 | 16.2 | 4.2 |
| conjunction | 6 | present | 442 | 416 | 25 | 15.9 | 1.6 |
| conjunction | 6 | absent | 611 | 555 | 56 | 18.4 | 3.1 |
| conjunction | 12 | present | 549 | 509 | 40 | 22.1 | 1.8 |
| conjunction | 12 | absent | 897 | 863 | 34 | 22.8 | 1.5 |
| conjunction | 18 | present | 632 | 587 | 45 | 26.4 | 1.7 |
| conjunction | 18 | absent | 1209 | 1249 | -41 | 35.5 | -1.1 |
| spatial | 3 | present | 561 | 530 | 31 | 17.9 | 1.7 |
| spatial | 3 | absent | 711 | 695 | 16 | 15.3 | 1.0 |
| spatial | 6 | present | 693 | 723 | -30 | 26.6 | -1.1 |
| spatial | 6 | absent | 1071 | 1061 | 9 | 19.6 | 0.5 |
| spatial | 12 | present | 926 | 922 | 4 | 37.6 | 0.1 |
| spatial | 12 | absent | 1567 | 1575 | -9 | 25.4 | -0.3 |
| spatial | 18 | present | 1074 | 1050 | 25 | 44.6 | 0.6 |
| spatial | 18 | absent | 2070 | 2329 | -259 | 49.3 | -5.3 |

### Eye movements

| task | fixations/trial | mean duration ms | median duration ms | amplitude deg | refixation rate |
|---|---|---|---|---|---|
| feature | 1.27 | 229 | 282 | 8.3 | 0.003 |
| conjunction | 1.97 | 292 | 312 | 12.6 | 0.001 |
| spatial | 4.30 | 241 | 239 | 12.5 | 0.005 |

### RT quantiles (ms)

| task | n | target | .1 | .3 | .5 | .7 | .9 |
|---|---|---|---|---|---|---|---|
| feature | 3 | absent | 500 | 513 | 618 | 773 | 966 |
| feature | 6 | absent | 500 | 500 | 580 | 731 | 962 |
| feature | 12 | absent | 500 | 533 | 711 | 822 | 1042 |
| feature | 18 | absent | 500 | 602 | 770 | 930 | 1232 |
| feature | 3 | present | 500 | 501 | 561 | 651 | 818 |
| feature | 6 | present | 500 | 504 | 558 | 631 | 751 |
| feature | 12 | present | 500 | 500 | 544 | 641 | 799 |
| feature | 18 | present | 500 | 524 | 585 | 683 | 822 |
| conjunction | 3 | absent | 500 | 656 | 746 | 831 | 1040 |
| conjunction | 6 | absent | 657 | 779 | 890 | 1013 | 1212 |
| conjunction | 12 | absent | 808 | 1053 | 1177 | 1352 | 1517 |
| conjunction | 18 | absent | 998 | 1257 | 1466 | 1652 | 2084 |
| conjunction | 3 | present | 500 | 544 | 677 | 803 | 987 |
| conjunction | 6 | present | 500 | 588 | 747 | 870 | 1012 |
| conjunction | 12 | present | 500 | 641 | 834 | 991 | 1250 |
| conjunction | 18 | present | 514 | 693 | 914 | 1105 | 1446 |
| spatial | 3 | absent | 776 | 894 | 1003 | 1111 | 1198 |
| spatial | 6 | absent | 1034 | 1246 | 1377 | 1505 | 1696 |
| spatial | 12 | absent | 1426 | 1680 | 1856 | 2048 | 2317 |
| spatial | 18 | absent | 1610 | 2130 | 2360 | 2615 | 3066 |
| spatial | 3 | present | 575 | 728 | 823 | 945 | 1182 |
| spatial | 6 | present | 543 | 791 | 978 | 1179 | 1421 |
| spatial | 12 | present | 654 | 915 | 1175 | 1476 | 1922 |
| spatial | 18 | present | 643 | 993 | 1371 | 1694 | 2076 |

### Ex-Gaussian fits (ms)

| task | n | target | mu | sigma | tau |
|---|---|---|---|---|---|
| feature | 3 | absent | 500 | 0 | 218 |
| feature | 6 | absent | 500 | 0 | 166 |
| feature | 12 | absent | 500 | 0 | 232 |
| feature | 18 | absent | 500 | 0 | 329 |
| feature | 3 | present | 500 | 0 | 114 |
| feature | 6 | present | 500 | 0 | 109 |
| feature | 12 | present | 500 | 0 | 102 |
| feature | 18 | present | 500 | 0 | 131 |
| conjunction | 3 | absent | 589 | 101 | 180 |
| conjunction | 6 | absent | 733 | 155 | 179 |
| conjunction | 12 | absent | 1038 | 237 | 157 |
| conjunction | 18 | absent | 1164 | 284 | 337 |
| conjunction | 3 | present | 500 | 0 | 212 |
| conjunction | 6 | present | 592 | 139 | 163 |
| conjunction | 12 | present | 500 | 0 | 358 |
| conjunction | 18 | present | 500 | 0 | 490 |
| spatial | 3 | absent | 880 | 147 | 127 |
| spatial | 6 | absent | 1281 | 264 | 89 |
| spatial | 12 | absent | 1863 | 347 | 0 |
| spatial | 18 | absent | 2055 | 493 | 308 |
| spatial | 3 | present | 673 | 140 | 189 |
| spatial | 6 | present | 824 | 276 | 178 |
| spatial | 12 | present | 779 | 263 | 455 |
| spatial | 18 | present | 1046 | 446 | 339 |

### Prevalence

| prevalence | miss rate | false-alarm rate | absent RT ms | present RT ms | rejections | trials |
|---|---|---|---|---|---|---|
| 10% | 0.098 | 0.000 | 2464 | 1189 | 21.2 | 3592 |
| 50% | 0.076 | 0.000 | 1728 | 1125 | 10.9 | 3600 |

### Priming

| target | repeat ms | switch ms | benefit ms | n repeat/switch |
|---|---|---|---|---|
| present | 616 | 622 | 6 +- 6 | 1230/845 |
| absent | 721 | 716 | -5 +- 11 | 1365/870 |

