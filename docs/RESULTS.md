# Results

A comparison of this model with other models of visual search, fitted to
the same participants, is in [RESULTS-COMPARISON-20260906.md](RESULTS-COMPARISON-20260906.md).

A later, exploratory refit of the same day is reported separately in
[RESULTS-REFIT-20260905.md](RESULTS-REFIT-20260905.md). It adds six
parameters that default to the behaviour measured below, so nothing in this
document changes; its test-split numbers are not confirmatory because the test
summaries below had already been inspected.

The validation repairs are implemented, but the revised model does not meet
all quantitative human targets. On untouched test participants, the shared
ACT-R fit has mean RT RMSE **108.0 ms**, mean cell quantile RMSE **127.7 ms**
(target: at most 40 ms), and **2 of 6** slopes within 5 ms/item. The largest
miss-rate difference is **10.9 percentage points** (target: at most 3).
Final shared runs contain 2,000 retained trials per cell across two fresh
seeds, with no timeouts. Lisp/mirror search means have no discrepancy beyond
the predeclared Bonferroni threshold across 24 cells; maximum |z| is 1.47.

The [historical report](RESULTS-HISTORICAL-20260904.md) preserves the old
provisional targets and event-loop RT measurements. They are not current
human validation. The old intercept ranges are superseded by the measured
intercept errors in the generated slope CSVs.

## Sources and protocol

