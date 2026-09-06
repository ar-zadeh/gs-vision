# Refit results (September 5, 2026, post-freeze, exploratory)

This round re-fits the gs-vision module after the frozen September 5
validation in [RESULTS.md](RESULTS.md). The frozen model's test summaries had
already been inspected when this round began, so nothing here is a confirmatory
test. This round still selects on the validation participants before its own
test evaluation, and the frozen run directory is untouched.

## Summary

The refit improves the fit to the training participants substantially and the
fit to the held-out test participants moderately, and it does not reach
Wolfe's targets. On the test participants the better candidate (the trigger
base) lowers mean cell quantile RMSE from **127.7 to 100.1 ms** (target 40),
raises slopes within 5 ms/item from **2 to 4 of 6**, and leaves the largest
miss-rate error at **11.3 points** (frozen 10.9; target 3). Feature search
now meets the 40 ms quantile target in seven of eight cells and conjunction
absent cells improve two- to three-fold; spatial cells get worse because the
model now follows the slower training participants. On the validation
participants both refit candidates are worse than the frozen fit, so the
protocol's own selection would keep the frozen model. Saccade amplitude is
unchanged at about 12 degrees. All of this is exploratory.

## What the frozen model's own logs showed

The diagnosis used the frozen run's trial and fixation logs, not the summary
tables. Six problems accounted for the misses recorded in RESULTS.md.

1. **A 130 ms fast edge.** Fast trials were a 50 ms request latency, about
   40 ms of identification and a 110 ms keypress. Human feature and
   conjunction-present quantiles start near 350 ms; the model's ex-Gaussian
   mu pinned at the 200 ms trim bound in 12 of 24 cells.
2. **Identification noise was a hidden constant.** The Wald sampler's noise
   of 0.1 was a `defparameter`, not a parameter. With the fitted threshold it
   forced a coefficient of variation of 1.3 (mean 89 ms, SD 120 ms) on every
   identification, which made present-trial tails and absent-trial spread far
   too wide.
3. **Spatial search paid a mandatory saccade at small set sizes.** Shape was
   resolvable only within about 4 degrees, so at set size 3 the model made
   3.2 fixations and spent 670 ms searching where the human total RT is 694.
4. **The quit controller was inert.** In spatial search every miss came from
   the competitive quit rule while the adaptive threshold scale had drifted to
   about fifty times its starting value; the feedback controller never bound.
5. **False alarms were structurally impossible.** Identification was a timer,
   not a decision.
6. **Saccades exceeded the attentional field.** The covert loop rejected
   everything inside the fitted 11 degree field before the eye moved, and the
   destination was then the guidance winner with icon-order tie-breaking: 94%
   of later conjunction saccades and 70% of later spatial saccades exceeded
   11 degrees.

## What was implemented

Six parameters were added to both the Lisp module and the Python mirror. All
default to the frozen behaviour; the mirror with defaults reproduces the frozen
24,000-trial mirror run row for row, and every earlier configuration file still
loads.

| Parameter | Role |
|---|---|
| `:gs-id-sigma` | Wald identification noise, previously the fixed 0.1 |
| `:gs-id-error` | probability that an identification decision flips (a miss or a false alarm) |
| `:gs-onset-latency` | seconds between the search request and the first covert selection |
| `:gs-adaptive-quit-delta` | divide the competitive quit increment by the adaptive threshold scale |
| `:gs-explore-proximity` | distance-penalised destination when nothing inside the attentional field is selectable |
| `:gs-saccade-trigger` | request a saccade once the nearest selectable item is farther than this, while covert selection continues |

The differential-evolution search moved from six to thirteen dimensions
(identification threshold and noise, decision error, onset latency, IOR
memory, selection interval, bottom-up weight, attentional field, competitive
increment, error goal, choice temperature, priority noise and the shape acuity
slope) and from 72 evaluations to 2,418 per restart, in parallel on the mirror.
Two bases were fitted on the training participants: `explore` (adaptive quit
increment plus distance-penalised exploration) and `trigger` (the same with a
6 degree saccade trigger). One restart each; a second restart per base was
started and stopped for time. The Lisp/mirror parity check was repeated for
each new switch before fitting; the only lean found, under the adaptive quit
increment, flips sign across seeds and vanishes at equal controller state, so
it is drift of the slow feedback controller rather than an implementation
difference. That drift also makes the parity z-test anti-conservative for this
mechanism.

