---
title: "Bringing Guided Search into ACT-R: A tutorial on the gs-vision module and its validation against benchmark visual search data"
author:
  - "Bruce Farnod^1^ and Frank E. Ritter^2^"
  - "^1^ [Affiliation, department, institution, city, country]"
  - "^2^ College of Information Sciences and Technology, The Pennsylvania State University, University Park, PA, USA"
date: "Manuscript prepared for the Behavior Research Methods Tutorial Collection. Corresponding author: Frank E. Ritter, College of Information Sciences and Technology, The Pennsylvania State University, University Park, PA 16802, USA. Email: Frank.ritter@psu.edu. The manuscript was last edited on September 6, 2026."
---

# Abstract

ACT-R's vision module has been the architecture's account of visual perception for more than two decades, and its mechanisms for locating and attending objects have not changed in that time. It has no acuity, no salience, no guidance, no eye position, and no way to stop a search that has found nothing; a production loop that searches with it runs three to ten times slower per item than a human observer. This tutorial presents gs-vision, a replacement vision module for ACT-R 7.31 that implements Guided Search 6 (priority map, capacity-limited asynchronous identification, memory for rejected items, adaptive quitting), the quantitative engine of Competitive Guided Search, per-feature acuity and iconic memory in the tradition of PAAV and EPIC, and EMMA eye movements, as a subclass that leaves every existing model running unchanged. We explain the theory, walk through the buffer interface with a complete search model, and show how to drive, log, and fit the module from Python. We then validate it on the reaction-time distributions and error rates of the three Wolfe, Palmer, and Horowitz (2010) benchmark tasks with held-out participants, and compare it with the stock module, PAAV, a Guided Search 6 variant, and six trial-level models fitted with the same objective. gs-vision is the most accurate model of visual search that runs in ACT-R and has eyes, and it is within participant noise of the best trial-level models. Its miss rates and saccade amplitudes remain wrong in documented ways. All code and run records are available.

*Keywords:* ACT-R, visual search, Guided Search, cognitive architecture, eye movements, model validation, reaction time distributions

# Introduction

Cognitive architectures let a modeler predict the time course of a whole task, perception included, from a small set of fixed mechanisms (Anderson, 2007; Anderson et al., 2004). ACT-R is the most widely used such architecture in psychology and human–computer interaction, and its perceptual-motor layer has been an important reason for that reach: a model can read a screen, move its eyes, and press keys with latencies that were calibrated against human data (Byrne, 2001; Salvucci, 2001). Yet the part of that layer that decides *where the model looks next* has changed little since ACT-R/PM. A `visual-location` request filters the model's list of objects by symbolic slot values, returns one match at no cost, and breaks ties at random. A `move-attention` request then encodes the object in a fixed 85 ms. There is no eccentricity, no acuity, no salience, no guidance by target features, no cost for distance, and no principled way to stop a search that finds nothing. The module can be *used* to search, by writing a production loop that finds, attends, and tests one object at a time, but each iteration costs at least 135 ms and typically 185 to 235 ms (Fleetwood & Byrne, 2006), where human observers inspect items in a conjunction search at 10 to 50 ms per item and finish a feature search without inspecting anything.

Visual search research went a different way in the same period. Guided Search (Wolfe, 1994, 2021) became the dominant framework, and its sixth version specifies a priority map fed by five sources of guidance, a selection rate of about one item every 50 ms into a capacity-limited "carwash" of about five items being identified at once, memory for four to six rejected items, three functional visual fields that separate what can be resolved, what can be attended, and where the eyes go, and an adaptive quitting rule. Competitive Guided Search (CGS; Moran et al., 2013) gave that architecture a quantitative engine with eight parameters that reproduces the full reaction-time (RT) distributions and error rates of the standard benchmark (Wolfe et al., 2010) better than a parallel race (Moran et al., 2016). Fixation-based accounts (Hulleman & Olivers, 2017) and active-vision architectures (Kieras & Meyer, 1997; Kieras & Hornof, 2014) showed how acuity and eye movements, not only covert attention, shape search slopes. None of this exists inside ACT-R 7. The one serious attempt to import it, the Pre-Attentive And Attentive Vision module (PAAV; Nyamsuren & Taatgen, 2013), was written for ACT-R 6, fixes one item per fixation, has no adaptive quitting, and was never evaluated against RT distributions or error rates. Later proposals (Byrne, 2006; Wiese et al., 2019) added salience to location requests but were not validated on search data.

The gap matters beyond visual search. Any ACT-R model that reads a display, whether it is a menu, a cockpit, an air-traffic scope, or a web page, needs a search process, and today's modelers either write a production loop whose timing is known to be wrong or approximate the search with a single `:nearest` request. A vision module that searched the way people do would improve the perceptual predictions of every such model without changing anything else in the architecture.

This tutorial presents gs-vision, a module that fills that gap for ACT-R 7.31, and follows the format of earlier ACT-R primers in this journal (Dimov et al., 2020). It has four aims. First, to explain the theory the module implements and the design decisions that were needed to put a Guided Search architecture inside ACT-R's event-driven module system (the Module section). Second, to show, step by step, how a modeler uses it: loading, extended visicon features, the three buffer requests, feedback, diagnostics, and a complete model of a search experiment driven from Python (the Tutorial section). Third, to report a validation that is unusual for an architecture module: RT quantiles and error rates of the three Wolfe et al. (2010) benchmark tasks, with participants held out before fitting, next to the stock ACT-R module, PAAV, a variant that uses Wolfe's own posted Guided Search 6 engine, and six trial-level models from the literature fitted with the same objective (the Validation and Comparison sections). Fourth, to be candid about what the module does not yet get right, because a module that is going to be used deserves a documented list of its failures (the Discussion). Everything reported was run from scripts in the accompanying repository, and every table in the paper can be regenerated from its run records.

# What ACT-R's vision module does today

The stock vision module (ACT-R 7.31.4, `vision.lisp` version 11.1) maintains a *visicon*, a list of feature chunks that the experiment adds with `add-visicon-features`. A `visual-location` request specifies slot constraints such as `color red` or `:attended new`, optional ordinal constraints such as `screen-x lowest`, and a `:nearest` option; the module returns one matching chunk, breaking ties by recency of onset and then at random, in 0 ms. A `visual` request with `move-attention` shifts attention to that location and, after `:visual-attention-latency` (85 ms), places an object chunk in the `visual` buffer. Four *finsts* mark recently attended objects for three seconds, so that `:attended nil` can exclude them. Those are the search primitives, and Table 1 summarizes the consequences for a model that uses them in a loop of three productions (find, attend, test).

Table 1. *Per-item timing of the stock vision module in a find, attend, test production loop*

| Component | Latency | Source |
|---|---|---|
| Production cycle | 50 ms each, three per item | Default `:dat` |
| `visual-location` request | 0 ms | Vision module |
| Attention shift and encoding | 85 ms | `:visual-attention-latency` |
| Total per item | 185–235 ms | Sum; 135 ms with `:auto-attend` |
| Human, conjunction search | 10–35 ms per item | Wolfe et al. (2010) |
| Human, spatial-configuration search | 45–100 ms per item | Wolfe et al. (2010) |

Three things follow. The loop is three to ten times too slow per item for guided or spatial search, and cannot produce a feature search that finishes without inspecting anything, unless the modeler adds a request such as `color red` that succeeds in 0 ms, which produces absent responses in about 210 ms, half the human value. The choice of the next item is random with respect to the target's features, so the module cannot express guidance. And there is no quitting rule: an absent trial ends when the model has run out of unattended objects, which with four finsts and more than four objects never happens without a counting strategy. The Comparison section quantifies these failures on the benchmark. EMMA (Salvucci, 2001), the eye-movement extension shipped with ACT-R, models *when and where the eyes go given a chosen location*, and gs-vision keeps it for exactly that; EMMA does not model which location is chosen.