All 111,777 source trials are retained in the normalized archive. RT analysis
uses correct trials at 200–4,000 ms for feature/conjunction and 200–8,000 ms
for spatial search, inclusive. Accuracy uses all validated behavioral rows.
Positive-RT sensitivity and pooled descriptive summaries are separate.
The protocol follows [Wolfe, Palmer, and Horowitz's source methods](https://pmc.ncbi.nlm.nih.gov/articles/PMC2891283/).

Participants are weighted equally, including their quantiles. The split seed
is 20260905. Within each task, training/validation/test counts are 5/2/2,
6/2/2, and 5/2/2. Simulation practice is synthetic: 30 trials precede each
300-trial block, with a final block of up to 400. Accuracy feedback follows
keypress; the next display appears 2 seconds after response. Tasks have
separate observers and learned state. Displays reproduce a distribution;
the source RT files do not supply original item coordinates.

The first selection interval remains a modeled selection cost. Wald
identification completes recognition when features are available. ACT-R
then constructs the buffer object without a second full recognition delay.
Measured response-stage times are 160 ms for repeated keys, 260 ms for
switches, and 310 ms for the first response. Feedback is outside trial RT.
The runner's event-loop return is usually 90 ms later than keypress, and is
never used as the response timestamp.

## Development and frozen testing

Two independent DE searches fit six parameters against training quantiles
and separate error rates. Each uses four generations and an 18-member
population, followed by larger independent validation simulations. This is
a bounded optimization exercise, not evidence of optimizer convergence or
a global optimum. Drift, priority temperature, and noise are fixed in the
new search to reduce redundant scale fitting. Local sensitivity is reported
without reselecting parameters after the freeze.

The primary model shares all search settings across tasks. Per-task searches
and historical settings were secondary candidates. Feature and spatial
validation selected the shared settings; their final simulations are reused
explicitly. Conjunction selected a historical alternative with 11 parameter
fields differing from the shared fit, including its 16-degree attentional
field. This secondary setting exceeds the new DE field bound and must not
be interpreted as one universal model. All candidates were selected before
test evaluation. Future tuning based on these test results is exploratory.

## Controlled mechanism evidence

Fixed-parameter ablations use seeds 321 and 322. Removing extra recognition
saves approximately 43–49 ms on present trials; it does not explain the whole
historical intercept gap. Under the revised eye policy, spatial fixation
count falls from 12.92 to 6.06 per trial, and stationary durations increase
from 146 to 188 ms. Mean saccade amplitude falls only from 12.81 to 11.81
degrees, still outside the 3–7 degree project check.

The final shared RT fit also misses the eye checks. Its stationary durations
are 124.8 ms (feature), 186.3 ms (conjunction), and 142.2 ms (spatial), against
the 180–275 ms project range. Spatial amplitude is 12.77 degrees and count is
4.57 per trial. These are benchmark search-window measures, not a matched
comparison with continuous-foraging episodes.

The default bottom-up weight remains 0.5. At 3.0, default conjunction absent
RT rises from 1,146 to 2,812 ms and fixation count from 2.46 to 6.38; a
capture benefit does not justify promoting it globally. The default
threshold step remains 0.05. The 0.005 ablation changes speed and accuracy
without establishing the intended prevalence behavior. Both candidates and
their trajectories are retained for review. The selected human fit has its
own complete, explicit settings.

The unchanged GS6 replication retains the posted MATLAB's prevalence
exception: low prevalence does not produce the intended human combination
of sharply increased misses and faster absent RT. Shrinking the controller
step is not a demonstrated solution. See the secondary experiment results
for the revised hybrid's residual failure.

The [secondary results](validation-20260905/SECONDARY-RESULTS.md) report
capture, both priming protocols, the history ablation, prevalence, and human
split-half eye consistency. The shared mirror capture cost is 10.6 ms against
the 39.4 ms human analogue; raising the weight to 3 gives 28.7 ms. This is
calibration with different target features, not a matched replication.

## Eye-data interpretation

The nested OSF [Experiment 1 component](https://osf.io/qwm6r/) supplied
`Exp1Data.mat`, exported using the installed MATLAB. It contains 146,956
fixations from 19 participants; the author's script selects 18. Adding target
episode to subject/trial/fixation identity resolves 14 apparent repeated
indices without deleting any records. Participant-average foraging measures
are 15.98 fixations per episode, 249.1 ms per fixation, 5.41-degree saccades,
and a 9.5% refixation rate under a one-degree proximity definition.

The [Wu and Wolfe methods](https://pmc.ncbi.nlm.nih.gov/articles/PMC8976560/)
describe 1-degree T/L stimuli on a 10-by-8 grid at 2.5-degree spacing,
continuous target replacement, and click responses. The source table agrees
with that geometry (120-pixel spacing; 47.76 pixels per degree). The separate
`RealData.csv` concerns 42/80-item keypress search; it is not this fixation
table or the 2-versus-5 benchmark. Its undocumented accuracy coding is not
used as a new fitting target.

Human split-half ScanMatch, Sequence Score, and MultiMatch are computed for
100 target/initial-gaze-matched conditions. They are descriptive human
consistency estimates. Model-to-human scanpath scores and the within-one-
fixation criterion remain unavailable for a matched experiment: original
rotations, stimulus/result timestamps, and a model observation window aligned
with continuous foraging clicks are missing. Benchmark fixation logs end at
visual result. Their counts cannot be equated with the foraging episodes.

## Reproducible artifacts

Review [the run record](validation-20260905/run-record.json),
[the selected configurations](validation-20260905/selected.json), and
[the final shared test plot](validation-20260905/shared_test.png).
The same directory contains all 24-cell summaries, five quantiles, confidence
intervals, error counts, slopes/intercepts, ex-Gaussian fits, parity tables,
ablation summaries, and secondary study results. Full trial, event, and
fixation logs remain under `data/model/repair_20260905/`. The original
StuffIt archive was inspected as an archive, but its contents could not be
decoded with the available archive tool; it is not combined with raw RTs.

The original frozen selection metadata understates the historical conjunction
candidate's extra settings. Its value of six describes the new DE search
dimension; the selected historical candidate differs from shared in eleven
fields. The [metadata erratum](validation-20260905/selection_metadata_erratum.json)
records those fields while preserving the original freeze.

Final checks pass: 115 Lisp assertions, 18 reference tests, 15 compatibility
tests, 17 validation tests, and ten CLI help checks. A concurrent-test failure
exposed the tutorial client's shared port-file race. The runner now uses a
private handshake and a separate client module per session; a nested-session
regression verifies isolation. Complete parameter readback rejected the wrong
server during the failed test. The failed logs remain in the run directory.

Run `harness/report.py --manifest ... --final-test` with the venv to regenerate
the marked section below. It verifies source/split/configuration hashes and
fails for missing required inputs. See the run record for complete commands.


<!-- BEGIN VALIDATION GENERATED -->

## Raw-data validation

Human values use validated source trials and equal participant weights. ACT-R RT runs from stimulus onset to first valid keypress. Practice is excluded from retained counts. Full cell tables, confidence intervals, quantiles, and plots are in the evaluation artifact directory.

Source rows: 111,777. Split ID: `3909d6744a259e3a836b682ca7f2f15766cb8c1c58581145042a72c5fdb7f841`.


| Run | Role | Split | Mean RT RMSE (ms) | Quantile RMSE (ms) | Slopes within 5 ms/item | Largest miss error (points) | Timeouts |
|---|---|---|---|---|---|---|---|
| unfitted | unfitted | train | 465.9 | 351.9 | 3/6 | 11.5 | 0 |
| unfitted | unfitted | validation | 593.4 | 411.1 | 5/6 | 15.6 | 0 |
| unfitted | unfitted | test | 529.1 | 365.4 | 3/6 | 12.4 | 0 |
| shared | primary | train | 160.7 | 151.5 | 3/6 | 10.1 | 0 |
| shared | primary | validation | 123.7 | 143.1 | 5/6 | 16.5 | 0 |
| shared | primary | test | 108.0 | 127.7 | 2/6 | 10.9 | 0 |
| task_feature | secondary | train | 71.9 | 78.2 | 2/2 | 0.8 | 0 |
| task_feature | secondary | validation | 44.7 | 93.2 | 2/2 | 0.6 | 0 |
| task_feature | secondary | test | 84.9 | 98.8 | 2/2 | 2.2 | 0 |
| task_conjunction | secondary | train | 198.6 | 203.0 | 0/2 | 6.7 | 0 |
| task_conjunction | secondary | validation | 79.1 | 98.9 | 1/2 | 7.1 | 0 |
| task_conjunction | secondary | test | 134.4 | 157.9 | 1/2 | 6.1 | 0 |
| task_spatial | secondary | train | 205.1 | 184.8 | 0/2 | 10.1 | 0 |
| task_spatial | secondary | validation | 163.7 | 200.7 | 1/2 | 16.5 | 0 |
| task_spatial | secondary | test | 104.3 | 122.3 | 0/2 | 10.9 | 0 |


### Primary ACT-R fit: train

These are measured participant-average means. Error rates use all behavioral trials independently of RT trimming.


| Task | N | Target | Human mean | ACT-R mean | Human median | ACT-R median | Quantile RMSE | Human error % | ACT-R error % | Human RT count | Model RT count | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| conjunction | 3 | absent | 543.6 | 583.7 | 515.0 | 571.5 | 128.4 | 2.01 | 0.00 | 2957 | 1993 | 0 |
| conjunction | 3 | present | 495.3 | 432.5 | 464.3 | 366.8 | 101.0 | 2.15 | 4.25 | 2893 | 1875 | 0 |
| conjunction | 6 | absent | 597.4 | 745.8 | 558.1 | 729.0 | 199.2 | 1.46 | 0.00 | 2942 | 1998 | 0 |
| conjunction | 6 | present | 511.7 | 443.7 | 481.2 | 362.0 | 117.2 | 2.71 | 5.70 | 2913 | 1861 | 0 |
| conjunction | 12 | absent | 717.8 | 1013.1 | 649.7 | 933.5 | 356.6 | 1.35 | 0.00 | 2986 | 1999 | 0 |
| conjunction | 12 | present | 562.3 | 485.6 | 524.2 | 404.5 | 126.9 | 3.05 | 9.95 | 3022 | 1791 | 0 |
| conjunction | 18 | absent | 840.0 | 1166.7 | 763.2 | 1103.2 | 372.6 | 1.19 | 0.00 | 2898 | 1998 | 0 |
| conjunction | 18 | present | 616.0 | 517.4 | 566.2 | 426.5 | 129.8 | 4.44 | 10.85 | 2808 | 1771 | 0 |
| feature | 3 | absent | 459.6 | 345.1 | 410.7 | 313.2 | 102.2 | 1.73 | 0.00 | 2447 | 1939 | 0 |
| feature | 3 | present | 412.7 | 378.4 | 381.3 | 328.2 | 66.9 | 1.99 | 2.00 | 2463 | 1911 | 0 |
| feature | 6 | absent | 446.8 | 357.6 | 408.9 | 317.5 | 88.7 | 1.31 | 0.00 | 2535 | 1916 | 0 |
| feature | 6 | present | 426.7 | 381.1 | 390.0 | 327.5 | 64.2 | 2.14 | 1.30 | 2331 | 1904 | 0 |
| feature | 12 | absent | 442.8 | 362.1 | 406.4 | 319.5 | 81.0 | 0.93 | 0.00 | 2468 | 1928 | 0 |
| feature | 12 | present | 427.6 | 380.3 | 394.8 | 328.0 | 71.5 | 1.91 | 2.20 | 2414 | 1884 | 0 |
| feature | 18 | absent | 444.8 | 373.5 | 404.0 | 325.0 | 76.8 | 0.43 | 0.00 | 2548 | 1937 | 0 |
| feature | 18 | present | 432.9 | 376.2 | 398.8 | 324.8 | 73.8 | 2.78 | 2.70 | 2425 | 1885 | 0 |
| spatial | 3 | absent | 910.6 | 874.3 | 844.1 | 880.0 | 65.2 | 0.86 | 0.00 | 2426 | 2000 | 0 |
| spatial | 3 | present | 761.9 | 662.3 | 714.0 | 634.5 | 109.4 | 1.63 | 3.75 | 2411 | 1920 | 0 |
| spatial | 6 | absent | 1320.3 | 1212.0 | 1254.5 | 1231.2 | 119.0 | 0.86 | 0.00 | 2464 | 2000 | 0 |
| spatial | 6 | present | 917.2 | 796.5 | 846.6 | 759.2 | 131.6 | 1.93 | 8.30 | 2493 | 1832 | 0 |
| spatial | 12 | absent | 1983.4 | 1796.4 | 1913.5 | 1754.2 | 200.7 | 1.03 | 0.00 | 2461 | 2000 | 0 |
| spatial | 12 | present | 1220.9 | 1007.1 | 1120.4 | 922.0 | 203.2 | 6.33 | 14.30 | 2316 | 1711 | 0 |
| spatial | 18 | absent | 2391.8 | 2033.5 | 2321.6 | 1987.8 | 353.7 | 1.01 | 0.00 | 2474 | 2000 | 0 |
| spatial | 18 | present | 1444.0 | 1144.0 | 1312.1 | 1079.2 | 295.6 | 10.84 | 20.95 | 2219 | 1580 | 0 |


### Primary ACT-R fit: validation

These are measured participant-average means. Error rates use all behavioral trials independently of RT trimming.


| Task | N | Target | Human mean | ACT-R mean | Human median | ACT-R median | Quantile RMSE | Human error % | ACT-R error % | Human RT count | Model RT count | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| conjunction | 3 | absent | 669.6 | 583.7 | 569.0 | 571.5 | 99.4 | 1.31 | 0.00 | 996 | 1993 | 0 |
| conjunction | 3 | present | 582.1 | 432.5 | 491.5 | 366.8 | 118.7 | 1.75 | 4.25 | 985 | 1875 | 0 |
| conjunction | 6 | absent | 750.9 | 745.8 | 644.5 | 729.0 | 96.9 | 1.12 | 0.00 | 974 | 1998 | 0 |
| conjunction | 6 | present | 594.7 | 443.7 | 519.8 | 362.0 | 133.9 | 2.82 | 5.70 | 997 | 1861 | 0 |
| conjunction | 12 | absent | 969.4 | 1013.1 | 883.0 | 933.5 | 163.4 | 0.97 | 0.00 | 987 | 1999 | 0 |
| conjunction | 12 | present | 671.2 | 485.6 | 588.0 | 404.5 | 165.1 | 2.43 | 9.95 | 964 | 1791 | 0 |
| conjunction | 18 | absent | 1228.9 | 1166.7 | 1167.5 | 1103.2 | 123.3 | 1.22 | 0.00 | 948 | 1998 | 0 |
| conjunction | 18 | present | 726.7 | 517.4 | 619.8 | 426.5 | 182.0 | 5.01 | 10.85 | 955 | 1771 | 0 |
| feature | 3 | absent | 352.5 | 345.1 | 342.0 | 313.2 | 65.6 | 1.26 | 0.00 | 1028 | 1939 | 0 |
| feature | 3 | present | 309.7 | 378.4 | 302.5 | 328.2 | 111.6 | 1.43 | 2.00 | 961 | 1911 | 0 |
| feature | 6 | absent | 348.3 | 357.6 | 338.0 | 317.5 | 81.2 | 1.35 | 0.00 | 1015 | 1916 | 0 |
| feature | 6 | present | 316.6 | 381.1 | 306.5 | 327.5 | 106.3 | 1.60 | 1.30 | 921 | 1904 | 0 |
| feature | 12 | absent | 346.9 | 362.1 | 336.0 | 319.5 | 89.7 | 1.00 | 0.00 | 996 | 1928 | 0 |
| feature | 12 | present | 320.3 | 380.3 | 312.0 | 328.0 | 102.7 | 2.05 | 2.20 | 1002 | 1884 | 0 |
| feature | 18 | absent | 346.4 | 373.5 | 335.0 | 325.0 | 90.5 | 0.69 | 0.00 | 1004 | 1937 | 0 |
| feature | 18 | present | 327.3 | 376.2 | 317.5 | 324.8 | 98.3 | 3.32 | 2.70 | 932 | 1885 | 0 |
| spatial | 3 | absent | 694.1 | 874.3 | 639.0 | 880.0 | 207.2 | 2.27 | 0.00 | 1039 | 2000 | 0 |
| spatial | 3 | present | 598.9 | 662.3 | 554.8 | 634.5 | 128.9 | 0.87 | 3.75 | 930 | 1920 | 0 |
| spatial | 6 | absent | 951.2 | 1212.0 | 881.5 | 1231.2 | 294.0 | 1.10 | 0.00 | 983 | 2000 | 0 |
| spatial | 6 | present | 691.1 | 796.5 | 634.0 | 759.2 | 191.7 | 1.25 | 8.30 | 962 | 1832 | 0 |
| spatial | 12 | absent | 1506.5 | 1796.4 | 1404.5 | 1754.2 | 334.7 | 0.30 | 0.00 | 1000 | 2000 | 0 |
| spatial | 12 | present | 921.5 | 1007.1 | 825.8 | 922.0 | 159.3 | 2.22 | 14.30 | 972 | 1711 | 0 |
| spatial | 18 | absent | 1950.7 | 2033.5 | 1806.0 | 1987.8 | 178.3 | 0.58 | 0.00 | 1042 | 2000 | 0 |
| spatial | 18 | present | 1117.0 | 1144.0 | 1008.5 | 1079.2 | 111.8 | 4.50 | 20.95 | 953 | 1580 | 0 |


### Primary ACT-R fit: test

These are measured participant-average means. Error rates use all behavioral trials independently of RT trimming.


| Task | N | Target | Human mean | ACT-R mean | Human median | ACT-R median | Quantile RMSE | Human error % | ACT-R error % | Human RT count | Model RT count | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| conjunction | 3 | absent | 525.6 | 583.7 | 498.0 | 571.5 | 140.4 | 1.92 | 0.00 | 968 | 1993 | 0 |
| conjunction | 3 | present | 504.5 | 432.5 | 468.5 | 366.8 | 104.4 | 2.77 | 4.25 | 1014 | 1875 | 0 |
| conjunction | 6 | absent | 612.4 | 745.8 | 559.5 | 729.0 | 197.7 | 2.18 | 0.00 | 960 | 1998 | 0 |
| conjunction | 6 | present | 542.1 | 443.7 | 504.0 | 362.0 | 120.3 | 2.08 | 5.70 | 986 | 1861 | 0 |
| conjunction | 12 | absent | 811.7 | 1013.1 | 756.0 | 933.5 | 248.1 | 1.00 | 0.00 | 976 | 1999 | 0 |
| conjunction | 12 | present | 598.6 | 485.6 | 555.5 | 404.5 | 134.2 | 3.43 | 9.95 | 941 | 1791 | 0 |
| conjunction | 18 | absent | 1023.8 | 1166.7 | 963.5 | 1103.2 | 190.4 | 0.91 | 0.00 | 999 | 1998 | 0 |
| conjunction | 18 | present | 676.2 | 517.4 | 619.2 | 426.5 | 160.0 | 6.33 | 10.85 | 934 | 1771 | 0 |
| feature | 3 | absent | 463.6 | 345.1 | 437.0 | 313.2 | 118.9 | 2.78 | 0.00 | 1016 | 1939 | 0 |
| feature | 3 | present | 437.9 | 378.4 | 419.0 | 328.2 | 88.3 | 3.76 | 2.00 | 967 | 1911 | 0 |
| feature | 6 | absent | 470.0 | 357.6 | 436.5 | 317.5 | 115.1 | 2.83 | 0.00 | 966 | 1916 | 0 |
| feature | 6 | present | 435.3 | 381.1 | 418.5 | 327.5 | 87.7 | 3.49 | 1.30 | 937 | 1904 | 0 |
| feature | 12 | absent | 452.4 | 362.1 | 426.5 | 319.5 | 97.5 | 2.81 | 0.00 | 965 | 1928 | 0 |
| feature | 12 | present | 445.5 | 380.3 | 423.2 | 328.0 | 91.2 | 2.91 | 2.20 | 969 | 1884 | 0 |
| feature | 18 | absent | 457.1 | 373.5 | 431.8 | 325.0 | 96.2 | 1.44 | 0.00 | 935 | 1937 | 0 |
| feature | 18 | present | 447.6 | 376.2 | 425.8 | 324.8 | 95.2 | 3.50 | 2.70 | 993 | 1885 | 0 |
| spatial | 3 | absent | 694.1 | 874.3 | 646.5 | 880.0 | 198.1 | 3.31 | 0.00 | 1009 | 2000 | 0 |
| spatial | 3 | present | 587.2 | 662.3 | 542.0 | 634.5 | 122.0 | 3.67 | 3.75 | 941 | 1920 | 0 |
| spatial | 6 | absent | 1110.7 | 1212.0 | 1039.5 | 1231.2 | 154.7 | 2.69 | 0.00 | 997 | 2000 | 0 |
| spatial | 6 | present | 790.2 | 796.5 | 713.8 | 759.2 | 83.1 | 2.19 | 8.30 | 1033 | 1832 | 0 |
| spatial | 12 | absent | 1747.0 | 1796.4 | 1695.2 | 1754.2 | 128.5 | 2.76 | 0.00 | 975 | 2000 | 0 |
| spatial | 12 | present | 1062.8 | 1007.1 | 957.2 | 922.0 | 60.5 | 5.36 | 14.30 | 946 | 1711 | 0 |
| spatial | 18 | absent | 2168.7 | 2033.5 | 2027.2 | 1987.8 | 127.7 | 2.92 | 0.00 | 921 | 2000 | 0 |
| spatial | 18 | present | 1265.9 | 1144.0 | 1161.5 | 1079.2 | 104.0 | 10.02 | 20.95 | 828 | 1580 | 0 |


### Implementation agreement

2000 retained trials per cell or more. 0 of 24 search-time means exceed the Bonferroni family threshold; maximum |z| = 1.47. The parity CSV also reports quantile, error, and fixation-count differences.



### Evidence limits

Two test participants per task give limited population precision. Simulation seeds quantify Monte Carlo variation, not human individual differences. Zero false alarms are a structural model limitation. Scanpath agreement requires verified per-fixation coordinates and matched trial/display data; aggregate fixation counts do not establish it. Historical CGS or GS6 simulation output is not a measured human reference.

<!-- END VALIDATION GENERATED -->