Both fits chose a very regular identification process and a wide attentional
field rather than the wider shape acuity or the long onset latency the
diagnosis anticipated:

| Setting | Frozen shared | Explore fit | Trigger fit |
|---|---|---|---|
| Identification mean / CV | 89 ms / 1.34 | 118 ms / 0.20 | 125 ms / 0.54 |
| Decision error per identification | 0 | 0.0023 | 0.0006 |
| Onset latency | 0 | 24 ms | 60 ms |
| Attentional field | 11.0 deg | 14.7 deg | 14.6 deg |
| Shape acuity slope | 0.40 | 0.43 | 0.43 |
| Error goal | 0.08 (inert) | 0.093 | 0.121 |
| Bottom-up weight | 1.05 | 0.53 | 3.07 |
| IOR memory | 11 | 14 | 16 |
| Training cost (quantile RMSE + error terms, same seed) | 175.5 | 104.4 | 94.6 |

## Validation selection

Selection on the two validation participants per task, with fresh seeds and
400 trials per cell, picked the **frozen** fit. Both refit candidates improve
feature and conjunction and lose heavily on spatial:

| Candidate | Feature | Conjunction | Spatial | Mean |
|---|---|---|---|---|
| Module defaults | 196.9 | 224.8 | 892.1 | 437.9 |
| Frozen shared | 103.1 | 172.2 | 251.0 | 175.4 |
| Refit, explore | 88.3 | 153.4 | 426.6 | 222.8 |
| Refit, trigger | 113.1 | 150.9 | 366.9 | 210.3 |

The spatial loss is a property of the split, not of the mechanisms. The
participant-average means differ by 20 to 30 percent between the splits, and
the validation participants are the outliers in two of the three tasks:

| Task | Split | Absent, N = 3 / 18 | Present, N = 3 / 18 |
|---|---|---|---|
| spatial | train | 911 / 2392 | 762 / 1444 |
| spatial | validation | 694 / 1951 | 599 / 1117 |
| spatial | test | 694 / 2169 | 587 / 1266 |
| feature | train | 460 / 445 | 413 / 433 |
| feature | validation | 353 / 346 | 310 / 327 |
| feature | test | 464 / 457 | 438 / 448 |
| conjunction | train | 544 / 840 | 495 / 616 |
| conjunction | validation | 670 / 1229 | 582 / 727 |
| conjunction | test | 526 / 1024 | 505 / 676 |

A model fitted to the training participants' spatial speed is 20 percent too
slow for the validation participants. The frozen fit undershot the training
participants by about that much and so matched validation by accident. With
two participants per split, validation selection is deciding which pair of
people the model resembles, which is why the like-for-like comparison below
runs every candidate on all three splits.

## Like-for-like comparison in ACT-R

Both refit candidates were run in ACT-R with fresh seeds 601 and 602, 1,000
retained trials per cell per seed, next to the frozen shared run (seeds 401 and
402). Human values are participant-weighted as in RESULTS.md.

| Run | Split | Mean RT RMSE (ms) | Quantile RMSE (ms) | Slopes within 5 ms/item | Largest miss error (points) | Timeouts |
|---|---|---|---|---|---|---|
| Frozen | train | 160.7 | 151.5 | 3/6 | 10.1 | 0 |
| Frozen | validation | 123.7 | 143.1 | 5/6 | 16.5 | 0 |
| Frozen | test | 108.0 | 127.7 | 2/6 | 10.9 | 0 |
| Refit, explore | train | 71.3 | 88.8 | 5/6 | 6.9 | 0 |
| Refit, explore | validation | 223.6 | 191.2 | 2/6 | 9.3 | 0 |
| Refit, explore | test | 138.8 | 128.6 | 4/6 | 6.5 | 0 |
| Refit, trigger | train | 60.0 | 65.7 | 5/6 | 13.2 | 0 |
| Refit, trigger | validation | 191.6 | 173.3 | 2/6 | 14.7 | 0 |
| Refit, trigger | test | 102.5 | 100.1 | 4/6 | 11.3 | 0 |