PAAV (Nyamsuren & Taatgen, 2013) replaced the location side with an `abstract-location` buffer served from an iconic memory with eccentricity-dependent acuity, a Guided Search 4 activation map, and a pruning rule that lets a model declare absence without fixating everything. It reproduced conjunction slopes of about 20 ms per item present and 54 to 73 ms per item absent, and fixation counts in a comparative-search task. Its limitations for the goal of human-like search are that it selects one item per fixation, so the item slope is tied to the saccade rate and cannot reach the 9 to 11 ms per item of Wolfe et al. (2010); that it has no adaptive quitting, so miss rates, prevalence effects and the absent-trial RT distribution are not modeled; that it requires ACT-R 6; and that it was never evaluated against RT distributions or error rates. gs-vision borrows PAAV's acuity and iconic-memory layer and its integration pattern, and replaces the rest. Because PAAV cannot be loaded into ACT-R 7, the Comparison section scores it through a mirror of its mechanisms transcribed from its source code.

# The gs-vision module

## Theory

gs-vision implements Guided Search 6 (Wolfe, 2021) as the organizing architecture, Competitive Guided Search (Moran et al., 2013) as the arithmetic of selection, identification and quitting, EPIC-style acuity (Kieras & Meyer, 1997) with PAAV's iconic memory for what is visible from where the eye is, and EMMA (Salvucci, 2001) for saccades. Figure 1 shows the pieces and the one-trial flow between them. Table 2 lists the equations.

