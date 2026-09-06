# Model comparison (September 6, 2026, exploratory)

This document answers one question: does gs-vision fit the Wolfe, Palmer and
Horowitz (2010) benchmark better than the other models of visual search, and
if some model fits better, what does it do differently? Sixteen configurations
of ten model families were scored on the same participants, splits, trimming,
objective and code. The six ACT-R rows are the runs already reported in
[RESULTS.md](RESULTS.md), [RESULTS-REFIT-20260905.md](RESULTS-REFIT-20260905.md)
and [RESULTS-GS6-20260905.md](RESULTS-GS6-20260905.md); the ten new rows are
trial-level models implemented in `reference/baselines.py`, fitted to the
training participants by `harness/compare_models.py` with the objective the
gs-vision fits used (`harness.fit.quantile_cost`), and scored with
`harness.evaluate.compare`. Everything is exploratory: the frozen gs-vision
test summaries were inspected on September 5, before this comparison.

## Summary

1. **gs-vision is the best model that has eyes and runs in ACT-R, and it is
   within about 20 ms of the best models of any kind.** On the held-out test
   participants the September 5 refit has mean cell quantile RMSE 100 ms.
   The two best models, a serial self-terminating model (80 ms) and
   Competitive Guided Search (83 ms), are trial-level models with no display,
   no eye and a free response stage. Every other model with a spatial layer
   or an ACT-R run is worse: the fitted gs6-vision variant 123 ms, the frozen
   gs-vision fit 128 ms, the stock ACT-R vision loop with its timing fitted
   137 ms and without fitting 501 ms.
2. **The 20 ms gap is inside the participant noise.** The training
   participants' own averages, used as a "model" of the test participants,
   score 93 ms on this metric, and the ranking of the top five models
   reverses on the validation participants (where the frozen gs-vision fit is
   best). Nothing fitted on these splits can be expected to reach the 40 ms
   target, and differences under about 25 ms between models are not
   interpretable.
3. **What the better models do differently is not a search mechanism.** The
   serial model and CGS win on the RT distributions because each fits its own
   non-decision time per response and an exponential residual, and because
   their per-item timing is free per task. gs-vision keeps its response stage
   fixed at the values measured from ACT-R's motor module and derives task
   differences from the display and the template. Both trial-level models
   still under-shoot the conjunction-absent tails, and the serial model's
   fitted values (23 ms per item in conjunction search, an inspection-time
   coefficient of variation of 1.2) are not a plausible mechanism.
4. **PAAV (added September 6, as a display-level mirror of its ACT-R 6
   source) scores 383 ms at its posted values and 275 ms with nine
   parameters fitted.** Feature search fits; conjunction absent slopes are
   three times too steep as posted (94 ms/item) and repaired by the fit
   (28); spatial-configuration search is nearly efficient in both (5/23 and
   6/14 ms/item against 45/98), because shape is resolvable within about 9
   degrees and PAAV's binary contrast rule makes the 2 pop out among 5s; the
   posted acuity leaves corner items outside iconic memory, which gives 10
   percent misses in feature and spatial search. The fit removes bottom-up
   activation (weight 0.03) and raises noise to get there. No Lisp parity
   check exists for these rows. Artifacts: `paav*.json` in the comparison
   directory, `paav*_cells.csv` and plots in `docs/validation-comparison-20260906/`.
5. **Where gs-vision actually loses is the miss rate, not the RTs.** Its
   largest miss-rate error is 11 points against 3 to 7 for the trial-level
   models; in conjunction and spatial search at set size 18 it misses 18 to
   19 percent of targets where humans miss 6 and 10. The quit rule, not the
   timing, is the mechanism to work on next.

## What was compared