### Test participants: slopes and intercepts

| Task | Target | Human slope | Trigger | Explore | Frozen | Human intercept | Trigger | Explore | Frozen |
|---|---|---|---|---|---|---|---|---|---|
| conjunction | absent | 33.4 | 20.5 | 28.2 | 38.9 | 418 | 590 | 513 | 498 |
| conjunction | present | 11.2 | 4.8 | 4.0 | 5.9 | 471 | 488 | 448 | 413 |
| feature | absent | -0.8 | 1.2 | 2.5 | 1.7 | 468 | 417 | 398 | 343 |
| feature | present | 0.8 | -0.1 | 0.2 | -0.2 | 434 | 418 | 379 | 381 |
| spatial | absent | 97.7 | 92.9 | 100.8 | 78.1 | 477 | 707 | 717 | 717 |
| spatial | present | 44.5 | 43.6 | 43.1 | 32.0 | 493 | 620 | 645 | 591 |

The spatial slopes are now within 5 ms/item for both candidates, where the
frozen fit missed by 13 to 20. The spatial intercepts did not move: the
mandatory-saccade cost at small set sizes remains, because neither fit chose
the wider shape acuity (both stayed near 0.43). The conjunction absent slope
fell below the human value for the trigger candidate.

### Test participants: cells

| Task | N | Target | Human mean | Trigger | Explore | Frozen | Human q10 | Trigger | Explore | Frozen | Human error % | Trigger | Explore | Frozen | Trigger qRMSE | Explore qRMSE | Frozen qRMSE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| conjunction | 3 | absent | 526 | 620 | 579 | 584 | 426 | 403 | 363 | 298 | 1.9 | 0.1 | 0.5 | 0.0 | 137 | 107 | 140 |
| conjunction | 3 | present | 505 | 501 | 460 | 432 | 393 | 335 | 316 | 231 | 2.8 | 4.3 | 5.3 | 4.2 | 64 | 70 | 104 |
| conjunction | 6 | absent | 612 | 745 | 701 | 746 | 468 | 497 | 422 | 398 | 2.2 | 0.1 | 1.3 | 0.0 | 175 | 151 | 198 |
| conjunction | 6 | present | 542 | 518 | 470 | 444 | 404 | 347 | 322 | 232 | 2.1 | 8.1 | 8.3 | 5.7 | 46 | 77 | 120 |
| conjunction | 12 | absent | 812 | 849 | 861 | 1013 | 537 | 539 | 506 | 503 | 1.0 | 0.4 | 2.4 | 0.0 | 64 | 80 | 248 |
| conjunction | 12 | present | 599 | 548 | 500 | 486 | 421 | 366 | 328 | 250 | 3.4 | 14.6 | 10.0 | 10.0 | 56 | 104 | 134 |
| conjunction | 18 | absent | 1024 | 944 | 1011 | 1167 | 590 | 597 | 570 | 593 | 0.9 | 0.8 | 3.4 | 0.0 | 80 | 23 | 190 |
| conjunction | 18 | present | 676 | 574 | 519 | 517 | 448 | 374 | 332 | 259 | 6.3 | 17.6 | 10.9 | 10.8 | 97 | 155 | 160 |
| feature | 3 | absent | 464 | 420 | 401 | 345 | 357 | 314 | 316 | 214 | 2.8 | 0.1 | 0.3 | 0.0 | 36 | 58 | 119 |
| feature | 3 | present | 438 | 418 | 379 | 378 | 348 | 316 | 306 | 218 | 3.8 | 0.9 | 3.5 | 2.0 | 16 | 50 | 88 |
| feature | 6 | absent | 470 | 425 | 416 | 358 | 352 | 311 | 317 | 212 | 2.8 | 0.1 | 0.5 | 0.0 | 41 | 51 | 115 |
| feature | 6 | present | 435 | 419 | 382 | 381 | 348 | 313 | 308 | 217 | 3.5 | 0.2 | 2.8 | 1.3 | 18 | 53 | 88 |
| feature | 12 | absent | 452 | 432 | 430 | 362 | 345 | 312 | 315 | 214 | 2.8 | 0.1 | 0.8 | 0.0 | 18 | 21 | 98 |
| feature | 12 | present | 445 | 416 | 380 | 380 | 351 | 311 | 307 | 218 | 2.9 | 0.2 | 4.0 | 2.2 | 24 | 60 | 91 |
| feature | 18 | absent | 457 | 439 | 440 | 373 | 346 | 316 | 316 | 215 | 1.4 | 0.1 | 0.5 | 0.0 | 17 | 17 | 96 |
| feature | 18 | present | 448 | 418 | 383 | 376 | 353 | 314 | 308 | 214 | 3.5 | 0.5 | 6.1 | 2.7 | 28 | 65 | 95 |
| spatial | 3 | absent | 694 | 919 | 978 | 874 | 509 | 709 | 742 | 628 | 3.3 | 0.1 | 0.5 | 0.0 | 244 | 301 | 198 |
| spatial | 3 | present | 587 | 715 | 755 | 662 | 418 | 441 | 424 | 330 | 3.7 | 4.3 | 3.5 | 3.8 | 151 | 198 | 122 |
| spatial | 6 | absent | 1111 | 1328 | 1376 | 1212 | 708 | 983 | 1047 | 860 | 2.7 | 0.3 | 1.1 | 0.0 | 264 | 306 | 155 |
| spatial | 6 | present | 790 | 910 | 913 | 796 | 459 | 487 | 446 | 343 | 2.2 | 7.5 | 6.9 | 8.3 | 161 | 171 | 83 |
| spatial | 12 | absent | 1747 | 1860 | 1923 | 1796 | 1104 | 1277 | 1342 | 1026 | 2.8 | 0.6 | 2.3 | 0.0 | 176 | 239 | 129 |
| spatial | 12 | present | 1063 | 1173 | 1189 | 1007 | 513 | 583 | 520 | 426 | 5.4 | 15.2 | 11.5 | 14.3 | 121 | 144 | 61 |
| spatial | 18 | absent | 2169 | 2343 | 2524 | 2034 | 1325 | 1528 | 1470 | 1097 | 2.9 | 0.6 | 3.9 | 0.0 | 219 | 413 | 128 |
| spatial | 18 | present | 1266 | 1381 | 1402 | 1144 | 569 | 625 | 610 | 478 | 10.0 | 19.2 | 13.2 | 20.9 | 151 | 174 | 104 |

