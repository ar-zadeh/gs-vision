# Project handoff: gs-vision

The September 5, 2026 validation repair is implemented. Read
[the current results](docs/RESULTS.md) for measured failures and
[the repair specification](docs/VALIDATION-REPAIR-HANDOFF.md) for the original
acceptance criteria. Engineering completion does not establish a human fit.

## Current state

The module remains a subclass of ACT-R 7.31.4 vision. Search runs inside the
module. Shape remains identification-only by default. The unchanged
`reference/gs6_sim.py` is the posted-MATLAB replication; `gs_hybrid.py` mirrors
our revised hybrid; total human RT is compared with the complete ACT-R model.

The importer accounts for all 111,777 trials. Participant splits are frozen
at 5/2/2 for feature and spatial, and 6/2/2 for conjunction. Models were
selected using training and validation participants before test evaluation.
The final shared fit uses two fresh simulation seeds, with 2,000 retained
trials per cell in Lisp and Python. It has no Bonferroni-significant search
mean discrepancy across 24 cells, but it misses several human targets.

Test mean RT RMSE is 108.0 ms; mean cell quantile RMSE is 127.7 ms against
the 40 ms target. Two of six slopes pass; the largest miss-rate discrepancy
is 10.9 percentage points. The final ACT-R runs have no timeouts. Saccade
amplitude, priming, and low-prevalence behavior still need scientific work.
Test results have now been inspected: any future model selection using them
must be labeled exploratory or use new held-out data.

A post-freeze refit later on September 5 is reported in
[RESULTS-REFIT-20260905.md](docs/RESULTS-REFIT-20260905.md). It adds six
module parameters (`:gs-id-sigma`, `:gs-id-error`, `:gs-onset-latency`,
`:gs-adaptive-quit-delta`, `:gs-explore-proximity`, `:gs-saccade-trigger`),
all defaulting to the frozen behaviour, and a 13-parameter parallel
differential-evolution fit driven by `harness/refit.py`. On the test
participants the better candidate lowers quantile RMSE from 127.7 to 100.1 ms
and passes 4 of 6 slopes; on the validation participants it is worse than the
frozen fit, because the two-participant splits differ by 20 to 30 percent in
speed. Its artifacts live in `data/model/refit_20260905/` and
`docs/validation-refit-20260905/`; the frozen run directory is untouched.

## Confirmed repairs

The parameter contract in `harness/parameters.py` transports complete
configurations, rounds millisecond-valued settings before simulation, checks
ACT-R readback, and hashes accepted values. Missing entries and unsupported
settings raise errors. Initialization reaches adaptive state before learning.

The runner timestamps stimulus, search request/result, identification, and
keypress. Event-loop return is later than keypress and is not RT. The mirror
uses the measured keyboard response stage: 160 ms on repeats, 260 ms on
switches, and 310 ms on the first response. Feedback occurs after keypress;
its production is outside RT. No production or motor latency was tuned.

Fixations include the starting gaze and final closure, use occupied
coordinates, and exclude movement execution. Benchmark setup centers gaze
without resetting learning. Generic searches can retain the current gaze.
Wald identification completes recognition once required features are
available; ACT-R constructs the object at that event without another full
encoding delay. Pending delivery is owned and cancellable.

Saccade triggering uses noise-free guidance with a margin. Destination choice
has a separate distance penalty. Covert work can continue during preparation;
new selections stop during movement. Strong peripheral candidates prevent
weak distractor work from prematurely exhausting the adaptive threshold.
Adaptive stopping drains outstanding identifications before quitting. The
competitive denominator includes unresolved items, uses noise-free guidance,
and caps its own beta at four. These are explicit model revisions.

The Lisp Wald sampler now uses a true normal variate. The mirror uses ACT-R's
45-degree saccade-direction equivalence and logistic landing noise. The
first selection interval remains a modeled selection cost.

## Files and artifacts

The active validation entry points are listed here.

| File | Purpose |
|---|---|
| `harness/human_data.py` | Validated archival import, exclusions, splits, participant summaries |
| `harness/parameters.py` | Parameter schema, units, normalization, transport, readback |
| `harness/protocol.py` | Shared balanced displays and synthetic practice blocks |
| `harness/fit.py` | Real-data DE objective; synthetic mode requires an explicit flag |
| `harness/repair.py` | Development candidates, ablations, frozen final runs |
| `harness/refit.py`, `harness/refit_report.py` | Post-freeze refit: fit, select, ACT-R final, evaluate; comparison tables |
| `harness/evaluate.py` | Run validation, participant uncertainty, parity, plots |
| `harness/report.py` | Explicit manifest-to-report regeneration |
| `harness/experiments.py`, `harness/study_batch.py` | Mirror and ACT-R secondary manipulations |
| `harness/eye_audit.py`, `harness/export_eye_data.m` | Wu/Wolfe fixation audit and MATLAB export |
| `harness/sensitivity.py` | Development-only local parameter diagnostics |
| `harness/archive_validation.py` | Secondary summaries, review artifacts, and reproducibility record |