| Model | Where | What it does |
|---|---|---|
| gs-vision (frozen, refit, defaults) | ACT-R module, `gs-vision/` | Priority map with acuity, covert selection into a five-item Wald diffuser, IOR ring, EMMA saccades, competitive plus adaptive quitting, fixed measured response stage |
| gs6-vision (defaults, posted, fitted) | ACT-R module, `gs6-vision/` | Same spatial layer with Wolfe's posted GS6 two-bound diffuser, quit-signal diffuser and feedback rules |
| Serial self-terminating (FIT) | `reference/baselines.py` | Treisman and Gelade: one preattentive stage for feature search; random-order serial inspection with perfect memory, exhaustive on absent trials; per-inspection miss probability |
| Competitive Guided Search | `reference/baselines.py` | Moran et al. 2013: Luce-choice selection with a target weight, Wald identification, full inhibition, a quit unit that gains weight per rejection. `shared timing` fits guidance and quitting per task and everything else once; `per task` is the paper's protocol, all eight parameters per task |
| Fixation-based (Hulleman and Olivers 2017) | `reference/baselines.py` | 250 ms fixations examining up to k items (per task), memory for the last few fixations, quit at a coverage fraction, per-fixation detection probability |
| Parallel race | `reference/baselines.py` | Townsend-style race with a capacity exponent, per-task processing rate and target advantage; present when the target finishes, absent when the slowest distractor finishes |
| GS6 engine, pure | `reference/baselines.py` on `reference/gs6_sim.py` | Wolfe's posted MATLAB simulation with a per-task target selection weight and a response stage; `posted` keeps the engine values, `rates fitted` frees them |
| ACT-R stock vision module | `reference/baselines.py` (timing mirror) | Find/attend/test production loop on the default module: 0 ms location request, 85 ms attention shift, three 50 ms productions, four 3 s finsts, random choice among unattended items, the same measured response stage as gs-vision. Variants: 20 finsts; timing fitted |
| PAAV (Nyamsuren and Taatgen 2013) | `reference/baselines.py` (display-level mirror of `paav-visual-module_2014.01.15.lisp`, added September 6) | Request/attend/test loop on the ACT-R 6 module: per-feature acuity `s > a e^2 - b e` with the posted `a`, `b`; iconic memory; bottom-up activation as binary feature dissimilarity over `1 + sqrt(pixel distance)`; top-down 1 / 0.5 / 0 per template feature (match / not visible / mismatch); `1.1 BU + 0.45 TD + noise`, highest wins; permanent attended marks; the visual decision threshold (`:relevancy higher`) that removes zero-top-down candidates and candidates no farther than the last attended object with no more top-down activation than it; 20 ms + 2 ms/deg saccades with landing noise, 50 ms encoding, three 50 ms productions per item. Runs on the same displays as gs-vision. Variants: posted values with the measured response stage; noise, map weights, encoding, production count, acuity scale and response stage fitted |

The trial-level models were fitted with differential evolution (population 8
per dimension, 60 generations, 200 trials per cell, seed 1001) on the
training participants, then run at 2 seeds by 1,000 trials per cell. The
stock ACT-R rows are a mirror of the module's timing, not a run in ACT-R.
PAAV was not implemented: it requires ACT-R 6, and its one-item-per-fixation
architecture is bracketed here by the fixation-based model (k fitted to
about 2 items per fixation in spatial search) and the stock ACT-R loop.

## Headline: test participants

Quantile RMSE is the mean over the 24 cells of the RMSE across the .1, .3,
.5, .7 and .9 correct-RT quantiles. Miss and false-alarm percentages are means
over cells with the human value in brackets.