Mean false-alarm rate on test cells: trigger 0.29%, explore 1.47%, frozen
0.00%, human 2.30%. Mean miss rate: trigger 7.72%, explore 7.16%, frozen
7.19%, human 4.13%.

What changed, cell by cell:

* **The fast edge is fixed.** Feature q10 moved from 214 to 311 to 316 ms
  against a human 345 to 357; the model's ex-Gaussian mu is no longer pinned
  at the 200 ms trim bound in any cell (see below). This is what turned the
  feature cells from about 100 ms quantile RMSE into 16 to 41 ms.
* **Conjunction absent no longer overshoots at large set sizes** (944 versus
  1167 at set size 18, human 1024), but the trigger candidate's conjunction
  absent slope is now too shallow and its present misses are too high (14.6%
  and 17.6% at set sizes 12 and 18 against 3.4% and 6.3%). The fitted error
  goal of 0.12 is the model trading misses for absent RT; the objective
  weights one percentage point of error like 10 ms of quantile error, which
  was too lenient. A per-task error goal or a heavier error weight is the
  obvious next lever.
* **Spatial follows the training participants.** The training participants'
  absent RT at set size 3 is 911 ms; the model's is 919; the test
  participants' is 694. Correct slopes plus the unchanged intercept put the
  refit above the frozen model on every spatial cell for these two test
  participants.
* **False alarms exist now** but the fits kept them below the human 2.3%.

### Eye movements

