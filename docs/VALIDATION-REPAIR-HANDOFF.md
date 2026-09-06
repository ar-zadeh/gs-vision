# Handoff: repair gs-vision and validate against raw human data

Written September 5, 2026, for the next implementation session. Read this
document and [the project orientation](../HANDOFF.md) before changing code.

The user has downloaded the human search data and wants the recommendations
from the project review completed: fix the timing and gaze problems, align
the Python mirror and Lisp module, improve eye movements and quitting, fit
parameters to actual human trials, and report validation honestly.

This document is an execution specification. Creating it did **not** fix the
module, fit parameters, or rerun the scientific experiments. The download
inventory and parser observations below were checked directly in the local
files. The other findings distinguish inspected code from hypotheses that
still need controlled tests.

## 1. Objective and authority

Deliver a corrected ACT-R vision module and reproducible comparisons with
human **total reaction times**, accuracy, and applicable eye-movement data.
Prefer one shared set of search parameters across the three benchmark tasks.
Report residual failures even if every engineering step is complete.

Use these documents for their respective purposes:

| Document | Role |
|---|---|
| [HANDOFF.md](../HANDOFF.md) | Existing architecture, setup, and review findings |
| [Implementation specification](IMPLEMENTATION-HANDOFF.md) | Original design and acceptance criteria |
| [Module README](../gs-vision/README.md) | Current API and deliberate deviations |
| [Results](RESULTS.md) | Historical measurements, to preserve before regeneration |
| This document | Next implementation steps and validation requirements |

For the work described here, this document supersedes instructions to use
synthetic human targets or assume that the raw Wolfe data are unavailable.
Changes to the scientific mechanisms must be documented as model revisions.
The existence of a suspected bug is not proof of its effect size.

Keep three comparisons separate throughout the work:

1. `reference/gs6_sim.py` versus Wolfe's posted MATLAB: replication of the
   original simulation, which reports search time.
2. `reference/gs_hybrid.py` versus the Lisp module: agreement between two
   implementations of our hybrid architecture at identical parameters.
3. The complete ACT-R model versus human data: stimulus onset to keypress,
   including the model's productions and motor processing.

The ACT-R module combines GS6, Competitive Guided Search, peripheral
perception, memory, and EMMA. Matching Wolfe's simulation is not equivalent
to matching humans, and our hybrid need not produce the MATLAB's exact RTs.

## 2. Local data: verified inventory

The new downloads are in `data/Human-data-paper/`, not `data/human/`.
Preserve their names and bytes. The three `.txt` files are tab-separated.

| File | Task | Rows | Participants | Bytes |
|---|---|---:|---:|---:|
| `RVvGV.txt` | `feature` | 35,948 | 9 | 1,055,246 |
| `RVvRHGV.txt` | `conjunction` | 39,962 | 10 | 1,154,478 |
| `2_vs_5.txt` | `spatial` | 35,867 | 9 | 1,010,270 |
| `milliontrialsdataexcel.sit` | Historical slope archive; inspect separately | Unknown | Unknown | 1,042,991 |

The three task files total **111,777 trials**. All contain set sizes 3, 6,
12, and 18. These are source counts before exclusions, not fitting counts.