| Model | In ACT-R | Fitted params | Mean RT RMSE (ms) | Quantile RMSE (ms) | feature | conjunction | spatial | Slopes within 5 ms/item | Largest miss error (points) | Miss % (human) | FA % (human) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| *Training participants' averages* | | | 120.9 | *93.3* | 25 | 60 | 195 | 5/6 | 2.0 | 3.5 (4.1) | 1.18 (2.30) |
| Serial self-terminating (FIT) | no | 9 | 108.8 | **80.5** | 14 | 71 | 157 | 3/6 | 6.7 | 3.2 (4.1) | 0.85 (2.30) |
| Competitive Guided Search, shared timing | no | 12 | 106.6 | **82.9** | 29 | 68 | 152 | 2/6 | 6.1 | 4.6 (4.1) | 1.15 (2.30) |
| Competitive Guided Search, per task | no | 24 | 132.3 | **98.8** | 24 | 84 | 189 | 2/6 | 2.7 | 3.6 (4.1) | 1.87 (2.30) |
| gs-vision, September 5 refit | yes | 13 | 102.5 | **100.1** | 25 | 90 | 186 | 4/6 | 11.3 | 7.7 (4.1) | 0.29 (2.30) |
| Fixation-based (Hulleman and Olivers) | no | 12 | 103.1 | **105.6** | 76 | 78 | 163 | 3/6 | 5.9 | 5.0 (4.1) | 0.01 (2.30) |
| GS6 engine, pure, rates fitted | no | 12 | 148.7 | **114.3** | 22 | 100 | 222 | 1/6 | 4.2 | 3.3 (4.1) | 1.27 (2.30) |
| gs6-vision, engine rates fitted | yes | 16 | 163.4 | **122.5** | 42 | 98 | 227 | 3/6 | 18.4 | 11.1 (4.1) | 1.30 (2.30) |
| GS6 engine, pure, as posted | no | 6 | 124.4 | **123.3** | 121 | 78 | 171 | 2/6 | 12.0 | 7.6 (4.1) | 1.40 (2.30) |
| gs-vision, frozen shared fit | yes | 6 | 108.0 | **127.7** | 99 | 162 | 122 | 2/6 | 10.9 | 7.2 (4.1) | 0.00 (2.30) |
| Parallel race | no | 14 | 131.8 | **129.4** | 72 | 131 | 185 | 3/6 | 8.6 | 1.5 (4.1) | 1.18 (2.30) |
| ACT-R stock vision, timing fitted (mirror) | no | 6 | 116.1 | **137.3** | 29 | 171 | 211 | 2/6 | 10.0 | 0.0 (4.1) | 0.00 (2.30) |
| PAAV, fitted (mirror) | no | 9 | 455.3 | **275.4** | 49 | 109 | 668 | 3/6 | 6.4 | 2.3 (4.1) | 0.00 (2.30) |
| gs6-vision, engine posted, spatial layer fitted | yes | 8 | 487.3 | **312.9** | 92 | 304 | 543 | 4/6 | 14.5 | 8.0 (4.1) | 1.45 (2.30) |
| gs-vision, module defaults | yes | 0 | 529.1 | **365.4** | 103 | 265 | 729 | 3/6 | 12.4 | 7.1 (4.1) | 0.00 (2.30) |
| PAAV, posted values (mirror) | no | 0 | 526.4 | **382.9** | 71 | 497 | 582 | 2/6 | 9.0 | 8.4 (4.1) | 0.00 (2.30) |
| ACT-R stock vision, 4 finsts (mirror) | no | 0 | 705.3 | **501.1** | 116 | 546 | 841 | 2/6 | 18.4 | 7.3 (4.1) | 0.00 (2.30) |
| ACT-R stock vision, 20 finsts (mirror) | no | 0 | 742.1 | **540.1** | 116 | 574 | 930 | 2/6 | 10.0 | 0.0 (4.1) | 0.00 (2.30) |
| gs6-vision, Wolfe's values | yes | 0 | 1251.9 | **795.1** | 157 | 564 | 1664 | 3/6 | 10.8 | 9.1 (4.1) | 1.48 (2.30) |

The first row is not a model. It is the training participants' cell
quantiles and error rates scored against the test participants, and it is the
level a model that reproduced its training data perfectly would reach.

## The ranking is not stable across splits

| Model | Train | Validation | Test |
|---|---|---|---|
| Training participants' averages | 0 | 192.9 | 93.3 |
| Serial self-terminating (FIT) | 64.0 | 189.9 | 80.5 |
| Competitive Guided Search, shared timing | 79.4 | 184.8 | 82.9 |
| Competitive Guided Search, per task | 48.6 | 196.1 | 98.8 |
| gs-vision, September 5 refit | 65.7 | 173.3 | 100.1 |
| Fixation-based | 105.7 | 204.8 | 105.6 |
| GS6 engine, pure, rates fitted | 113.2 | 183.0 | 114.3 |
| gs6-vision, engine rates fitted | 97.5 | 191.8 | 122.5 |
| gs-vision, frozen shared fit | 151.5 | 143.1 | 127.7 |
| Parallel race | 111.4 | 208.2 | 129.4 |
| ACT-R stock vision, timing fitted (mirror) | 173.7 | 149.6 | 137.3 |

Three things follow. The two validation participants per task differ from the
training participants by 20 to 30 percent in speed (RESULTS-REFIT-20260905.md),
so every model fitted to the training participants scores 170 to 210 ms on
them and the frozen fit, which happens to sit between the groups, wins there.
The per-task CGS fit is the best training fit (49 ms) and loses 50 ms on
test, which is what 24 free parameters on five or six participants buys. And
the spatial task dominates every model's misfit (150 to 230 ms on test) for
the same reason it dominates the human split-to-split difference (195 ms):
those two test participants are faster than the training group by 200 to 400
ms at the large set sizes.