| Run | Task | Fixations per trial | Stationary duration (ms) | Saccade amplitude (deg) | Refixation rate |
|---|---|---|---|---|---|
| Trigger | conjunction | 1.85 | 203 | 12.1 | 0.004 |
| Trigger | feature | 1.03 | 203 | 9.7 | 0.014 |
| Trigger | spatial | 5.04 | 149 | 12.3 | 0.004 |
| Explore | conjunction | 1.73 | 206 | 13.8 | 0.002 |
| Explore | feature | 1.03 | 183 | 11.6 | 0.000 |
| Explore | spatial | 5.01 | 158 | 12.9 | 0.003 |
| Frozen | conjunction | 1.98 | 186 | 13.6 | 0.006 |
| Frozen | feature | 1.13 | 125 | 11.6 | 0.043 |
| Frozen | spatial | 4.57 | 142 | 12.8 | 0.004 |

| Run | Task | First saccade (deg) | Later saccades (deg) | Later saccades beyond 11 deg |
|---|---|---|---|---|
| Trigger | conjunction | 9.3 | 16.2 | 85% |
| Trigger | feature | 9.7 | 14.0 | 100% |
| Trigger | spatial | 8.7 | 13.4 | 63% |
| Explore | conjunction | 10.9 | 18.2 | 96% |
| Explore | feature | 11.5 | 21.6 | 100% |
| Explore | spatial | 8.9 | 14.2 | 70% |
| Frozen | conjunction | 10.8 | 16.8 | 94% |
| Frozen | feature | 11.8 | 7.5 | 36% |
| Frozen | spatial | 8.8 | 14.2 | 70% |

Stationary durations in feature and conjunction moved into the 180 to 275 ms
range; spatial stays below it. Amplitude did not improve. The exploration
rule and the 6 degree trigger both fire, but the covert loop still clears the
attentional field before the eye lands, and both fits widened that field to
14.6 degrees, so later saccades still have to jump beyond it. Shorter
saccades need a smaller attentional field, which the RT fit resists, or eye
data in the objective, which these displays do not have.

### Ex-Gaussian shape, test participants

| Task | N | Target | Human mu / sigma / tau | Trigger | Explore | Frozen |
|---|---|---|---|---|---|---|
| conjunction | 3 | absent | 431 / 32 / 95 | 459 / 101 / 161 | 337 / 20 / 241 | 410 / 158 / 174 |
| conjunction | 3 | present | 389 / 27 / 115 | 343 / 49 / 157 | 299 / 13 / 161 | 200 / 0 / 232 |
| conjunction | 6 | absent | 460 / 35 / 152 | 651 / 181 / 94 | 590 / 193 / 111 | 561 / 199 / 185 |
| conjunction | 6 | present | 397 / 26 / 146 | 351 / 46 / 168 | 305 / 16 / 166 | 201 / 1 / 243 |
| conjunction | 12 | absent | 509 / 46 / 302 | 732 / 216 / 116 | 762 / 253 / 99 | 598 / 219 / 415 |
| conjunction | 12 | present | 424 / 47 / 174 | 363 / 48 / 185 | 309 / 17 / 191 | 211 / 12 / 275 |
| conjunction | 18 | absent | 704 / 185 / 320 | 742 / 210 / 201 | 712 / 232 / 299 | 718 / 269 / 448 |
| conjunction | 18 | present | 437 / 46 / 240 | 374 / 54 / 199 | 313 / 22 / 206 | 240 / 39 / 278 |
| feature | 3 | absent | 360 / 29 / 104 | 351 / 54 / 69 | 352 / 50 / 49 | 200 / 0 / 145 |
| feature | 3 | present | 354 / 31 / 84 | 352 / 54 / 65 | 354 / 52 / 25 | 200 / 0 / 168 |
| feature | 6 | absent | 358 / 32 / 112 | 346 / 54 / 80 | 350 / 51 / 66 | 200 / 0 / 158 |
| feature | 6 | present | 355 / 31 / 80 | 353 / 56 / 66 | 348 / 50 / 34 | 200 / 0 / 181 |
| feature | 12 | absent | 349 / 31 / 104 | 336 / 48 / 95 | 352 / 54 / 79 | 200 / 0 / 168 |
| feature | 12 | present | 356 / 31 / 90 | 348 / 53 / 68 | 351 / 51 / 29 | 200 / 0 / 178 |
| feature | 18 | absent | 351 / 31 / 106 | 336 / 46 / 103 | 351 / 54 / 89 | 200 / 0 / 174 |
| feature | 18 | present | 361 / 33 / 86 | 354 / 56 / 64 | 351 / 50 / 32 | 200 / 0 / 176 |
| spatial | 3 | absent | 514 / 58 / 181 | 919 / 161 / 0 | 978 / 169 / 0 | 807 / 174 / 68 |
| spatial | 3 | present | 405 / 32 / 182 | 638 / 197 / 78 | 747 / 230 / 8 | 567 / 215 / 95 |
| spatial | 6 | absent | 739 / 142 / 372 | 1328 / 278 / 0 | 1375 / 273 / 0 | 1212 / 276 / 0 |
| spatial | 6 | present | 422 / 32 / 368 | 652 / 254 / 258 | 678 / 289 / 235 | 526 / 242 / 270 |
| spatial | 12 | absent | 1311 / 344 / 436 | 1859 / 430 / 0 | 1923 / 427 / 0 | 1350 / 467 / 447 |
| spatial | 12 | present | 443 / 31 / 620 | 774 / 324 / 399 | 900 / 428 / 289 | 539 / 240 / 468 |
| spatial | 18 | absent | 1509 / 420 / 660 | 1931 / 545 / 412 | 2076 / 701 / 447 | 1635 / 638 / 398 |
| spatial | 18 | present | 472 / 40 / 794 | 872 / 401 / 509 | 995 / 501 / 407 | 656 / 323 / 488 |