Reviewable summaries, configurations, and plots live in
`docs/validation-20260905/`. Full runs, source hashes, commands, logs, and the
pre-change snapshot live in `data/model/repair_20260905/`. Its `baseline/`
contains the original results, source archive, working-tree status, revision, and
environment. Original downloads remain unchanged and ignored by Git.

The eye audit recovered `Exp1Data.mat` from the nested OSF Results folder.
It contains continuous T-among-L foraging fixations. The author's analysis
selects 18 of the 19 participants in the table. Fixation identity requires
subject, trial, target episode, and fixation index. The separate `RealData.csv`
is a 42/80-item keypress search table. Neither dataset is the 2-versus-5 task.
See the results for supported eye metrics and window/geometry limitations.

## Reproduction

Run commands from this repository using its venv. The existing frozen run
directory can regenerate reports; use a separate directory for new model
development. Read `docs/validation-20260905/run-record.json` for exact commands
and the distinction between exploratory, development, and final runs.

The following commands regenerate reports and run checks on the frozen run.
Development commands and their seeds are recorded in the run record.

```powershell
.venv/Scripts/python.exe harness/report.py --manifest data/model/repair_20260905/run_manifest.json --final-test
.venv/Scripts/python.exe harness/archive_validation.py
sbcl --non-interactive --load tests/test_module_events.lisp
.venv/Scripts/python.exe -m pytest reference/test_reference.py tests/test_validation.py -q
.venv/Scripts/python.exe -m pytest tests/test_backcompat.py -v
```

Final checks pass: 115 Lisp assertions and 50 Python tests. The runner uses
a private dispatcher handshake and one tutorial client module per session;
it does not attach through the shared home port file. Nested sessions retain
their own model settings. No vendored ACT-R file is modified.

## Constraints for future work

Never edit `actr7.x/` or load the older external ACT-R installation. Load
`gs-vision/load-gs-vision.lisp` before any model exists. Internal Lisp time is
milliseconds; scheduling requires `:time-in-ms t` where applicable. Preserve
learning within a participant and reset it between tasks and participants.
Do not hide misfits in production/motor timing or give shape guiding access.
Natural-image and GUI search remain separate future projects.

## gs6-vision (September 5, evening)

A second module folder, `gs6-vision/`, replaces the Competitive Guided Search
engine with Wolfe's posted Guided Search 6 simulation: a two-bound diffuser
stepped every 10 ms, an adaptive start point, the quit-signal diffuser with the
MATLAB's feedback rules, diffuser-only memory, and Guided Search 2's dual
orientation channels and best-channel top-down rule. Its mirror is
`reference/gs6_hybrid.py`; `harness/parameters.py` recognises both parameter
schemas; `harness/run_batch.py --module gs6` drives it; `harness/gs6_fit.py`
ran fit, selection, ACT-R final runs and evaluation into
`data/model/gs6_20260905/` and `docs/validation-gs6-20260905/`. Results are in
[RESULTS-GS6-20260905.md](docs/RESULTS-GS6-20260905.md): the engine as posted
does not fit these data (test quantile RMSE 313 ms with the spatial layer
fitted); with its rates fitted it matches the frozen gs-vision fit (122.5
against 127.7 ms) but not the refit (100.1), and its quit rule produces excess
misses at small set sizes (18 points) and inverts the prevalence effect on
misses. Lisp and mirror agree in all 24 cells with the controller frozen. The
frozen and refit run directories are untouched; everything is exploratory.

## Model comparison (September 6)

`reference/baselines.py` implements ten trial-level comparison models with
one interface (serial self-terminating search, a parallel race, Competitive
Guided Search with shared or per-task parameters, the Hulleman and Olivers
fixation model, Wolfe's posted GS6 engine with and without its rates fitted,
and three timing mirrors of ACT-R's stock vision module).
`harness/compare_models.py` fits them on the training participants with the
gs-vision objective, runs 2 x 1,000-trial finals, scores every model and every
existing ACT-R run with one formula, and writes
`docs/validation-comparison-20260906/`. Results are in
[RESULTS-COMPARISON-20260906.md](docs/RESULTS-COMPARISON-20260906.md): on the
test participants the gs-vision refit (100 ms quantile RMSE) is the best model
with eyes or an ACT-R run and about 20 ms behind the best trial-level models
(serial 80, CGS 83), a gap inside the 93 ms floor set by the human split
differences; its clear deficit against them is the miss rate (largest error
11 points against 3 to 7). `tests/test_baselines.py` covers the mirrors.