![Figure 1. Architecture of gs-vision and the flow of one search. Productions (top) issue one request, receive one result, and report one outcome. Everything between runs on the module's own scheduled events. Gold arrows are the buffer interface; green and red arrows are the two possible outcomes of a search.](figs/fig_architecture.png)

*Priority map.* Every item in iconic memory receives a priority that is a weighted sum of bottom-up salience (local contrast in categorical feature channels, divided by inter-item distance, as in Guided Search 2), top-down guidance (categorical channel match to the guiding template; features that are not yet visible contribute an uncertainty term), a history term (priming traces per feature value decaying over about ten seconds), an optional value term and an optional scene prior, minus inhibition of return for recently rejected items, plus logistic noise. Guidance is restricted to *guiding features* (by default color, orientation, size, and luminance); every other feature, and shape above all, is compared only once an item is inside the identification stage. That one rule is what makes feature search efficient and spatial-configuration search inefficient with a single set of mechanisms.

*Covert selection and identification.* Every 50 ms, while a search is active and the identification stage has capacity (five items), the module selects one item by a Luce choice over the noisy priorities of the items inside the attentional functional visual field (8 degrees by default). Each selected item is identified after a Wald-distributed time (drift and threshold as in CGS), which completes when the item's required features are available at the current eye position; if they are not, the item waits for a saccade. A match ends the search with a hit; a mismatch rejects the item, adds it to the inhibition-of-return ring, and increments the quit unit.

*Quitting.* Two rules race. The competitive rule of CGS quits with probability equal to the quit weight divided by the sum of the quit weight and the guidance weights of every unresolved item, evaluated after every rejection. The adaptive rule of Guided Search 6 maintains a threshold scale that multiplies the effective set size; when the number of rejections reaches it, new selection pauses, outstanding identifications drain, and the search quits. Feedback after each trial lowers the scale after a correct rejection and raises it after a miss, with the prevalence-scaled step of the posted Guided Search 6 simulation, and updates a running prevalence estimate.

*Eyes.* A saccade is triggered when an item outside the attentional field carries guidance that exceeds the best item inside it by a margin, or when nothing selectable remains inside it; the destination is chosen from the exploratory field (12 degrees) by guidance minus a distance penalty. Preparation, execution (20 ms plus 2 ms per degree), and landing noise follow EMMA. On landing, acuity is re-evaluated: each feature of each item is available with a probability given by the EPIC rule, item size compared with a threshold that grows linearly with eccentricity and has a per-feature slope, and available features are written into an iconic memory that persists for four seconds.

Table 2. *Core equations of gs-vision*

| Mechanism | Equation | Origin |
|---|---|---|
| Availability of feature *f* of item *i* | P(size~i~ > N(θ~f~ · e~i~, σ)) | EPIC (Kieras & Meyer, 1997), PAAV |
| Priority | P~i~ = w~BU~BU~i~ + w~TD~TD~i~ + w~H~H~i~ + w~V~V~i~ + w~S~S~i~ − IOR~i~ + ε~i~, ε logistic | Guided Search 2 and 6 |
| Selection | p(i) = exp(βP~i~) / Σ~j~ exp(βP~j~), items inside the attentional field | CGS (Luce choice) |
| Identification time | Wald(μ, θ); mean θ/μ | CGS |
| Competitive quit | p(quit) = w~q~ / (w~q~ + Σ~unresolved~ w~j~), w~q~ += Δ per rejection | CGS |
| Adaptive quit | rejections ≥ scale × N~eff~; scale −= step after a true negative, += step / (2 · goal · prevalence) after a miss | Guided Search 6 |
| Saccade duration | 20 ms + 2 ms/deg, plus preparation and landing noise | EMMA |

## Design decisions

Four decisions were necessary to put this architecture into ACT-R, and each is a commitment a user should know about.

*The item-level loop runs inside the module.* Productions fire every 50 ms, which coincidentally matches Guided Search's selection rate but not its identification or fixation rates, and production overhead plus the 85 ms shift makes production-driven item search several times too slow. The declarative module set the precedent: retrieval is sub-symbolic and internal, and productions only request and receive. gs-vision does the same for search. A production sets the template; the module runs selection, identification, saccades and quitting on its own scheduled events; the target object arrives in the `visual` buffer, or the buffer is left empty with `state error`, exactly like a retrieval failure.

*It is a subclass, not a fork.* The module class inherits from `vision-module`. The `:vision` module is undefined and redefined with the same buffer names and every stock parameter, which is rebuilt from the live parameter table rather than copied out of `vision.lisp`. Ordinary requests are delegated to the stock methods. Consequently the motor module, the AGI devices, the Environment, and EMMA keep working, and every existing model runs unchanged: the backward-compatibility test runs the ACT-R tutorial unit 2 and unit 3 models under the stock module and under gs-vision, enabled and disabled, and requires identical traces line for line.

*The response stage is measured, not fitted.* The model presses a key with ACT-R's motor module. The keyboard response stage was measured from the module (160 ms for a repeated key, 260 ms for a switch, 310 ms for the first response of a block) and held fixed in every fit. The trial-level models in the Comparison section fit their own non-decision times; gs-vision never did.

*One model run is one simulated observer.* The adaptive threshold, the priming traces and the prevalence window persist across trials, so an experiment must clear per-trial state with `gs-reset-search`, not with `reset`.

## Implementation

The module is 2,000 lines of Common Lisp in five files (Table 3), loaded by `load-gs-vision.lisp` after ACT-R and EMMA and before any model exists. A Python mirror (`reference/gs_hybrid.py`) implements the same mechanisms with independent random streams; it is used for parameter fitting, because a 24,000-trial run takes about 75 s in either implementation but the mirror can run in parallel processes, and it is checked against the Lisp module on identical displays after every change (Lisp/mirror parity is reported with the validation). A Python harness drives ACT-R over its remote interface, generates displays, records event times, fits parameters, and evaluates runs against human data.

Table 3. *Files of the module and the harness*

| File | Contents |
|---|---|
| `gs-vision/gs-params.lisp` | Module class, item records, every `:gs-*` parameter with its validator |
| `gs-vision/gs-priority.lisp` | Feature channels, priority map, Wald and logistic samplers |
| `gs-vision/gs-diffuser.lisp` | Covert selection, identification, both quit rules, feedback |
| `gs-vision/gs-eye.lisp` | Acuity, iconic memory, functional visual fields, saccades |
| `gs-vision/gs-vision.lisp` | Creation, reset, request and query dispatch, module registration |
| `models/search-model.lisp` | The benchmark model used in this paper (listed in the Tutorial) |
| `reference/gs_hybrid.py` | Python mirror used for fitting and parity checks |
| `harness/` | Display generation, ACT-R driver, human data import, fitting, evaluation, reports |
| `tests/` | 115 Lisp event assertions; reference, compatibility and validation tests in Python |

# Tutorial: using gs-vision in a model

This section builds the model that produced every ACT-R result in the paper. Readers who want to run it should install ACT-R 7.31.4 (the repository vendors it), Steel Bank Common Lisp, and the Python environment from `requirements.txt`.

## Step 1: Load the module

The module must be installed before any model is defined, because a module cannot be undefined once a model exists.

```lisp
sbcl --load G:/VisualSearchModeling/gs-vision/load-gs-vision.lisp
```

Inside a model, two parameters turn the pieces on. With `:gs-enabled nil` the new requests are refused and the module behaves as the stock one, which is useful for ablations.

```lisp
(sgp :emma t :gs-enabled t)
```

## Step 2: Describe the display

Displays are added exactly as before with `add-visicon-features`. The module defines a chunk-type `gs-feature` that includes `visual-location` and adds the continuous slots `hue` (0–360), `orient` (degrees, 0 vertical), `lum` (0–1) and the categorical slot `shape`. Only the slots a modeler needs must be given: `color` is used when `hue` is absent, and `size` (in square degrees) is derived from `width` and `height` when it is absent. The listing below is what the harness sends for a red vertical bar, a green vertical bar and a digit.

```lisp
(add-visicon-features
  '(isa (gs-feature) screen-x 512 screen-y 300 kind bar color red value bar
        shape bar hue 0 orient 0 lum 0.5 width 20 height 60 size 0.7)
  '(isa (gs-feature) screen-x 700 screen-y 420 kind bar color green value bar
        shape bar hue 120 orient 0 lum 0.5 width 20 height 60 size 0.7)
  '(isa (gs-feature) screen-x 300 screen-y 500 kind digit color white value two
        shape two hue 0 orient 0 lum 1.0 width 30 height 40 size 0.6))
```

Two slots are available for models with a pixel front end: `salience` replaces the module's internal bottom-up computation with an externally computed value, and `prior` supplies a scene prior. Both enter the priority map with their own weights.

## Step 3: Issue a search

The full search is one request. The slots name the template; the module decides which of them guide (by default color, orientation, size and luminance) and which are compared only after selection. Options restrict guidance to named slots or select the quitting rule.

```lisp
+visual> isa gs-search color red orient steep      ; conjunction search
+visual> isa gs-search shape two                   ; no guiding feature: spatial search
+visual> isa gs-search color red guide color       ; restrict guidance to color
+visual> isa gs-search color red stop cgs          ; adaptive | cgs | both (default)
```

Channel names such as `steep`, `shallow`, `red` and `small` are categorical, following Guided Search; a numeric value is mapped to the channel it falls in. The result arrives in the `visual` buffer as an ordinary visual object, or the search quits and the buffer is left empty with `state error`. A model therefore branches on two buffer tests, exactly as it does for retrievals:

```lisp
(p respond-present
   =goal> isa trial state searching
   =visual>
   ?manual> state free
   ==>
   +manual> cmd press-key key "j"
   -visual>
   =goal> state responded)

(p respond-absent
   =goal> isa trial state searching
   ?visual> state error
   ?manual> state free
   ==>
   +manual> cmd press-key key "f"
   =goal> state responded)
```

For models that want to keep their own production loop, a guided location request exists as well. It ranks the visicon by the priority map instead of choosing at random and costs one selection interval rather than 0 ms; the usual filters (`screen-x`, `:nearest`, `:attended`) still apply.

```lisp
+visual-location> isa visual-location color red orient steep :guided t
```

## Step 4: Report the outcome

Adaptive quitting and priming need to know how the trial ended. The observer cannot know whether its response was correct, so the experiment tells it, and a production passes the outcome to the module after the keypress. This production is outside RT.

```lisp
(p report-outcome
   =goal> isa trial state responded outcome =o
   ?visual> state free
   ==>
   +visual> isa gs-feedback outcome =o          ; hit | miss | fa | tn
   =goal> state waiting outcome nil)
```

## Step 5: Read the diagnostics

Every selection, decision, saccade, fixation, quit and feedback is a trace event at `:output medium`, so it appears in the standard trace and in the Environment:

```
GS-SEARCH start template (COLOR RED ORIENT STEEP) n-eff 6. qt 1.00
GS-SELECT VISICON-ID2 priority 1.415
GS-DECIDE VISICON-ID2 reject
GS-SACCADE 512. 384. -> 700. 500. amp 11.0
GS-FIXATE 706. 495.
GS-DECIDE VISICON-ID9 hit
GS-FEEDBACK HIT qt 1.000 prevalence 0.50
```

Commands expose the same information to a harness: `gs-search-stats` returns fixations, rejections, elapsed time and the quit reason for the last search; `gs-fixation-log` returns stationary intervals as `(time x y duration)`; `gs-event-log` returns every timestamped event; `gs-state` returns the threshold scale, the prevalence estimate and the feedback count. `gs-reset-search` clears per-trial state between trials while preserving learning, and `gs-benchmark-gaze` places the eye at a fixation cross without charging time, as an experiment's fixation cross does.

## Step 6: Drive the experiment from Python

The repository's harness uses ACT-R's own remote interface (the `actr.py` client shipped with the tutorial). One trial is: reset the search, place the gaze, add the display, arm the goal, run until the keypress, then send feedback. The listing below is the core of `harness/run_batch.py`.

```python
actr.call_command("gs-reset-search")
actr.call_command("gs-benchmark-gaze", cx, cy)
actr.add_visicon_features(*display.visicon_features())
actr.call_command("gs-trial-setup", task, color, orient, shape)
actr.run(10)                                   # stops at the keypress monitor
outcome = score(display, key_pressed)
actr.call_command("gs-trial-feedback", outcome)
actr.run(2)                                    # feedback production and intertrial interval
stats = actr.call_command("gs-search-stats")
fixations = actr.call_command("gs-fixation-log")
```

`gs-trial-setup` and `gs-trial-feedback` are two Lisp functions defined at the bottom of the model file and registered as remote commands; they write the trial's template and outcome into the goal chunk. RT is measured from stimulus onset to the first valid keypress, recorded by a keypress monitor; the return of the event loop is about 90 ms later and is never used as RT.

## Step 7: Fit parameters

The module's search parameters are set with `sgp` and mirrored one-to-one in the Python `GSParams` record. The harness validates a complete configuration, sends it to ACT-R, reads every value back, and hashes the accepted values into the run record, so that a run can always be traced to the parameters it actually used. Fitting uses differential evolution (Storn & Price, 1997) on the mirror with the objective of the Validation section, and the selected configuration is then run in ACT-R at fresh seeds. The commands that reproduce the paper's fits are in the Open Practices section.

Table 4 lists the parameters a modeler is most likely to touch. The complete list, with the stock vision parameters that continue to work, is in the module's README.

Table 4. *Principal gs-vision parameters*

| Parameter | Default | Role |
|---|---|---|
| `:gs-guiding-features` | `(color orient size lum)` | Features that may guide selection; all others are identification-only |
| `:gs-select-interval` | 0.050 s | Time between covert selections |
| `:gs-diffuser-capacity` | 5 | Items identified at once |
| `:gs-choice-beta` | 4.0 | Luce temperature on priorities |
| `:gs-id-drift`, `:gs-id-threshold`, `:gs-id-sigma` | 0.25, 0.03, 0.1 | Wald identification: mean θ/μ, noise σ |
| `:gs-id-error` | 0.0 | Probability that an identification decision flips |
| `:gs-quit-delta` | 0.02 | Competitive quit weight per rejection |
| `:gs-qt-init`, `:gs-qt-step`, `:gs-error-goal` | 1.0, 0.05, 0.08 | Adaptive quitting |
| `:gs-memory` | 4 | Inhibition-of-return ring size |
| `:gs-attn-fvf`, `:gs-explore-fvf` | 8, 12 deg | Attentional and exploratory fields |
| `:gs-saccade-margin`, `:gs-saccade-trigger` | 0.25, 0 deg | When a peripheral item pulls the eye |
| `:gs-acuity-theta` | color .10, orient .20, shape .40, size .20, lum .10 | Acuity slope per feature |
| `:gs-w-bu`, `:gs-w-td`, `:gs-w-h`, `:gs-w-v`, `:gs-w-s` | 0.5, 1.0, 0.3, 0, 1.0 | Priority-map weights |
| `:gs-noise` | 0.2 | Logistic noise on priorities |
| `:gs-priming-tau` | 10 s | Decay of feature priming |
| `:gs-iconic-span` | 4 s | Persistence of a feature in iconic memory |
| `:gs-value-hook` | `nil` | Function or remote command supplying a value term per location |

# Validation against benchmark human data

## Data

Wolfe et al. (2010) published trial-level RTs and accuracy for three tasks that span the range of search efficiency: a feature search (red vertical target among green vertical bars), a color-by-orientation conjunction search (red vertical among red horizontal and green vertical), and a spatial-configuration search (a digit 2 among 5s), each at set sizes 3, 6, 12 and 18, target present on half the trials, with 9, 10 and 9 observers who each completed about 4,000 trials. The archive contains 111,777 trials, and the harness's importer retains every one of them, records the SHA-256 of each source file, and fails on any malformed line. Following the source paper's methods, RT analyses use correct trials between 200 and 4,000 ms (feature, conjunction) or 200 and 8,000 ms (spatial), and accuracy uses every validated trial. Participants are weighted equally; a cell's human quantile is the mean over participants of that participant's quantile.

## Protocol

Participants were split within each task into training, validation and test groups of 5/2/2 (feature), 6/2/2 (conjunction) and 5/2/2 (spatial) with a fixed seed, before any model was fitted. Parameters were fitted on the training participants, candidates were selected on the validation participants with fresh seeds, the selection was frozen, and the frozen model was then run in ACT-R with two further seeds at 1,000 retained trials per cell (2,000 per cell in total, 24 cells per split) and scored once against the test participants. The fitting objective was the mean over the 24 cells of the RMSE between model and human RT quantiles at .1, .3, .5, .7 and .9, plus 1,000 ms times the absolute difference in error rate, plus a penalty for trials that timed out. Simulated observers ran the experiment as the human observers did: 30 practice trials before each 300-trial block, accuracy feedback after each keypress, a two-second interval before the next display, and a fixation cross at which gaze was placed before each trial. Because the source files do not contain item coordinates, displays reproduce the published geometry with random placement.

The report of every run states three summary numbers: mean cell quantile RMSE (ms), the number of the six RT-by-set-size slopes (three tasks by present and absent) that fall within 5 ms per item of the human slope, and the largest miss-rate error in percentage points. Targets set before the work were 40 ms, 6 of 6, and 3 points. The Lisp module and the Python mirror were compared on identical displays in every cell with a Bonferroni-corrected z-test on search time; the frozen run has 0 of 24 exceedances with a maximum |z| of 1.47.

## Results of the frozen fit

The primary fit shares all settings across the three tasks; the module therefore has to derive the differences between tasks from the displays and the templates alone. Six parameters were fitted (identification threshold, inhibition-of-return memory, selection interval, bottom-up weight, attentional field, competitive quit increment) with a small differential-evolution search (four generations of 18, 72 evaluations). Table 5 gives the frozen results on all three splits, together with the module at its defaults and with the exploratory refit described next.

Table 5. *gs-vision runs in ACT-R against the human splits (2,000 retained trials per cell, no timeouts)*

| Run | Fitted parameters | Split | Mean RT RMSE (ms) | Quantile RMSE (ms) | Slopes within 5 ms/item | Largest miss error (points) |
|---|---|---|---|---|---|---|
| Module defaults | 0 | train | 465.9 | 351.9 | 3/6 | 11.5 |
| Module defaults | 0 | validation | 593.4 | 411.1 | 5/6 | 15.6 |
| Module defaults | 0 | test | 529.1 | 365.4 | 3/6 | 12.4 |
| Frozen shared fit | 6 | train | 160.7 | 151.5 | 3/6 | 10.1 |
| Frozen shared fit | 6 | validation | 123.7 | 143.1 | 5/6 | 16.5 |
| Frozen shared fit | 6 | **test** | **108.0** | **127.7** | **2/6** | **10.9** |
| Refit (exploratory) | 13 | train | 60.0 | 65.7 | 5/6 | 13.2 |
| Refit (exploratory) | 13 | validation | 191.6 | 173.3 | 2/6 | 14.7 |
| Refit (exploratory) | 13 | test | 102.5 | 100.1 | 4/6 | 11.3 |

The frozen model reproduces the qualitative structure of the benchmark: flat feature-search functions, a conjunction slope near the human value on absent trials, and spatial-configuration slopes that rise with set size on both trial types, with absent RTs about twice present RTs. Its quantitative misses on the test participants are a feature search that is 60 to 110 ms too fast throughout, a conjunction absent function that is too steep (39 versus 33 ms per item) and starts too late, spatial-configuration slopes that are too shallow (78 and 32 versus 98 and 45 ms per item), and miss rates that rise too steeply with set size in conjunction and spatial search (10.8 and 20.9 percent at set size 18 against 6.3 and 10.0). It produces no false alarms at all, because identification in this version is a timer rather than a decision.

## An exploratory refit

The frozen run's own trial and fixation logs identified six causes for those misses: a 130 ms fast edge (a 50 ms request latency, about 40 ms of identification, and the fastest keypress); an identification noise that was a fixed constant, forcing a coefficient of variation of 1.3 on every identification; a mandatory saccade at small set sizes in spatial search, because shape was resolvable only within about four degrees; an adaptive quit controller that had drifted to fifty times its starting scale and never bound, so that every miss came from the competitive rule; the structural impossibility of false alarms; and saccades that exceeded the attentional field because the covert loop exhausted the field before the eye moved. Six parameters were added to address them (Table 4: `:gs-id-sigma`, `:gs-id-error`, `:gs-onset-latency`, `:gs-adaptive-quit-delta`, `:gs-explore-proximity`, `:gs-saccade-trigger`), all defaulting to the frozen behavior so that the frozen results are unchanged, and thirteen parameters were refitted with a larger search (2,418 evaluations). Because the frozen test results had been inspected before this refit, it is exploratory, and Table 5 labels it so.

The refit improves the test fit from 127.7 to 100.1 ms, passes four of six slopes, and meets the 40 ms quantile target in seven of eight feature-search cells; conjunction absent cells improve two- to three-fold (Figure 2). It does not improve the miss rates, and on the validation participants it is *worse* than the frozen fit (173 versus 143 ms). The reason is instructive for anyone fitting group data with few participants: the two validation participants in spatial search are 20 percent faster than the training group, and the two in feature search 25 percent faster, while the two in conjunction search are slower. A model fitted to the training participants' speed loses on validation; the frozen fit had undershot the training participants by about the same amount and matched validation by accident. With two participants per split, validation selection decides which pair of people the model resembles, which is why every candidate is reported on every split.

![Figure 2. The exploratory refit of gs-vision run in ACT-R against the test participants. Top: mean correct RT by set size (shaded bands are the range across participants). Bottom: model against human RT quantiles (.1 to .9) for each of the eight cells per task; the dotted line is identity.](figs/fig_gsvision_test.png)

## Mechanism evidence: ablations

Fixed-parameter ablations at the frozen settings (seeds 321 and 322, 1,200 trials per cell) isolate what the eye and quitting policies contribute (Table 6). Restoring a second full encoding after identification, the behavior of the stock module, adds 43 to 49 ms to present trials. Reverting the saccade policy to guidance-only destinations with no margin and no distance penalty raises the spatial fixation count from 6.1 to 12.9 per trial and spatial absent RT from 2.5 to 4.4 s, and produces the only timeouts seen in the project. Raising the bottom-up weight from 0.5 to 3.0, which improves the capture effect reported below, raises conjunction absent RT from 1.1 to 2.8 s and the fixation count from 2.5 to 6.4, which is why the default was not promoted.

Table 6. *Ablations at the frozen settings (mirror; conjunction and spatial absent trials)*

| Configuration | Conjunction absent RT (ms) | Spatial absent RT (ms) | Spatial fixations per trial |
|---|---|---|---|
| Frozen policies | 1,146 | 2,510 | 6.1 |
| Extra recognition delay restored | 1,146 | 2,510 | 6.1 |
| Old saccade policy | 1,707 | 4,417 | 12.9 |
| Old quit weights | 1,192 | 3,218 | 6.1 |
| Bottom-up weight 3.0 | 2,812 | 2,510 | 6.1 |
| Threshold step 0.005 | 973 | 2,116 | 6.1 |

## Eye movements

The benchmark has no eye data, so the module's fixations were compared with the human values collected by Wu and Wolfe (2022) in a T-among-L foraging task whose data are on the Open Science Framework, with the caveat that foraging episodes and keypress search windows are not the same measurement. The human participant averages are 16.0 fixations per episode, 249 ms per fixation, 5.4 degree saccades, and a 9.5 percent refixation rate. The frozen gs-vision run produces stationary durations of 125 ms (feature), 186 ms (conjunction) and 142 ms (spatial), 4.6 fixations per spatial trial, and saccade amplitudes of 11.6 to 13.6 degrees; the refit lengthens the durations to about 200 ms in feature and conjunction search but leaves the amplitude at about 12 degrees. Fixation durations are therefore short and saccades are twice too long. The amplitude problem is structural: the covert loop clears the attentional field before the eye moves, so the next saccade goes to the best remaining item wherever it is. A saccade trigger that lets the eye start moving while covert selection continues was one of the refit's additions; the fits did not choose it strongly enough to fix the amplitude. Scanpath similarity to the human data (ScanMatch, MultiMatch) could not be computed for a matched experiment, because the foraging data lack the stimulus rotations and onset timestamps that a matched simulation needs; the human split-half consistency values are reported in the repository as the ceiling such a comparison would face.

## Secondary phenomena

Three effects that a Guided Search model should produce were tested at the frozen settings (Table 7). *Attentional capture* by an irrelevant salient singleton (the additional-singleton paradigm; Adam et al., 2021) costs the model 7.6 ms in ACT-R at the default bottom-up weight and 23 ms at a weight of 3, against 39 ms in the human data; the model's analogue uses an orientation target where the human study used a shape target, so this is a calibration, not a replication. *Priming of pop-out* (Maljkovic & Nakayama, 1994) is not established: repeat-minus-switch differences are within a few milliseconds at the frozen priming weight, and removing the history term changes them by 22 ms in the wrong direction because the history term also carries distractor priming. *Prevalence* (Wolfe et al., 2005) fails: at 10 percent target prevalence the model's misses rise by only 1.5 points and its absent responses *slow* by 87 ms, where human observers miss far more often and respond "absent" faster. This is a property of the posted Guided Search 6 feedback rules, which the module reproduces faithfully: with a true-negative step proportional to prevalence and a miss step inversely proportional to it, the controller's equilibrium miss rate is twice the error goal times the prevalence, which falls as prevalence falls. The same failure appears in a line-by-line Python port of Wolfe's MATLAB.

Table 7. *Secondary manipulations at the frozen settings (ACT-R runs; 95% intervals over simulation seeds)*

| Effect | Model | Human reference |
|---|---|---|
| Singleton capture cost, bottom-up weight 0.5 | 7.6 ms [2.5, 12.7] | 39.4 ms [31.6, 48.0] (Adam et al., 2021) |
| Singleton capture cost, bottom-up weight 3.0 | 23.0 ms [21.7, 24.2] | same |
| Priming of pop-out, switch minus repeat | −2.9 ms [−10.0, 4.2] | 20–60 ms (Maljkovic & Nakayama, 1994) |
| Prevalence 10% vs 50%, change in misses | +1.5 points [1.3, 1.7] | +20 to +25 points (Wolfe et al., 2005) |
| Prevalence 10% vs 50%, change in absent RT | +87 ms [77, 98] | faster |

# Comparison with other models

The question a prospective user will ask is whether the module is more accurate than what already exists. Eighteen configurations of eleven model families were scored on the same participants, splits, trimming, objective and code (Table 8; Figure 3). The ACT-R rows are runs of the module (defaults, frozen fit, refit), of a variant module described below, and of timing mirrors of the stock module and of PAAV. The trial-level rows are implementations of the published models in `reference/baselines.py`, fitted to the training participants with differential evolution (60 generations, population 8 per dimension, 200 trials per cell) and run at two seeds by 1,000 trials per cell.

*The stock ACT-R module* was driven by the ordinary find, attend, test loop with the same measured response stage. With its defaults (four finsts, 85 ms attention shift, three productions per item, a counting strategy so that absent trials terminate) its conjunction search runs at 47 to 57 ms per item present and 118 ms per item absent (human 11 and 33), its spatial search at 94 to 119 and 235 ms per item (human 45 and 98), and its feature search answers "absent" in 210 ms; its quantile RMSE on the test participants is 501 ms (Figure 4). Letting its attention latency, production count, finst count and response times vary brings it to 137 ms, and does so by driving the attention latency to 6 ms and the finst count to 19, which is no longer the stock module. These rows are a mirror of the module's documented timing rather than a run in ACT-R, and the mirror reproduces that timing exactly in a unit test.

*PAAV* was scored the same way, because it runs only on ACT-R 6 and porting its 7,000 lines to the current visicon, device and module interfaces was out of scope. Its mirror in `reference/baselines.py` transcribes the mechanisms of the posted source (`paav-visual-module`, version 0.98e): per-feature acuity (a feature of an item of size *s* at eccentricity *e* is visible when *s* > *a~f~e*^2^ − *b~f~e*, with the posted *a* and *b* per feature and the noise term disabled as in the source), iconic memory with four-second persistence, bottom-up activation as binary feature dissimilarity over one plus the square root of the pixel distance, top-down activation of 1, 0.5 or 0 per template feature for a match, an invisible feature, or a mismatch, selection of the highest 1.1·BU + 0.45·TD + noise among unattended items, permanent attended marks, the visual decision threshold that prunes candidates no farther from gaze than the last attended object whose top-down activation does not exceed it and declares absence when nothing remains, saccades of 20 ms plus 2 ms per degree with landing noise, 50 ms encoding, and three 50 ms productions per item. It runs on the same displays as gs-vision, so acuity and distance act on it as they do on the module. There is no Lisp implementation to check it against, which is the caveat that distinguishes these rows from the gs-vision rows. With the posted values PAAV scores 383 ms on the test participants. Feature search fits (71 ms; the threshold rule quits after one fixation on absent trials), but conjunction absent slopes are three times the human value (94 versus 33 ms per item), spatial-configuration search is nearly efficient (5 and 23 versus 45 and 98 ms per item), because shape is resolvable within about nine degrees and the binary contrast rule makes the 2 pop out among 5s, and it misses 10 percent of targets in feature and spatial search, because items in the corners of a 22.5 degree field have no visible feature from the fixation cross and are not in iconic memory when the search quits. Fitting nine parameters (noise, the two map weights, encoding time, production count, an acuity scale and the response stage) brings it to 275 ms; the fit does so by removing bottom-up activation (weight 0.03) and raising noise, which repairs conjunction search (28 ms per item absent) and the miss rates but leaves spatial search at 6 and 14 ms per item, and 3.6 percent misses at set size 18 against 10. A one-item-per-fixation architecture with a pruning rule cannot produce an inefficient search on a display where the target's shape is visible from a few fixations away; that is the limitation the Guided Search architecture removes.

*A Guided Search 6 variant* (gs6-vision, in its own folder of the repository) replaces the CGS engine with Wolfe's posted Guided Search 6 simulation: a two-bound diffusion per item stepped every 10 ms, an adaptive start point, the quit-signal diffuser with the MATLAB's feedback rules, diffuser-only memory, and Guided Search 2's dual orientation channels. It was built to answer how close the module can be made to Wolfe's own numbers. As posted, the engine does not fit (795 ms untuned; 313 ms with only the spatial layer fitted around it); with its rates fitted it reaches 122.5 ms on the test participants, about the frozen gs-vision fit, but with a drift, quit increment and selection interval far from the posted values. It produces false alarms at a plausible rate (1.3 percent against 2.3), which gs-vision does not, and misses 18 to 20 percent of targets at set size 3 in conjunction and spatial search, because its quit threshold scales with set size (Figure 5). Its absent-to-present slope ratio in conjunction search is 7 where the human value is 3.

*Trial-level models* have no display, no eye and no acuity, so they can be compared only on RT quantiles and errors. They were: a serial self-terminating model with a preattentive stage (Treisman & Gelade, 1980); Competitive Guided Search in two protocols (timing shared across tasks, and the paper's own all-parameters-per-task protocol); the fixation-based model of Hulleman and Olivers (2017); a parallel race with a capacity exponent (Townsend & Ashby, 1983; the competitor of Moran et al., 2016); and Wolfe's posted Guided Search 6 engine with a per-task target weight, as posted and with its rates fitted.

Table 8. *All models on the held-out test participants (quantile RMSE in ms; miss and false-alarm percentages are means over cells, human values in brackets)*

| Model | In ACT-R | Fitted params | Quantile RMSE | Feature | Conjunction | Spatial | Slopes within 5 ms/item | Largest miss error | Miss % (human 4.1) | FA % (human 2.3) |
|---|---|---|---|---|---|---|---|---|---|---|
| *Training participants' own averages* | | | *93.3* | 25 | 60 | 195 | 5/6 | 2.0 | 3.5 | 1.18 |
| Serial self-terminating (FIT) | no | 9 | 80.5 | 14 | 71 | 157 | 3/6 | 6.7 | 3.2 | 0.85 |
| CGS, shared timing | no | 12 | 82.9 | 29 | 68 | 152 | 2/6 | 6.1 | 4.6 | 1.15 |
| CGS, per task | no | 24 | 98.8 | 24 | 84 | 189 | 2/6 | 2.7 | 3.6 | 1.87 |
| **gs-vision, refit** | **yes** | 13 | **100.1** | 25 | 90 | 186 | 4/6 | 11.3 | 7.7 | 0.29 |
| Fixation-based (H&O) | no | 12 | 105.6 | 76 | 78 | 163 | 3/6 | 5.9 | 5.0 | 0.01 |
| GS6 engine, rates fitted | no | 12 | 114.3 | 22 | 100 | 222 | 1/6 | 4.2 | 3.3 | 1.27 |
| gs6-vision, rates fitted | yes | 16 | 122.5 | 42 | 98 | 227 | 3/6 | 18.4 | 11.1 | 1.30 |
| GS6 engine, as posted | no | 6 | 123.3 | 121 | 78 | 171 | 2/6 | 12.0 | 7.6 | 1.40 |
| **gs-vision, frozen fit** | **yes** | 6 | **127.7** | 99 | 162 | 122 | 2/6 | 10.9 | 7.2 | 0.00 |
| Parallel race | no | 14 | 129.4 | 72 | 131 | 185 | 3/6 | 8.6 | 1.5 | 1.18 |
| Stock ACT-R vision, timing fitted (mirror) | mirror | 6 | 137.3 | 29 | 171 | 211 | 2/6 | 10.0 | 0.0 | 0.00 |
| PAAV, fitted (mirror) | mirror | 9 | 275.4 | 49 | 109 | 668 | 3/6 | 6.4 | 2.3 | 0.00 |
| gs6-vision, engine as posted | yes | 8 | 312.9 | 92 | 304 | 543 | 4/6 | 14.5 | 8.0 | 1.45 |
| gs-vision, module defaults | yes | 0 | 365.4 | 103 | 265 | 729 | 3/6 | 12.4 | 7.1 | 0.00 |
| PAAV, posted values (mirror) | mirror | 0 | 382.9 | 71 | 497 | 582 | 2/6 | 9.0 | 8.4 | 0.00 |
| Stock ACT-R vision, 4 finsts (mirror) | mirror | 0 | 501.1 | 116 | 546 | 841 | 2/6 | 18.4 | 7.3 | 0.00 |
| Stock ACT-R vision, 20 finsts (mirror) | mirror | 0 | 540.1 | 116 | 574 | 930 | 2/6 | 10.0 | 0.0 | 0.00 |
| gs6-vision, Wolfe's values | yes | 0 | 795.1 | 157 | 564 | 1664 | 3/6 | 10.8 | 9.1 | 1.48 |

![Figure 3. Mean cell quantile RMSE of every model on the test participants (left) and the validation participants (right). Blue bars are ACT-R vision modules with a display and eyes (the stock module and PAAV as timing mirrors); gray bars are trial-level models with no display. The dashed line is the score of the training participants' own cell averages against the same participants, the level a model that reproduced its training data perfectly would reach.](figs/fig_comparison.png)

![Figure 4. The stock ACT-R vision module driven by a find, attend, test production loop (timing mirror, four finsts), against the test participants, in the format of Figure 2.](figs/fig_stock_test.png)

![Figure 5. Miss rates on present trials by set size for the human test participants and four models.](figs/fig_misses.png)

Four conclusions follow, and they should be read together.

First, *gs-vision is the most accurate model of visual search that runs in ACT-R and has eyes.* On the held-out participants its refit scores 100 ms and its frozen fit 128 ms, against 123 ms for the Guided Search 6 variant with its rates fitted, 137 ms for the stock module with its timing fitted, 275 ms for PAAV with nine parameters fitted, 383 ms for PAAV at its posted values, and 501 to 540 ms for the stock module as shipped. The stock module cannot be made to reproduce the benchmark without changing the numbers that define it, and PAAV cannot be made to produce an inefficient search. On the validation participants the frozen gs-vision fit is the best model of any kind (Figure 3, right).

Second, *it is within participant noise of the best models of any kind.* The two best trial-level models, a serial self-terminating model and CGS with shared timing, score 80 and 83 ms on the test participants. The training participants' own cell averages, used as a "model" of the test participants, score 93 ms, and the ranking of the top five models reverses on the validation participants. Differences under about 25 ms between models are not interpretable with two held-out participants per task, and nothing fitted on these splits can be expected to reach the 40 ms target. CGS's published misfits of 35, 22 and 5 ms for the three tasks (Moran et al., 2013) come from per-participant fits; fitted to group quantiles here and scored on held-out participants, the same model gives 152, 68 and 29 ms.

Third, *what the better-fitting models do differently is not a search mechanism.* Both fit a non-decision time per response and an exponential residual (two parameters that gs-vision does not have, because its response stage is measured from the motor module), and both fit per-task timing (the serial model's 23 ms per item in conjunction search, with an inspection-time coefficient of variation of 1.2, is a curve rather than a mechanism). gs-vision has one identification process and one quit controller and derives the differences between tasks from acuity and the template on a display. It matches CGS in feature search and beats the serial model in the conjunction-absent tails; it loses in spatial search, where it follows the slower training group and is uniformly 130 to 210 ms slow on the two test participants, and in conjunction-absent trials at set sizes 3 and 6, where its first quantiles are late because the covert loop pays a saccade before it can quit.

Fourth, *where gs-vision loses is the miss rate* (Figure 5). Its largest miss-rate error is 11 points against 3 to 7 for the trial-level models; at set size 18 in conjunction and spatial search it misses 18 to 19 percent of targets where the human observers miss 6 and 10. The quit rule abandons targets that are still being identified or still waiting for a saccade. CGS's quit unit, whose weight grows with each rejection against a fixed per-task target weight, produces misses that rise with set size at close to the human rate with one parameter per task; the module already has that unit, but its increment is shared across tasks and competes with the adaptive threshold instead of replacing it. That is the mechanism to change next.

# Discussion

## What the module offers a modeler

A model that uses gs-vision gains, for one buffer request, a search whose time course follows the display: efficient when a guiding feature separates the target, inefficient when only shape does, longer on absent trials than on present ones by a ratio that depends on the task, with positively skewed RT distributions whose spread grows with set size, miss rates that rise with set size, fixations that are logged with positions and durations, and learning across trials of a quitting criterion and feature priming. It gains these while keeping every stock request, every parameter, EMMA, the motor module and the Environment, so that an existing model can adopt the module by loading it and replacing one production loop with one request. The module runs at about 3 ms of wall-clock time per trial, so experiments with tens of thousands of trials are practical.

For cognitive models of applied tasks, the relevant properties are that the search cost of an interface element is now a function of its features, its position relative to the eye and the features of its neighbors, rather than a constant; that guidance can be restricted or turned off to model an observer who does not know what the target looks like; and that a `salience` slot and a `:gs-value-hook` let a pixel-level saliency model (Itti et al., 1998) or a learned value map feed the priority map from outside, which is the path to natural-scene search benchmarks such as COCO-Search18 (Chen et al., 2021).

## What it does not yet do

We have reported the failures as measured, and we list them here because they are the roadmap. Miss rates rise too steeply with set size in conjunction and spatial search, and the refit's error goal of 0.12 is a symptom rather than a cure; a per-task quit unit in the style of CGS is the next change. Saccade amplitudes are about twice the human value and fixation durations somewhat short, because covert selection exhausts the attentional field before the eye moves; a policy that lets the eye start earlier is implemented as `:gs-saccade-trigger` but was not selected strongly by the fits, and matched scanpath comparisons await eye-tracking data with the timing and stimulus information a simulation needs. The frozen model produces no false alarms; the refit's decision-error parameter produces them at 0.3 percent against 2.3, and the Guided Search 6 variant's two-bound diffusion gets closer. The prevalence effect is reproduced in the wrong direction by the posted Guided Search 6 feedback rules; a controller whose down-step is not multiplied by prevalence would restore a fixed equilibrium and a per-task error goal is what the human miss rates require. Priming of pop-out is not established. And the fits are group-level fits to five or six training participants, which, as the split-to-split differences of 20 to 30 percent in speed show, is the main limit on how well any model can score here; leave-participants-out or hierarchical fitting is the appropriate next protocol.

## On calling it the best

A tutorial that introduces a tool should say plainly what the tool's evidence supports. On the benchmark that the field uses to constrain models of search, with participants held out before fitting and every competitor fitted with the same objective, gs-vision is the most accurate vision module available for ACT-R: it is better than the stock module by a factor of four as shipped and better than the stock module with its timing fitted, better than PAAV at its posted values by a factor of three and than PAAV fitted by a factor of two and a half, and better than a faithful implementation of Guided Search 6's own engine on the same spatial layer. It is not better than the best trial-level models on RT quantiles, and the difference between it and them is smaller than the difference between two pairs of human participants. It has eyes, a display and a fixed response stage, which they do not, and it is worse at misses, which they are not. Those are the terms on which we recommend it.

## Principles for validating an architecture module

Three practices made the results in this paper reportable, and we recommend them for other module work. Hold participants out before fitting and freeze the selection before looking at them; label every later result exploratory, as we have. Score the model's implementation in the architecture against an independent implementation of the same mechanisms on identical inputs, so that a misfit can be attributed to the theory rather than to a bug; and note that a slowly drifting learned state (here, the quit threshold) makes that comparison anti-conservative unless the state is frozen. And fit the competitors with the same data, splits, objective and code as the model, including the architecture's own stock module, because a published misfit obtained under a different protocol is not a comparison.

# Open Practices Statement

The gs-vision module, the gs6-vision variant, the Python mirror and harness, the trial-level baseline models, all fitting and evaluation scripts, the run records (parameter values, seeds, source hashes, commands and logs) for every table in this paper, and the generated evaluation artifacts are available at https://github.com/ar-zadeh/gs-vision. The human data are the Wolfe et al. (2010) archive (https://search.bwh.harvard.edu/new/data_set_files.html) and the Wu and Wolfe (2022) fixation data (https://osf.io/vzg28/); the harness downloads them and verifies their hashes. The following commands regenerate the paper's ACT-R validation report, the model comparison and the test suites from the repository:

```
python harness/report.py --manifest data/model/repair_20260905/run_manifest.json --final-test
python harness/refit.py evaluate
python harness/compare_models.py fit && python harness/compare_models.py final
python harness/compare_models.py evaluate && python harness/compare_models.py report
sbcl --non-interactive --load tests/test_module_events.lisp
python -m pytest reference/test_reference.py tests/ -q
```

None of the reported studies were preregistered. The train/validation/test split, the objective, and the three summary targets were fixed and recorded in the repository before the first fit.

# Declarations

*Funding.* No funding was received for this work.

*Conflicts of interest.* The authors declare no competing interests.

*Ethics approval.* Not applicable; the study analyzed previously published, de-identified data.

*Consent to participate.* Not applicable.

*Consent for publication.* Not applicable.

*Availability of data and materials.* See the Open Practices Statement.

*Code availability.* See the Open Practices Statement.

*Authors' contributions.* AB: conceptualization, software, validation, writing the paper, editing. FER: reviewing, editing.

# References

Adam, K. C. S., Patel, T., Rangan, N., & Serences, J. T. (2021). Classic visual search effects in an additional singleton task: An open dataset. *Journal of Cognition, 4*(1), 34. https://doi.org/10.5334/joc.182

Anderson, J. R. (2007). *How can the human mind occur in the physical universe?* Oxford University Press.

Anderson, J. R., Bothell, D., Byrne, M. D., Douglass, S., Lebiere, C., & Qin, Y. (2004). An integrated theory of the mind. *Psychological Review, 111*(4), 1036–1060. https://doi.org/10.1037/0033-295X.111.4.1036

Bothell, D. (n.d.). *ACT-R 7.31 reference manual* [Computer software manual]. Carnegie Mellon University. http://act-r.psy.cmu.edu/

Byrne, M. D. (2001). ACT-R/PM and menu selection: Applying a cognitive architecture to HCI. *International Journal of Human-Computer Studies, 55*(1), 41–84. https://doi.org/10.1006/ijhc.2001.0469

Byrne, M. D. (2006). *Salience in the ACT-R visual system* [Presentation]. 13th Annual ACT-R Workshop, Pittsburgh, PA.

Chen, Y., Yang, Z., Ahn, S., Samaras, D., Hoai, M., & Zelinsky, G. (2021). COCO-Search18 fixation dataset for predicting goal-directed attention control. *Scientific Reports, 11*, 8776. https://doi.org/10.1038/s41598-021-87715-9

Dimov, C., Khader, P. H., Marewski, J. N., & Pachur, T. (2020). How to model the neurocognitive dynamics of decision making: A methodological primer with ACT-R. *Behavior Research Methods, 52*(2), 857–880. https://doi.org/10.3758/s13428-019-01286-2

Duncan, J., & Humphreys, G. W. (1989). Visual search and stimulus similarity. *Psychological Review, 96*(3), 433–458. https://doi.org/10.1037/0033-295X.96.3.433

Fleetwood, M. D., & Byrne, M. D. (2006). Modeling the visual search of displays: A revised ACT-R model of icon search based on eye-tracking data. *Human–Computer Interaction, 21*(2), 153–197. https://doi.org/10.1207/s15327051hci2102_1

Hulleman, J., & Olivers, C. N. L. (2017). The impending demise of the item in visual search. *Behavioral and Brain Sciences, 40*, e132. https://doi.org/10.1017/S0140525X15002794

Itti, L., Koch, C., & Niebur, E. (1998). A model of saliency-based visual attention for rapid scene analysis. *IEEE Transactions on Pattern Analysis and Machine Intelligence, 20*(11), 1254–1259. https://doi.org/10.1109/34.730558

Kieras, D. E., & Hornof, A. J. (2014). Towards accurate and practical predictive models of active-vision-based visual search. In *Proceedings of the SIGCHI Conference on Human Factors in Computing Systems* (pp. 3875–3884). ACM. https://doi.org/10.1145/2556288.2557324

Kieras, D. E., & Meyer, D. E. (1997). An overview of the EPIC architecture for cognition and performance with application to human-computer interaction. *Human–Computer Interaction, 12*(4), 391–438. https://doi.org/10.1207/s15327051hci1204_4

Maljkovic, V., & Nakayama, K. (1994). Priming of pop-out: I. Role of features. *Memory & Cognition, 22*(6), 657–672. https://doi.org/10.3758/BF03209251

Moran, R., Zehetleitner, M., Liesefeld, H. R., Müller, H. J., & Usher, M. (2016). Serial vs. parallel models of attention in visual search: Accounting for benchmark RT-distributions. *Psychonomic Bulletin & Review, 23*(5), 1300–1315. https://doi.org/10.3758/s13423-015-0978-1

Moran, R., Zehetleitner, M., Müller, H. J., & Usher, M. (2013). Competitive guided search: Meeting the challenge of benchmark RT distributions. *Journal of Vision, 13*(8), 24. https://doi.org/10.1167/13.8.24

Nyamsuren, E., & Taatgen, N. A. (2013). Pre-attentive and attentive vision module. *Cognitive Systems Research, 24*, 62–71. https://doi.org/10.1016/j.cogsys.2012.12.010

Salvucci, D. D. (2001). An integrated model of eye movements and visual encoding. *Cognitive Systems Research, 1*(4), 201–220. https://doi.org/10.1016/S1389-0417(00)00015-2

Storn, R., & Price, K. (1997). Differential evolution: A simple and efficient heuristic for global optimization over continuous spaces. *Journal of Global Optimization, 11*(4), 341–359. https://doi.org/10.1023/A:1008202821328

Townsend, J. T., & Ashby, F. G. (1983). *Stochastic modeling of elementary psychological processes.* Cambridge University Press.

Treisman, A. M., & Gelade, G. (1980). A feature-integration theory of attention. *Cognitive Psychology, 12*(1), 97–136. https://doi.org/10.1016/0010-0285(80)90005-5

Wiese, S., Lotz, A., & Rußwinkel, N. (2019). SEEV-VM: ACT-R visual module based on SEEV theory. In *Proceedings of the 17th International Conference on Cognitive Modeling* (pp. 301–307). Applied Cognitive Science Lab, Penn State.

Wolfe, J. M. (1994). Guided Search 2.0: A revised model of visual search. *Psychonomic Bulletin & Review, 1*(2), 202–238. https://doi.org/10.3758/BF03200774

Wolfe, J. M. (2021). Guided Search 6.0: An updated model of visual search. *Psychonomic Bulletin & Review, 28*(4), 1060–1092. https://doi.org/10.3758/s13423-020-01859-9

Wolfe, J. M., Horowitz, T. S., & Kenner, N. M. (2005). Rare items often missed in visual searches. *Nature, 435*(7041), 439–440. https://doi.org/10.1038/435439a

Wolfe, J. M., Palmer, E. M., & Horowitz, T. S. (2010). Reaction time distributions constrain models of visual search. *Vision Research, 50*(14), 1304–1311. https://doi.org/10.1016/j.visres.2009.11.002

Wu, C.-C., & Wolfe, J. M. (2022). The functional visual field(s) in simple visual search. *Attention, Perception, & Psychophysics, 84*(2), 383–395. https://doi.org/10.3758/s13414-021-02106-6

# Appendix: The complete benchmark model

The file `models/search-model.lisp` defines the model used for every ACT-R result in this paper. One production per task issues the search (the three templates have different slots, and a request slot with a `nil` value is not the same as an absent slot), two productions respond, and one production reports the outcome. The two functions at the end are registered as remote commands for the harness.

```lisp
(clear-all)
(define-model gs-search-model
  (sgp :v nil :trace-detail medium :er t
       :emma t :gs-enabled t
       :visual-num-finsts 4 :visual-finst-span 3.0)

  (chunk-type trial task state target-color target-orient target-shape outcome)
  (dolist (c '(start searching responded waiting done
               feature conjunction spatial bar digit two five))
    (unless (chunk-p-fct c) (define-chunks-fct `((,c name ,c)))))
  (define-chunks (goal isa trial task feature state waiting))
  (goal-focus goal)

  (p search-feature
     =goal> isa trial task feature state start target-color =c
     ?visual> state free
     ==>
     +visual> isa gs-search color =c
     =goal> state searching)

  (p search-conjunction
     =goal> isa trial task conjunction state start
            target-color =c target-orient =o
     ?visual> state free
     ==>
     +visual> isa gs-search color =c orient =o
     =goal> state searching)

  (p search-spatial
     =goal> isa trial task spatial state start target-shape =s
     ?visual> state free
     ==>
     +visual> isa gs-search shape =s
     =goal> state searching)

  (p respond-present
     =goal> isa trial state searching
     =visual>
     ?manual> state free
     ==>
     +manual> cmd press-key key "j"
     -visual>
     =goal> state responded)

  (p respond-absent
     =goal> isa trial state searching
     ?visual> state error
     ?manual> state free
     ==>
     +manual> cmd press-key key "f"
     =goal> state responded)

  (p report-outcome
     =goal> isa trial state responded outcome =o
     ?visual> state free
     ==>
     +visual> isa gs-feedback outcome =o
     =goal> state waiting outcome nil))

(defun gs-trial-setup (task color orient shape)
  (let ((task (string->name task))
        (color (and color (string->name color)))
        (orient (and orient (string->name orient)))
        (shape (and shape (string->name shape))))
    (dolist (c (remove nil (list task color orient shape)))
      (unless (chunk-p-fct c) (define-chunks-fct `((,c name ,c)))))
    (mod-focus-fct (list 'task task 'state 'start 'outcome nil
                         'target-color color 'target-orient orient
                         'target-shape shape))
    t))

(defun gs-trial-feedback (outcome)
  (let ((o (string->name outcome)))
    (if (member o '(hit miss fa tn))
        (progn (mod-focus-fct (list 'state 'responded 'outcome o)) t)
      (print-warning "gs-trial-feedback expects hit, miss, fa or tn, not ~s." outcome))))

(dolist (c '(("gs-trial-setup" gs-trial-setup "Arm the model for one trial.")
             ("gs-trial-feedback" gs-trial-feedback "Report a trial outcome.")))
  (unless (check-act-r-command (first c))
    (add-act-r-command (first c) (second c) (third c))))
```