Feature and conjunction-present distributions now have the human shape: a
core near 350 ms with a modest tail. The remaining shape failure is spatial,
where the human distribution is a narrow core (sigma about 30) plus a long
exponential tail and the model's is a wide, symmetric core with no tail. That
is the signature of fixation-count variability standing in for what humans do
within fixations, and it is the next mechanism to look at.

### Implementation agreement

Trigger candidate: 0 of 24 search-time means exceed the Bonferroni family
threshold, maximum |z| 2.08, 2,000 retained trials per cell. Explore
candidate: 1 of 24 exceeds (spatial 18 absent, Lisp 92 ms faster, z −3.34,
0.38 fewer fixations). Both candidates use the adaptive competitive
increment, whose slow controller drift makes trials autocorrelated and the
z-test anti-conservative; in the pre-fit probes the same cell's difference
flipped sign across seeds and vanished when compared at equal controller
state. The exceedance is reported as measured.

## Artifacts and reproduction

Fits, selection, ACT-R runs, mirrors and logs are in
`data/model/refit_20260905/` (`refit_explore_501.json`, `refit_trigger_501.json`,
`selection.json`, `run_manifest.json`, `frozen.json`, `final_lisp.log`,
`mechanism_parity/`). Evaluation tables, plots, ex-Gaussian fits, parity and
eye summaries are in [validation-refit-20260905/](validation-refit-20260905/).

```powershell
.venv/Scripts/python.exe -u harness/refit.py fit --base explore --seeds 501
.venv/Scripts/python.exe -u harness/refit.py fit --base trigger --seeds 501
.venv/Scripts/python.exe harness/refit.py select
.venv/Scripts/python.exe harness/refit.py final --candidates refit_explore_501 refit_trigger_501
.venv/Scripts/python.exe harness/refit.py evaluate
.venv/Scripts/python.exe harness/refit_report.py --runs refit_trigger_501=Trigger refit_explore_501=Explore frozen_shared=Frozen
```

Each fit is 30 generations of a 78-member population at 200 trials per cell,
evaluated on 7 parallel workers; the two bases ran concurrently in about 70
minutes. Checks after the changes: 128 Lisp assertions and 54 Python tests
pass, the frozen report regenerates unchanged, and the mirror with default
switches reproduces the frozen mirror run exactly.