## What the better-fitting models do

The serial model and the shared-timing CGS fit score 80 and 83 ms on test
against gs-vision's 100. Where the difference comes from:

- **A free response stage.** Both fit a non-decision time per response
  (serial: 320 ms present, 339 ms absent; CGS: 275 and 239 ms) and an
  exponential residual (rates 10 and 42 per second). gs-vision's response
  stage is fixed at the 160/260/310 ms measured from ACT-R's motor module
  and was never fitted to human RT, by design (RESULTS.md, "Sources and
  protocol"). The fixed stage costs the model the fast edge in feature search
  (its q10 is 36 ms early on the test participants) and the first-quantile
  of conjunction-absent trials.
- **Free per-task timing.** The serial model fits an inspection time per task
  (15 ms for the feature stage, 23 ms per item in conjunction, 116 ms per
  item in spatial search) and lets every inspection vary with a coefficient
  of variation of 1.2. CGS fits a target weight and a quit increment per task
  (feature 786 and 497, conjunction 23.7 and 2.6, spatial 1.9 and 0.055).
  gs-vision has one identification process and one quit controller; the task
  differences come from colour, orientation and shape acuity on a display,
  and from the template. That is the price of being a model of vision rather
  than of the three tasks.
- **Nothing about eyes, acuity or attention fields.** Neither model has a
  display. They cannot be asked about fixations, saccade amplitude,
  eccentricity effects or the attentional field, which are the checks
  gs-vision fails (RESULTS.md, "Eye-data interpretation"). The fixation-based
  model, the only trial-level model with an eye-like unit, scores 106 ms with
  a fitted 276 ms fixation examining about 17 items in feature search, 9 in
  conjunction and 2 in spatial search; its human-like fixation count comes
  with a feature-search misfit of 76 ms.

What the two models do *not* do well: both under-shoot the conjunction-absent
tails (q90 errors of -127 ms for the serial model and -40 ms for CGS at the
large set sizes; gs-vision's refit is +51 ms), and the serial model's ratio
of absent to present slopes is fixed at 2 where the humans show 3.0 in
conjunction search. The serial fit reaches its score with parameters that
are not a mechanism: 23 ms per item is half the fastest published estimate
of a serial inspection, and a coefficient of variation above 1 means the
"inspection" is mostly an exponential waiting time. It is a curve.

The Competitive Guided Search result is the one to read against the
literature. Moran et al. report quantile misfits of 35, 22 and 5 ms for the
2-versus-5, conjunction and feature tasks fitted per participant; here the
same model fitted to group averages gets 152, 68 and 29 ms on held-out
participants and 91, 45 and 10 ms on its training participants. The
difference is the protocol, not the model: group quantiles across
participants who differ by 30 percent in speed are wider than any
participant's, and held-out participants differ from the fitted ones.

## Where gs-vision loses and where it does not

By task and quantile on the test participants (mean signed error of the
model quantile, ms; positive is too slow):

| Model | Task | Present cells | Absent cells | q10 | q50 | q90 |
|---|---|---|---|---|---|---|
| gs-vision refit | feature | 21 | 28 | -36 | -12 | -24 |
| gs-vision refit | conjunction | 66 | 114 | -29 | +11 | +51 |
| gs-vision refit | spatial | 146 | 226 | +129 | +211 | +140 |
| CGS shared | feature | 38 | 19 | +21 | +15 | -2 |
| CGS shared | conjunction | 48 | 88 | -58 | -46 | -40 |
| CGS shared | spatial | 64 | 240 | +44 | +171 | +106 |
| Serial FIT | feature | 16 | 11 | 0 | -14 | +3 |
| Serial FIT | conjunction | 37 | 105 | -10 | -37 | -127 |
| Serial FIT | spatial | 151 | 162 | +71 | +148 | +201 |

gs-vision's refit is as good as CGS in feature search and better than the
serial model in the conjunction tails; it loses in the spatial task, where it
is uniformly 130 to 210 ms slow on these two participants (it follows the
slower training group, as RESULTS-REFIT-20260905.md recorded), and in
conjunction-absent trials at set sizes 3 and 6, where its first quantiles are
100 ms late because the covert loop pays a saccade before it can quit.

The one measure where every trial-level model beats every ACT-R run is the
miss rate. Present-trial error at set size 18 on the test participants:

| | Human | Serial | CGS shared | CGS per task | gs-vision refit | gs-vision frozen | gs6-vision fitted |
|---|---|---|---|---|---|---|---|
| conjunction | 6.3 | 2.9 | 7.4 | 3.6 | 17.6 | 10.8 | 8.4 |
| spatial | 10.0 | 3.3 | 13.2 | 8.3 | 19.2 | 20.9 | 7.4 |

gs-vision's quit rule (competitive unit plus adaptive threshold) gives up on
targets that are still in the diffuser or still waiting for a saccade; the
fitted error goal of 0.12 in the refit is a symptom, not a cause. The GS6
variant's quit rule has the opposite structural problem (RESULTS-GS6-20260905.md:
excess misses at small set sizes). CGS's quit unit, whose weight grows with
each rejection against a fixed target weight, produces misses that rise with
set size at close to the human rate with one parameter per task. That is the
mechanism worth transplanting: the module already has the competitive unit,
but its increment is shared across tasks and competes with the adaptive
threshold rather than replacing it.

## What ACT-R gives without gs-vision

The stock vision module is the relevant baseline for "is the module worth
having". Driven by the ordinary find/attend/test loop it costs 235 ms per
attended item, so conjunction search runs at 47 to 57 ms per item present and
118 ms per item absent (human 11 and 33), spatial search at 94 to 119 and 235
(human 45 and 98), and feature search responds "absent" in 210 ms because the
failed location request is free. Its quantile RMSE is 500 to 540 ms. Letting
its attention latency, production count, finst count and response times vary
brings it to 137 ms, still behind every fitted search model, and the fit does
it by driving the attention latency to 6 ms and the finst count to 19, which
is no longer the stock module. With four finsts and more than four candidates
the loop never terminates on absent trials without a counting strategy, which
is why the four-finst row needs one and why the fitted row shows zero misses.
None of this is a run in ACT-R; it is the module's documented timing.

## Caveats

- The trial-level models were optimised far more thoroughly (about 4,000 to
  7,000 objective evaluations each, 60 generations) than the gs-vision refit
  (2,418 evaluations, one restart) or the frozen fit (72 evaluations). That
  favours the trial-level rows on the training split and, with these small
  splits, probably on the test split too.
- The trial-level models fit their own response stage; gs-vision's is fixed
  from ACT-R measurements. Two free parameters worth of advantage sit in
  every non-ACT-R row.
- Two test participants per task. The training-group floor of 93 ms and the
  validation reversal are the measure of how much the test ranking means.
- Trial-level models have no display, so cell structure (which item is where,
  what the template is) is not a constraint on them. gs-vision's task
  differences are derived; theirs are fitted.
- The stock ACT-R rows are a timing mirror. Running them in ACT-R would
  require a separate model file and driver; the timing is documented and the
  mirror reproduces it exactly (`tests/test_baselines.py`).
- The pure GS6 engine rows use Wolfe's set-size scaling of the quit threshold
  (`N / 10`) unchanged for set sizes 3 to 18.

## Artifacts and reproduction

Fits, final runs and logs: `data/model/comparison_20260906/` (one JSON per
model with values, bounds, cost and evaluation count; `<model>_mirror_seed<s>.json`
finals; `pipeline.log`). Evaluation: `docs/validation-comparison-20260906/`
(`evaluation.json`, `REPORT-TABLES.md`, `<model>_<split>_cells.csv`,
`<model>_<split>_slopes.csv`, `<model>_<split>.png`, `human_<split>.csv`).
The ACT-R rows are read from their own validation directories and are not
copied.

```powershell
.venv/Scripts/python.exe -u harness/compare_models.py fit        # DE on train, 14 workers, about 30 min
.venv/Scripts/python.exe -u harness/compare_models.py final      # 2 seeds x 1000 trials per cell
.venv/Scripts/python.exe -u harness/compare_models.py evaluate   # train/validation/test CSVs, plots, evaluation.json
.venv/Scripts/python.exe -u harness/compare_models.py report     # REPORT-TABLES.md
.venv/Scripts/python.exe -m pytest tests/test_baselines.py reference/test_reference.py -q
```

The pipeline was run once end to end; the parallel race was refitted after
per-task processing rates were added (its first fit, without them, scored
331 on the training objective), and the fitted stock-ACT-R variant was
refitted after the 20 s trial time-out was added to the mirror, because a
finst count below the candidate count otherwise loops forever on absent
trials. Both are in `pipeline.log`.
