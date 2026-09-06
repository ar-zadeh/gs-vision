# Secondary validation


<!-- BEGIN VALIDATION GENERATED -->

These manipulations use the frozen shared fit. Weight sweeps are calibration. Intervals resample simulation seeds (three mirror, two ACT-R); the human capture interval resamples participants. They do not measure model individual differences.

| Implementation | Study | Contrast | Mean ms | 95% interval ms |
|---|---|---|---|---|
| mirror | known | switch minus repeat | -3.45 | -16.59 to 16.78 |
| mirror | unknown | switch minus repeat | 0.20 | -1.53 to 1.15 |
| mirror | unknown_no_history | switch minus repeat | -11.24 | -16.92 to -7.17 |
| mirror | capture w_bu=0.500 | present minus absent | 1.68 | -11.90 to 14.45 |
| mirror | capture w_bu=1.049 | present minus absent | 10.58 | 3.71 to 17.39 |
| mirror | capture w_bu=3.000 | present minus absent | 28.70 | 22.25 to 34.75 |
| ACT-R | known_priming | switch minus repeat benefit | -2.93 | -10.04 to 4.17 |
| ACT-R | unknown_priming | switch minus repeat benefit | -6.19 | -7.79 to -4.59 |
| ACT-R | unknown_no_history | switch minus repeat benefit | -22.47 | -39.01 to -5.94 |
| ACT-R | capture | distractor cost | 7.63 | 2.53 to 12.74 |
| ACT-R | capture_bu3 | distractor cost | 22.97 | 21.75 to 24.19 |
| human | Adam Search 1c, 24 participants | present minus absent | 39.41 | 31.64 to 47.96 |

The capture analogue uses an orientation target; Adam uses a shape target. The shared mirror cost is below half the human mean, while w_bu=3 moves closer. That sweep does not establish a matched replication or justify the substantial conjunction-search cost. The known-template control reveals the target color; the unknown-color protocol instead identifies a two among fives without revealing the upcoming guiding color. Neither establishes the 20–60 ms priming target. Counts of retained and correct repeat/switch trials are in the accompanying CSVs.

## Prevalence

The contrasts compare low with equal target prevalence.

| Implementation | 10%-50% miss points | 95% interval | Absent RT change ms | 95% interval |
|---|---|---|---|---|
| mirror | 2.35 | 1.56 to 3.13 | 123.2 | 65.2 to 196.8 |
| ACT-R | 1.47 | 1.28 to 1.65 | 87.3 | 77.1 to 97.5 |

The original project target requires at least a 10-point miss increase and faster absent responses. This model fails that joint target. Mirror blocks use 1,000 practice then 2,000 retained trials per seed. ACT-R uses the benchmark block schedule and 3,200 retained trials per seed. These are separate checks; no matched secondary parity claim is made. The prevalence plot shows threshold and rolling errors; seed-level rare-target counts and final state are retained.

## Human eye consistency

These estimates compare matched human conditions across participant halves.

| Metric | Human split-half mean |
|---|---|
| scanmatch | 0.4257 |
| sequence_score | 0.1742 |
| vector | 0.9491 |
| direction | 0.6841 |
| length | 0.9494 |
| position | 0.8405 |
| duration | 0.6777 |

Model-to-human comparison: not computed: keypress benchmark ends at visual result; continuous foraging uses a click and uncentered starts. Source item rotations and exact onset/result timestamps are absent. Human split-half values are conditional descriptive consistency, not a ceiling for the unmatched benchmark.

<!-- END VALIDATION GENERATED -->