The source page is the
[Wolfe laboratory data page](https://search.bwh.harvard.edu/new/data_set_files.html).
It describes the three trial datasets and the separate million-trial slope
collection. Associate the task files with
[Wolfe, Palmer, and Horowitz (2010)](https://pmc.ncbi.nlm.nih.gov/articles/PMC2891283/)
and its companion distribution analysis. Inspect the `.sit` archive's
contents before claiming what it contains; its filename alone is not proof.
Do not combine historical summary slopes with individual RT trials.

SHA-256 fingerprints of the inspected task files:

```text
RVvGV.txt
cd3c9266103a84c8bdb449ff342c93e180b67d14f35638259645cda9b928323f
RVvRHGV.txt
6e06a1ae64ff474fea053dc08f787df721ed6b3b8a9bccb019e6c990e7b537b5
2_vs_5.txt
50190cfa880fc810f386f6306e9ef82b120788ce5ea6b572d276c287350391ef
```

### Column mapping

Build an explicit loader rather than treating these as batch-runner CSVs.
Retain source values alongside normalized fields where interpretation matters.

| Normalized field | Feature source | Conjunction/spatial source |
|---|---|---|
| `subject_id` | `sinit` | `Subject` |
| `condition_source` | `CondReport` | `Condition` |
| `trial_source` | `trialdigit` | `trial#` |
| `set_size` | `setsize` | `setsize` |
| `target_present` | `target present` | `Targ_Pres` |
| `error` | `error` | `Error` |
| `outcome` | `message` | `message` |
| `rt_ms` | `RT` | `RT(ms)` |

Add `task`, `source_file`, `source_row`, `participant_key`, `correct`, and
analysis-inclusion flags. Define `correct` as `error == 0`. Scope participant
keys by task and source unless cross-task identity is established externally.
Numeric participant 1 in two files is not evidence of the same person.

Observed parser traps and validation requirements:

- The feature file has two trailing unnamed columns. Drop them only after
  asserting they contain no data.
- Trial numbers repeat within participants in all three datasets. Never
  deduplicate on participant plus trial number. Use source file plus source
  row as the record identity and preserve row order. Investigate resets
  before interpreting block boundaries or reconstructing trial sequences.
- There are no missing RT values, but each dataset contains zero RTs and
  extreme values. Source RT ranges are 0–47,945 ms for feature, 0–9,218 ms for
  conjunction, and 0–8,407 ms for spatial search.
- All inspected outcomes agree with target presence and error coding:
  `HIT`, `TNEG`, `MISS`, and `FA`. Assert this in the loader.
- Record participant counts, per-cell counts, exclusion counts, condition
  labels, malformed rows, and any duplicate full records. Identical rows
  need investigation; do not silently remove them.

Other locally available resources include `data/human/adam2021/` and
`data/human/wu_wolfe2022/`. The latter contains `RealData.csv` and
`ufov_analyze_Exp1.m`. The MATLAB script loads `Exp1Data`, which was not found
in that directory during this inventory. A companion analysis script does
not establish that its underlying fixation data are available.

The current `.gitignore` covers `data/human/` and `data/model/`, but not
`data/Human-data-paper/`. Do not accidentally commit the user's downloads.
During implementation, add the specific raw-data directory to the ignore
rules and keep provenance plus small artificial test fixtures in version
control. Check redistribution terms before publishing original data.

## 3. Ground rules and baseline

Preserve the original ACT-R architecture and a reproducible pre-change
baseline. Existing untracked files belong to the user.

- Never edit `actr7.x/`. Use the repository's ACT-R 7.31.4, not the older
  installation at `G:\ACT-RModels\actr7.x`.
- Use `.venv/Scripts/python.exe` for every Python command.
- Keep shape identification-only by default. Color, orientation, size, and
  luminance may guide attention. Do not improve fits by leaking target
  identity into the priority map.
- Keep the search loop inside the vision module. Preserve stock behavior for
  models that do not use the new API.
- Load `gs-vision/load-gs-vision.lisp` before any model exists.
- Internal Lisp times are milliseconds; use `:time-in-ms t` where needed.
- Preserve feedback, priming, and prevalence state between trials of one
  simulated participant. Reset those states between participants.
- Change Lisp and the hybrid mirror together. Preserve the original GS6
  replication as a separate reference; do not tune it to repair the hybrid.
- Do not tune ordinary production or motor latencies to hide a vision bug.
  Any independently justified response-stage calibration must be explicit,
  shared where appropriate, and evaluated separately.

Before edits, record the Git revision and working diff, environment versions,
source hashes, complete effective parameters, seeds, protocol, and baseline
artifacts. Preserve the current `RESULTS.md` and saved model runs in a
versioned baseline directory under `data/model/repair_20260905/` without
overwriting the original files. Do not assume the Git revision alone records
uncommitted code or documentation.

Run the existing baseline checks from the repository root:

```powershell
sbcl --non-interactive --load tests/test_module_events.lisp
.venv/Scripts/python.exe -m pytest reference/test_reference.py -q
.venv/Scripts/python.exe -m pytest tests/test_backcompat.py -v
```

Historical counts are 95 Lisp assertions, 18 reference tests, and 15 backward
compatibility cases. Report current results; do not assume those counts or
passes are still current. Add focused regression tests for confirmed defects.

## 4. Stage A: import human data and freeze the evaluation protocol

Implement a reusable importer, suggested path `harness/human_data.py`, plus
focused tests. This file and its CLI do not exist yet. Make all analysis and
fitting code consume the same validated dataset and summary definitions.

### Cleaning and aggregation

Produce a normalized trial table, a source manifest, and an exclusion audit.
Do not modify originals or remove trials from the normalized archival table.
Keep accuracy and RT eligibility separate.

Verify the published cleaning convention. The laboratory page describes
RT truncation below 200 ms or above 4,000 ms for feature/conjunction, and
below 200 ms or above 8,000 ms for spatial search. Use these as the initial
documented RT-analysis convention, with boundary handling stated explicitly.
Report an untrimmed positive-RT sensitivity analysis as well.

Compute correct-trial RT summaries on the RT-eligible records. Define error
denominators from valid behavioral records independently of RT-tail trimming;
show how exclusions affect them. Preserve the source accuracy even when RT
is invalid. Do not lower error rates by discarding mistakes or timeouts.

Calculate summaries per participant, task, set size, and target presence:
counts, mean, median, standard deviation, quantiles .1/.3/.5/.7/.9, misses,
and false alarms. Aggregate participants with equal weight for the primary
group comparison. Average participant quantiles rather than silently pooling
all RTs and calling the result an average participant. Label pooled results
as a separate descriptive view. Bootstrap participants for uncertainty.

Fit human slopes and intercepts from these measured cell summaries. Replace
the provisional `TIER1_SLOPES` and `TIER1_INTERCEPTS` as the source of current
human comparisons. Preserve old values only in clearly labeled historical
results. Earlier chat tables computed as `intercept + slope * N` are derived
estimates from those provisional values, not measured raw-data means.

### Prevent fitting to the test participants

Before comparing candidates, save a deterministic participant split and seed.
Use train/validation/test splits within each task. A workable initial split
is 5/2/2 for each nine-participant task and 6/2/2 for conjunction. Assign by
seeded shuffle of participant keys, independently of their RTs or errors.

Use training participants for fitting and validation participants for model
selection. Freeze mechanisms, parameters, preprocessing, and metrics before
the final test evaluation. Do not choose a seed, parameter bound, or model
revision using the test results. With only two test participants per task,
report uncertainty and avoid strong population claims. Cross-validation
within the development participants can assess fit stability.

Basic source-integrity checks may inspect all records. Do not repeatedly
inspect test performance during model development. If a later revision uses
test results, label that evaluation exploratory and document the loss of an
untouched test set.

**Stage A is complete when:** all three files import reproducibly, source
counts reconcile, column and outcome checks pass, repeated trial numbers are
preserved, exclusions are audited, and the split manifest is saved.

## 5. Stage B: make parameters, timing, and trial state trustworthy

Complete this stage before interpreting new fits. Inspection found important
gaps in the current harness beyond the earlier module review.

### Parameter transport

`harness/fit.py` writes the differential-evolution result under `_de.params`.
`harness/run_batch.py:load_params` reads only `delta`, so such a result can
silently run with defaults. `harness/analyze.py` also reads only `delta` for
mirror comparison. Furthermore, `params_delta` includes only keys from
`PHASE1_SPACE`, omitting several parameters fitted by differential evolution.

Create one parameter-loading and translation contract used by fitting,
batch execution, mirror comparison, and reporting. Serialize complete
effective settings, schema/version information, and units. Validate the
selected entry; reject missing keys and unsupported settings rather than
silently falling back. Explicitly classify Python-only response parameters.

Read parameters back from ACT-R after application, check acceptance, and hash
the effective configuration rather than just the requested delta. Ensure
initial adaptive state uses any newly applied initialization parameters.
Add a round-trip test using nondefault DE parameters, including bottom-up
weight, identification settings, and quitting settings. Confirm Lisp and
Python receive the same modeled values. New saccade parameters must travel
through this same path.

### Actual RT timestamps

The current key callback records the key but not its time. The batch runner
computes RT after `actr.run` returns. Verify whether the current model stops
exactly at output-key; do not assume event-loop return equals response time.
Record simulated timestamps for stimulus onset, search request, item
identification, buffer availability/failure, and the first valid keypress.

Define total RT as stimulus onset to keypress. Define module search time by
its actual request and result boundaries. Feedback after the response is
outside that trial's RT. Trace the actual production path: do not blindly
add three times 50 ms, since the feedback production occurs after response.
The previously reported 310–350 ms is a baseline observation to verify.
Measure ACT-R simulated time, never Python execution time or network latency.

Keep timeouts in the trial table and report them separately. The current
`analyze.load_trials` drops rows without `rt_ms`; preserve an unfiltered view
for trial counts and failures so timeouts cannot disappear from evaluation.

### Trial protocol and persistent state

The Python `run_cells` starts a separate observer per task and drops the first
25% of generated trials by default. Lisp `run_batch` mixes requested tasks
within one observer and retains all trials. Match task blocks, practice,
feedback timing, retained trials, and state boundaries on both sides.

For the main human benchmark, run tasks as separate participant sessions,
even with shared parameters. Shared parameters do not mean shared learned
state across unrelated task datasets. Match published practice and feedback
as closely as available records allow; label synthetic practice explicitly.
Never discard a quarter of human experimental trials just because the mirror
does so. Preserve enough metadata to reproduce time-dependent priming decay.

Where possible, save common generated display sequences for comparison.
The RT files do not contain original item coordinates: reproducing their
display distribution is not replaying their exact displays. Different Lisp
and NumPy random streams need not produce identical individual trials.

**Stage B is complete when:** parameter round trips pass, event timestamps
define RT unambiguously, timeouts remain visible, and both implementations
follow the same participant and trial protocol.

## 6. Stage C: repair fixation records and trial-start gaze

Inspect `gs-eye.lisp` (`gs-centre-eye`, `gs-saccade-land`),
`gs-diffuser.lisp` (`gs-start-search`, `gs-finish-hit`, `gs-quit-search`,
`gs-clear-search`), and the matching hybrid event loop.

The current landing and hit paths log the new coordinates with the preceding
fixation's time interval. Log the position actually occupied during that
interval. Include the initial central fixation and close the final fixation
on hit, quit, reset, timeout, or cancellation without duplicate rows.

Define fixation onset and offset carefully. Preparation while the eye remains
stationary can belong to a fixation; movement execution is not fixation
duration. The existing saccade event combines preparation and execution.
Separate those events if needed, and document any remaining approximation.
Define whether the log ends at visual result or keypress; compare human and
model counts over matching observation windows. Adding the initial fixation
changes count conventions, so recompute counts and amplitudes from the new
logs rather than assuming old metrics remain valid.

Set central gaze before each timed benchmark display, reflecting its fixation
cross. Prefer explicit experiment setup over globally forcing every generic
`gs-search` request to recenter; other tasks may intentionally continue from
the current gaze. Preserve adaptive state. Match the saccade-preparation
history in Lisp and Python, including any modeled return-to-center movement.

Test a known sequence of two gaze positions and a hit/quit: correct
coordinates, nonnegative durations, ordered times, no duplicated closure,
and no missing initial/final fixation. Run consecutive trials ending away
from center; verify each next benchmark trial starts centrally while its
learned quitting and priming state survive.

Rerun Lisp/mirror comparisons at unchanged baseline parameters before fitting.
Record how much each residual changes. Verify that diagnostics do not alter
the search decisions except for the intended gaze correction.

## 7. Stage D: resolve identification and first-selection timing

The current `gs-finish-hit` adds EMMA encoding after the Wald identification
event and immediately relocates gaze for a peripheral hit. This is a strong
candidate for duplicated recognition cost, but removing a fixed 100–200 ms
without tracing the required work is not a valid repair.

Establish one recognition contract: what evidence is available at selection,
what the Wald event completes, and what is still required before an object
can reach the visual buffer. If all needed features have been identified,
avoid charging another full recognition process. If features are unavailable,
preserve the required foveation and pending-item path. Retain real eye-movement
costs when a movement is required. Do not teleport gaze to make buffer
delivery easier.

Preserve ACT-R chunk construction, attended-location bookkeeping, buffer
state transitions, and production wake-up behavior. Inspect `encoding-complete`
in vendored ACT-R read-only before changing its use. Cover a centrally
identified target, a peripheral identifiable target, a target requiring
foveation, target disappearance, and cancellation/reset before delivery.
Ensure no stale completion event contaminates the next trial.

Audit the first-selection wait in `gs-schedule-select`. Decide whether the
first interval represents a required selection cost or an unnecessary idle
delay. Test and document the selected convention in both implementations;
retain it if evidence supports it. Do not remove it solely to improve RT.

Before refitting, show event-level before/after timing and changes in total
RT, module time, slopes, intercepts, and errors at fixed parameters. Do not
promise the whole human intercept gap will disappear.

## 8. Stage E: revise saccades and stabilize quitting

These changes include scientific hypotheses, so use controlled comparisons
and keep a record of the rule selected and alternatives evaluated.

### Eye-movement policy

In `gs-select`, a display-wide noisy winner currently determines whether the
module requests a saccade instead of selecting a nearby item. Test whether
this causes unnecessary long jumps and repeated idle selection cycles.

Evaluate the earlier proposed repair: use guidance without sampled noise,
plus an explicit margin, for the distant-versus-near decision; use a separate
distance preference for choosing saccade destinations; and allow useful
nearby selection during saccade preparation when capacity and acuity permit.
Specify processing during movement execution separately. Already scheduled
identification events must retain valid completion/cancellation semantics.

Keep pending-foveation items from starving. Preserve efficient feature search
when the strongly guided target is peripheral. Test homogeneous displays,
near/far targets, full diffuser capacity, concurrent hit/landing events,
and no available candidates. Document added parameters, units, and bounds.

Measure saccade amplitude, fixation duration, fixation count, items processed
per fixation, errors, and total RT together. Smaller saccades alone do not
establish a better search model.

### Competitive and adaptive quitting

The existing fit permits `choice_beta` up to 20, with 16 used for spatial
search. Diagnose whether a few noise winners dominate the quit denominator.
Compare bounded beta with a separately defined quit-weight calculation using
noise-free guidance. Preserve a meaningful quit-weight scale and the
contribution of unresolved items, including items already being identified.
Record the selected rule as a deviation if it changes the original design.

Test adaptive-only, competitive-only, and combined stopping. Check that a
search cannot quit merely because candidate items are in flight. Examine
threshold trajectories, error rates, and quit reasons across seeds.

Reevaluate the proposed defaults `:gs-w-bu = 3.0` and `:gs-qt-step = 0.005`
against the corrected implementation. They are evidence-backed candidates
from the old runs, not guaranteed optima after repairs. Promote them if the
new evaluation supports them; otherwise document the measured replacement.
Update Lisp defaults, Python defaults, tests, parameter bounds, and docs
together. The current DE bottom-up bound stops at 2.0 and cannot even test
the proposed 3.0 value.

Keep the GS6 MATLAB prevalence finding visible: its documented simulation
does not reproduce the human low-prevalence pattern. A smaller controller
step does not guarantee that pattern. If the hybrid still fails, diagnose
whether a relative threshold update or another justified mechanism is needed,
evaluate it as a separate revision, and report any remaining failure.

## 9. Stage F: fit actual human RT distributions

Only start final fitting after the corrected mirror and Lisp agree under
matched conditions. Use the mirror to search efficiently and ACT-R for final
validation. Do not treat mirror fitting success as ACT-R validation.

`quantile_cost` currently defaults to `synthetic_target`, whose quantiles are
random draws around provisional summary slopes/intercepts and whose error
targets are fixed placeholders. Replace this default in the real-data path.
Require a validated human summary and split; fail clearly if it is missing.
Any synthetic smoke-test mode must be explicit and labeled synthetic.
Changing two slope dictionaries is insufficient.

Fit equal-weight task/cell targets using correct-trial quantiles and separate
miss/false-alarm penalties. State units and weighting. The existing objective
uses quantile RMSE in milliseconds plus 10 ms per percentage point of error
difference per cell (`10 * 100 * abs(model_rate - human_rate)`). Preserve this
as a transparent starting objective or justify its revision using development
data. Penalize empty correct-response cells and timeouts explicitly.

Use one shared search parameter set as the primary model. Allow target
templates and experimentally specified stimulus properties to differ by task.
Report per-task fits as a secondary comparison, listing additional free
parameters and their held-out benefit. Do not silently call separate task
fits a single universal model.

Review fitting bounds after the mechanism changes. Selection interval,
identification parameters, capacity, memory, guidance weights, acuity,
eye-movement policy, noise, and quit settings affect overlapping outcomes.
Keep the search space manageable and justified. Start from defaults and
historical fits, use multiple optimizer seeds, and examine parameter
sensitivity and boundary solutions. Avoid fitting redundant overall priority
scale, temperature, and noise scales without identifiability checks.

The mirror's `t_nondecision` and `motor_error` are not vision parameters.
Calibrate the response approximation from ACT-R event timing on development
runs or model the measured response distribution explicitly. Do not give the
mirror a favorable response offset or lapse rate absent from the final ACT-R
model. Diagnose any remaining response-stage discrepancy separately.

Use cheap simulation samples for exploratory search, then larger independent
samples for candidate validation. Save optimizer settings, full parameter
vectors, seeds, objective components, source hashes, and split identifiers.
Use fresh simulation seeds for final testing. Do not choose final results
because one seed happens to match humans.

## 10. Stage G: final validation and reproducible reports

Run defaults, corrected-but-unfitted settings, the final shared fit, and the
secondary per-task fits under clearly named configurations. Show successive
mechanism changes at fixed parameters as well as final fitting gains.

### Main human comparison

For all 24 task/set-size/presence cells, report actual human and ACT-R mean
RT, median RT, five RT quantiles, uncertainty, retained counts, misses, false
alarms, and timeouts. Include slopes/intercepts, RT RMSE, quantile misfit,
and ex-Gaussian summaries where estimable. Plot raw-data mean RT against set
size and human/model quantile comparisons, with train and test labeled.

Use these original project targets without retroactively relaxing them:

| Metric | Target and reporting requirement |
|---|---|
| Six slopes | Each within 5 ms/item of the measured human reference |
| RT distributions | Mean cell quantile RMSE at most 40 ms; show every cell |
| Miss rates | Within 3 percentage points; report false alarms separately |
| Absolute RT | Show measured means, medians, and intercept errors; no hidden offset |
| Singleton capture | Correct sign and within 50% of matched human magnitude |
| Priming | Original 20–60 ms target, with protocol match stated |
| Low prevalence | Original target: at least 10-point miss increase and faster absent RT |

The last two are project design targets, not estimates from the new 50%
prevalence, fixed-template files. Their empirical interpretation requires a
matching experiment. Do not impose GS6's slope ratio of approximately three
as the exact human target for every task. Feature slopes near zero make
ratios unstable; mark those ratios uninformative.

### Lisp/mirror agreement

For final confirmation, target at least 2,000 retained trials per cell across
multiple independent seeds in each implementation. Count retained trials
after practice/burn-in; `run_cells` currently discards part of its requested
sample. Compare search-time means, quantiles, errors, and gaze behavior at
matched parameters and protocols. Report paired cell differences and Monte
Carlo uncertainty. Use a predeclared aggregate or multiplicity-aware check;
one nominal two-standard-error exceedance among many cells is not sufficient
proof of a port bug. Investigate systematic residuals before declaring parity.

### Capture, priming, prevalence, and eye movements

Reevaluate singleton capture against Adam et al. with stimulus and task
differences disclosed. The existing test substitutes an orientation target
for their shape target; it is not an exact experiment replication. Reserve
independent data or clearly label the result as calibration if it selects
the bottom-up weight.

For priming, implement a condition in which recent target history can help:
the current benchmark supplies the correct color template on every trial.
Specify how target identity can be recognized without revealing the upcoming
guiding color before selection. Run both the original known-template control
and a justified priming protocol. Include a history-weight-zero ablation,
repeat/switch counts, seeds, and confidence intervals.

For prevalence, compare at least 10% and 50%, optionally 90%, with matched
practice and enough rare-target trials. Plot adaptive state and errors over
time. Distinguish missing empirical evidence from a measured model failure.

Resolve the provenance of the alleged Wu and Wolfe eye benchmark before
refitting to it. Existing documents disagree on participant counts and even
the type of experiment. Verify paper, OSF component, task, display dimensions,
item sizes, target frequency, accuracy coding, RT units, and fixation window.
Do not infer any of these from the folder name. The current display generator
expands the field to 40.5 degrees at set size 80; verify whether that matches
the human experiment before treating its fixation-count mismatch as settled.

Compare fixation counts, durations, saccade amplitudes, and refixations under
the verified geometry. Retain the original 180–275 ms duration and 3–7 degree
amplitude targets as project checks, with task applicability stated. The
original count criterion is within one fixation per trial for matched data.
Compute scanpath metrics only if compatible per-fixation coordinates and
trial/display information are available; include human split-half baselines.
If unavailable, document the missing fields and report only supported metrics.
Do not invent coordinates from aggregate fixation counts.

### Reporting and completion

Extend `harness/report.py` to accept an explicit run manifest, normalized
human summaries, and destination. It currently reads hardcoded old filenames,
imports provisional targets, prints tables, and catches section exceptions.
Running it alone does not rewrite `docs/RESULTS.md`. Implement an explicit,
tested regeneration path that preserves the narrative and replaces only the
generated section. Required missing inputs must fail visibly; optional
unavailable metrics must be labeled, not silently omitted.

Record every reported model value's run identifier and every human value's
source, preprocessing, and split. Generate standalone plots and tables. Add
human variability or split-half agreement where computable. Verify published
competitor numbers against their sources before quoting them; CGS parameters
currently carry an unverified-transcription warning. Neither CGS output nor
Wolfe MATLAB output can be relabeled as measured human data.

Update `HANDOFF.md`, `docs/RESULTS.md`, `gs-vision/README.md`,
`gs-vision/CHANGELOG.md`, `docs/CODE-WALKTHROUGH.md`, and the hybrid docstring
to reflect the final behavior. Mark the research report's old architecture
header as superseded. Reconcile contradictory intercept summaries from
regenerated values, not by choosing one old range. Include the GS6 prevalence
exception and separate confirmed fixes from unresolved hypotheses.

Run the baseline test suites again after the changes, together with focused
new tests for import, parameter transport, timing, state persistence,
fixations, and report generation. Save exact commands and resulting artifacts
in a run record. New CLIs and flags must have working `--help` examples;
do not copy hypothetical commands into the final report as completed runs.

## 11. Deliverables and stopping condition

The implementation session must leave a reviewable result covering all stages.
Use this checklist to distinguish completed work from hoped-for science.

- [x] Original data and pre-change results preserved with provenance.
- [x] All 111,777 source trials accounted for by the importer and audit.
- [x] Participant splits, preprocessing, and scoring frozen and saved.
- [x] Complete fitted parameters round-trip into Lisp and the mirror.
- [x] RT is tied to actual simulated stimulus and response events.
- [x] Fixation logs and benchmark gaze starts corrected and tested.
- [x] Identification timing resolved with event-level evidence.
- [x] First-selection timing evaluated and its convention documented.
- [x] Saccade and quit-policy changes evaluated with controlled comparisons.
- [x] Bottom-up and threshold-step defaults reassessed and synchronized.
- [x] Synthetic human targets removed from the real-data fitting path.
- [x] Shared fit completed; per-task alternatives separately evaluated.
- [x] Final ACT-R runs evaluated on untouched test participants' summaries.
- [x] Lisp/mirror agreement quantified under matched protocols.
- [x] Capture, priming, and prevalence experiments run and reported.
- [x] Eye-data provenance/geometry resolved as far as evidence permits.
- [x] Supported eye metrics computed; unavailable scanpath evidence identified.
- [x] Reports, plots, docs, commands, and regression checks reproducible.

Completion does not require claiming that every scientific target passed.
It requires implementing and testing the repairs, carrying out fitting and
evaluation, and reporting every remaining misfit or concrete data limitation.
Do not stop after fixing only gaze, or after obtaining a good Python fit.
If a dataset needed for a secondary metric is unavailable, finish the other
stages and record the exact missing evidence. Natural-image and GUI search
Tiers 3 and 4 remain separate future projects; an audit of extra downloads
does not authorize building those systems.


## Implementation record

Implemented and evaluated in the September 5 repair session. See
[current results](RESULTS.md) and the
[run record](validation-20260905/run-record.json). Checked deliverables mean
the work was performed, not that every scientific target passed. Quantile,
slope, error, saccade, priming, and prevalence failures remain explicit.

The eye audit recovered the missing MATLAB fixation table from the nested
OSF Results folder. Supported human metrics and split-half scanpath
consistency are computed. Model-to-human scanpath comparison remains limited
by the unmatched continuous-foraging task and observation window; no
coordinates were invented from aggregate counts. The separate historical
StuffIt archive remains undecoded and was not used as raw RT data.
