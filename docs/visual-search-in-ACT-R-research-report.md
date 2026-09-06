# Human-like Visual Search in ACT-R: Theory, PAAV, Design, and Validation

This historical architecture proposal is superseded by
[the implementation specification](IMPLEMENTATION-HANDOFF.md) and
[the validation repair](VALIDATION-REPAIR-HANDOFF.md). The repository
now uses a vision subclass on ACT-R 7.31.4; old missing-ACT-R and
fork/vision-10.1 statements below describe the pre-implementation state.

Compiled 2026-09-04 from primary sources (papers, ACT-R 7.31 source and reference manual, dataset pages). Items that could not be verified against a primary source are marked **[unverified]**.

Local environment checked: SBCL 2.6.3 with QuickLisp and Python 3.12 (numpy/pandas/torch) are installed. ACT-R itself is not yet in this project and must be downloaded into it; see §1.2 of `IMPLEMENTATION-HANDOFF.md`. The ACT-R facts below were read from a copy of the same 7.31 release (vision module v10.1, `extras/emma` v8.2a1) present elsewhere on the machine. The default vision parameters in that install are `:visual-attention-latency 0.085`, `:visual-num-finsts 4`, `:visual-finst-span 3.0`, `:visual-onset-span 0.5`, `:visual-movement-tolerance 0.5`. EMMA defaults: K = 0.006, k = 0.4, saccade 20 ms + 2 ms/deg, 50 ms non-labile init, 50 ms per prepared feature.

---

## 1. What the theories say

### 1.1 Guided Search 6.0 (Wolfe, 2021, *Psychon Bull Rev* 28:1060)

- **Two pathways.** A selective pathway passes items one at a time through a capacity-limited binding/recognition bottleneck. A non-selective pathway gives gist, ensemble statistics and scene layout without selection.
- **Priority map** = weighted average of five guidance sources: bottom-up salience, top-down feature guidance, history (priming, contextual cueing), value/reward, and scene syntax/semantics. Guidance uses coarse categorical feature channels (orientation must differ by ~10–15° to guide).
- **Selection rate.** Winner-take-all on the priority map picks a new item roughly every 50 ms (~20 Hz).
- **Asynchronous diffuser.** Each selected item takes 150–300 ms to reach a target/distractor bound, so ~5 items are "in the carwash" at once. This is how 20–40 ms/item slopes coexist with 200 ms recognition.
- **Memory for rejected items.** About 4–6 recently rejected distractors are not re-selectable. Otherwise sampling is close to with-replacement.
- **Quitting.** A separate noisy accumulator races to an adaptive quitting threshold (QT). QT scales with effective set size; true negatives lower it, misses raise it more. A separate start-point criterion adapts on hits and false alarms.
- **Three functional visual fields (FVF).** Resolution FVF (acuity/crowding), exploratory FVF (where saccades go), attentional FVF (what can be covertly processed within a fixation, radius ~5–8° in T/L search).
- **GS6 simulation parameters** (MATLAB on OSF 9n4hf): diffuser capacity 5; new item every 50 ms; diffuser updated every 10 ms; drift = 1/20 of distance to bound (200 ms noiseless); noise SD = 2.5× drift; QT ∝ set size; hit → start point +1 step, FA → −16 steps; TN → QT −1 step, miss → QT + step/(error goal × prevalence × 2). Produces linear RT×set size, TA:TP slope ratio ≈ 3 with 5-item memory, ~8% misses rising with set size, positively skewed RT distributions, prevalence criterion shifts. **The GS6 simulation has no space, eccentricity, or eye movements.**

### 1.2 Guided Search 2 (Wolfe, 1994) — the fully specified spatial version

- Bottom-up activation per feature: categorical channel differences with each neighbour in a 5×5 neighbourhood, thresholded by a preattentive JND, divided by inter-item distance, averaged, ceiling 200.
- Top-down: one channel per feature (largest target-minus-distractor response), rescaled to max 200.
- Activation map = weighted sum; noise Normal SD 100 units, shrinking with signal strength.
- Deployment in descending activation with perfect within-trial memory; 50 ms/item (SD 25) + 400 ms overhead.
- Termination: adaptive activation threshold staircase (success → up N, error → down K·N, K = 14 gives ~7% errors) plus a time-out.

### 1.3 Competitive Guided Search (Moran, Zehetleitner, Müller & Usher, 2013, *J Vision*)

The best quantitative fit to the standard RT-distribution benchmark. Eight parameters, analytic:

- Selection: Luce choice, p_i = w_i / Σ w_j; distractors w = 1, target weight w_T free (guidance strength).
- Identification time per item ~ Wald (drift μ, threshold θ), error-free.
- Rejected item weight → 0 (full inhibition). A quit unit gains Δw_quit after each rejection; p_quit = w_quit / (Σ w + w_quit).
- Residual time shifted exponential; motor error m.
- Fits to Wolfe, Palmer & Horowitz 2010: 2-vs-5: w_T 1.51, mean ID time 115 ms; conjunction: w_T 4.96, ~50 ms/item; feature: w_T 600 (single inspection). Mean quantile misfit 35 / 22 / 5 ms; error misfit ≤1.4%. Beats a 13-parameter parallel race (Moran et al. 2016).

### 1.4 Other theories worth borrowing from

| Theory | Core idea | Useful for |
|---|---|---|
| Target Contrast Signal (Lleras et al. 2020, *APP*) | Unlimited-capacity parallel accumulators driven by item–template contrast; RT logarithmic in set size; time-out sends unresolved "candidates" to serial stage | Efficient-search stage; heterogeneity and similarity effects |
| Hulleman & Olivers 2017 (*BBS*) | The fixation, not the item, is the unit. 250 ms fixations; items per fixation ∝ ease (30 / 7 / 1 max); memory for last 4 fixations; quit at 85% coverage | Fixation-level timing that maps naturally onto ACT-R's 50 ms cycle |
| EPIC / Kieras & Meyer (2010–2026) | No covert attention; acuity + crowding + eye movements + strategy explain slopes 0–90 ms/item | Acuity availability functions: P(detect) = P(size > N(α·e, 0.5)) per property |
| Attentional Engagement (Duncan & Humphreys 1989) | Efficiency falls with T–D similarity, rises with D–D similarity | Bottom-up rule design |
| TVA (Bundesen 1990) | Exponential race into VSTM with capacity K and rate C | Accuracy-based tasks; partial report |
| SDT parallel (Palmer, Verghese & Pavel 2000) | Max-of-outputs; set-size effects shrink with discriminability | Threshold/accuracy predictions |
| Itti–Koch saliency (1998/2000) | Center–surround pyramids, normalization, WTA + IOR | Pixel-level bottom-up salience for real images |
| TAM (Zelinsky 2008) | Retina transform + target-correlation map; population-averaged saccade landing | Center-of-gravity fixations; scene search |
| IVSN, IRL, Gazeformer, HAT, DeepGaze III (2018–2024) | Deep target-modulated priority maps; scanpath prediction on COCO-Search18 | External priority-map front end for natural scenes |

### 1.5 Benchmark phenomena a "human-like" model must reproduce

| Phenomenon | Target values |
|---|---|
| Slopes | Feature ≈ 1 ms/item (TP ≈ TA). Color×orientation conjunction ≈ 9 ms/item TP (Wolfe 2010) but 20–30 TP / 50–70 TA in classic T&G-style displays. 2-vs-5: 43 TP / 95 TA. TA:TP ratio typically 2–3. |
| RT distributions | Positively skewed; μ, σ, τ all grow with set size; TA variance exceeds TP variance for hard search; TA and TP distributions overlap more than a time-threshold quit allows. |
| Errors | Misses 5–10% rising with set size; false alarms < 2%, flat. Prevalence: misses ~7% at 50% → ~30% at 1–2%, TA RTs fall; criterion shift, d′ stable. |
| Eccentricity | RT rises with target eccentricity even when size is scaled. |
| Priming of pop-out | Repeat faster than switch; trace decays over ~5–8 trials. |
| Similarity | T–D similarity slows, D–D similarity speeds; heterogeneity cost. |
| Eye movements | 3–4 fixations/s, fixation 180–275 ms, saccades 3–7°, attentional FVF 5–8°, refixations 5–20%. COCO-Search18: TP ≈ 2.6, TA ≈ 5.0 fixations. |
| Memory / IOR | ~4 rejected items or locations. |
| Scene guidance | ~50% of first saccades already target-directed in scenes. |

---

## 2. What ACT-R offers today, and why it falls short

### 2.1 Default vision module (ACT-R 7.31, `core-modules/vision.lisp`)

- Where system: a `visual-location` request filters the visicon by slot constraints (`color`, `kind`, `value`, `screen-x/y`, `size`, `lowest`/`highest`, `:nearest`, `:attended new/nil/t`). It costs **0 ms**. Ties are broken by newest onset, then **random**.
- What system: `move-attention` shifts and encodes in a fixed **85 ms** (`:visual-attention-latency`).
- Finsts: 4 markers, 3 s span, oldest reused.
- No eccentricity, acuity, salience, eye position, or guidance strength. The whole visicon is equally visible.
- Timing arithmetic for a find → attend → test production loop: 50 + 0 + 50 + 85 + 50 ≈ **185–235 ms per item**; with `:auto-attend` or pipelining the floor is **135 ms/item**. Humans: 10–50 ms/item conjunction slopes. Fleetwood & Byrne (2006) found the same 135 ms too *fast* for icon-search fixations, i.e. the default module is calibrated for neither covert item selection nor overt fixations.

### 2.2 EMMA (`extras/emma`)

Companion module that installs itself through `:visual-encoding-hook`. Encoding time T_enc = K·(−ln f)·e^{k·ε} (K = 0.006, k = 0.4), saccade preparation via feature-preparation costs (0–150 ms), non-labile 50 ms, execution 20 ms + 2 ms/deg, logistic landing noise. It handles *when and where the eyes go* given a chosen location, but not *which location* is chosen. Encoding at ε = 0 with f = 0.1 is ~14 ms, so near items can be covertly encoded before a saccade launches.

### 2.3 PAAV (Nyamsuren & Taatgen, 2012 ICCM; 2013 *Cogn Syst Res* 24:62)

What it does:

- Replaces the where side with an **`abstract-location` buffer** served from **iconic memory** (4 s persistence) rather than the visicon.
- Five fixed features: color, shape, shading, orientation, size.
- **Acuity**: feature visible iff size s > a·e² − b·e (a ≈ 0.10–0.15, b ≈ 0.85–0.96 per feature), a simplified Kieras (2010) function.
- **Activation** adapted from GS4: bottom-up BA_i = Σ_j Σ_k dissim(v_ik, v_jk)/√d_ij (binary dissimilarity); top-down TA_i = Σ_k sim(f_ik, f_k) with 0.5 for unknown features; VA_i = 1.1·BA_i + 0.45·TA_i + logistic noise (s = 0.2).
- **Visual decision threshold**: after encoding an item, objects with lower top-down activation *and* closer distance are pruned, so absence can be declared without fixating everything.
- Saccades: 20 ms + 2 ms/deg with size-scaled Gaussian landing; encoding fixed at **50 ms**.
- Fits: feature search flat (~440 ms TP / ~640 ms TA); conjunction **~20–23 ms/item TP, ~54–73 ms/item TA** (values differ between the ICCM and CSR versions); comparative search 37.4 vs 39.6 human fixations/trial; SET card game color dominance.

Limitations that matter for a "closest to humans" goal:

1. **ACT-R 6 only.** Code (v0.98e / 0.99g) is on bcogs.net/models; no ACT-R 7 port and no public repository were found **[unverified beyond that page]**. Porting is required.
2. **One item per fixation.** No attentional FVF, no asynchronous diffuser. Item slope is therefore tied to saccade rate, which is why its TA slope is too steep and it cannot produce the 9 ms/item conjunction slopes in Wolfe 2010.
3. **Binary feature similarity.** No categorical channels, no continuous similarity, so T–D similarity and heterogeneity effects are coarse.
4. **No history, reward, or scene guidance** (three of GS6's five sources).
5. **No quitting model.** The decision threshold is a pruning heuristic, not an adaptive criterion, so prevalence effects, miss rates and the TA RT distribution are not modeled.
6. **Never validated on RT distributions, errors, or eye-movement statistics** beyond fixation counts in one task. No R² or RMSE reported.
7. **Fixed feature set.** No modeler-defined features; no pixel input.

### 2.4 Other ACT-R attempts

Byrne (2006) salience add-on for ACT-R 6 (bottom-up + top-down + noise in `visual-location` choice); Stewart & West (2007) Python ACT-R salience; SEEV-VM (Wiese, Lotz & Rußwinkel 2019) based on PAAV + EMMA with SEEV guidance, unvalidated; Fleetwood & Byrne (2006) icon search with EMMA and `:nearest current`; ACT-CV and JSegMan/VisiTor for pixel-to-visicon. None implements GS6-style guidance plus a diffuser plus adaptive quitting in ACT-R 7. **That gap is the contribution available here.**

---

## 3. Proposed design: a guided-search vision module for ACT-R 7

### 3.1 Key architectural decision

Put the **item-level loop inside the module** and expose only **fixation-level events** to productions. ACT-R productions fire every 50 ms, which matches the *item selection rate* of GS6 by coincidence but not the fixation rate, and the 85 ms shift plus production overhead makes production-driven item search 3–10× too slow. The declarative module already sets the precedent: retrieval is sub-symbolic and internal, productions only request and receive. Do the same for search: productions set the guiding template and strategy, the module runs selection, identification, saccades and quitting, and returns "target at location X" or "search failed" with a realistic time course.

### 3.2 Layers

1. **Extended visicon.** Keep `add-visicon-features` but add continuous feature slots (hue angle, orientation degrees, size deg², luminance, shape category) alongside the existing symbolic slots for backward compatibility. For pixel input, a Python front end (Itti–Koch, or a DNN target-modulated map from IVSN/HAT) writes features and a per-item bottom-up salience value.
2. **Acuity and iconic memory (from PAAV / EPIC).** Per-feature availability by eccentricity: P(available) = P(s > N(α_f·e, σ)). Available features enter iconic memory (4 s persistence, updated every fixation). Unavailable features contribute 0.5 uncertainty in top-down matching.
3. **Priority map (GS2/GS6).** For each item i:
   `P_i = w_BU·BU_i + w_TD·TD_i + w_H·H_i + w_V·V_i + w_S·S_i − IOR_i − Prox_i + ε`
   - BU_i: GS2 local contrast in categorical channels, divided by distance, averaged over neighbours.
   - TD_i: per-feature categorical-channel match to the guiding template (one channel per feature, GS2 rule), continuous similarity within channel.
   - H_i: priming trace per feature value, decaying over ~5–8 trials.
   - V_i: value/reward weight (optional; hook for utility learning).
   - S_i: scene prior supplied externally (optional).
   - IOR_i: rejected within the last N items (N = 4–6, replaces finsts for search).
   - Prox_i: eccentricity penalty relative to current gaze (attentional FVF radius ~5–8°).
   - ε: logistic noise, scale s.
4. **Covert selection + asynchronous diffuser (GS6, CGS).** Every τ_sel = 50 ms, if the diffuser has capacity (default 5), select the WTA item within the attentional FVF. Each item accumulates toward target/distractor bounds with Wald-distributed completion (CGS μ, θ). Distractor completion → IOR and reduce its weight to 0. Target completion → module returns location + object to the `visual` buffer.
5. **Overt saccades (EMMA).** When no un-rejected item with priority above a threshold remains inside the attentional FVF, or after a fixation-duration limit, program a saccade to the priority peak in the exploratory FVF using EMMA's preparation, non-labile, execution and landing-noise rules. Update acuity, iconic memory and Prox on landing.
6. **Quitting (GS6/CGS).** A quit accumulator gains Δw_quit per rejection (CGS) with the GS6 adaptive rule on outcomes: TN → QT − δ, miss → QT + δ·(1/(error-goal × prevalence × 2)); hit → start point up, FA → start point down. Quit → `state error` on the buffer plus a `search-failure` chunk, mirroring retrieval failure.
7. **Buffer interface.** Keep `visual-location` and `visual` so existing models run unchanged. Add:
   - `+visual-location> isa guided-search color red orientation vertical :fvf t` → selection by priority map rather than random.
   - `+visual> isa search template T1 stop-rule adaptive` → run the full internal loop; response arrives when found or quit.
   - Queries: `state busy/free/error`, `fixations`, `items-rejected`.
   - Trace events per item selection, saccade, and quit, so the Environment and Python harness can log fixations and item-level timing.

### 3.3 Parameters (initial defaults)

| Parameter | Default | Source |
|---|---|---|
| `:gs-select-interval` | 0.050 s | GS6 |
| `:gs-diffuser-capacity` | 5 | GS6 |
| `:gs-id-drift`, `:gs-id-threshold` | μ 0.25, θ 0.03 (2-vs-5) | CGS fit |
| `:gs-memory` (IOR items) | 4 | Horowitz & Wolfe; H&O |
| `:gs-attn-fvf` | 6° | Wu & Wolfe 2019 |
| `:gs-w-bu`, `:gs-w-td` | 1.1, 0.45 (PAAV) or fit | PAAV / GS2 |
| `:gs-noise` | 0.2 | PAAV |
| `:gs-quit-delta` | 0.02 (2-vs-5), 0.16 (conj) | CGS |
| `:gs-acuity-alpha` per feature | 0.10–0.15 | PAAV/Kieras |
| EMMA parameters | existing defaults | EMMA |

### 3.4 Implementation route

- **Language.** Lisp module in ACT-R 7.31 using `define-module`, forked from `vision.lisp` (LGPL) rather than written from scratch, because the motor module, AGI and Environment reach into vision internals (Fitts targets, `:show-focus`, cursor device). Reuse EMMA's saccade code via its hook rather than re-implementing.
- **Development harness in Python** over the remote interface (`tutorial/python/actr.py`): generate displays with `add_visicon_features`, monitor `output-key`, run 10k-trial batches, fit parameters (e.g. with differential evolution) and plot quantiles. ACT-R also supports modules written in Python (`examples/creating-modules/external`), which is a fast path for prototyping the priority map before porting to Lisp; per-event JSON-RPC overhead makes it too slow for final batch runs.
- **Reference implementation first.** Before touching ACT-R, reproduce CGS and the GS6 simulation in Python and confirm they reproduce their published fits to Wolfe 2010. That gives a known-good target for the Lisp port.
- **Effort estimate.** Priority map + FVF + diffuser in a forked vision module: 3–5 weeks. EMMA integration and quitting: 2 weeks. Python harness and Wolfe 2010 fits: 2 weeks. COCO-Search18 front end: 4+ weeks and a separate paper.

---

## 4. Would it be close to humans? An honest forecast

- **Mean RT slopes and intercepts** for feature, conjunction and 2-vs-5: yes, achievable to within a few ms/item; PAAV already gets there approximately and the diffuser fixes its TA slope problem.
- **RT distributions and error rates** (the Wolfe 2010 constraints): achievable to roughly CGS quality (quantile misfit 20–35 ms) if the CGS core is used as the identification/quit engine. No ACT-R model has ever been evaluated this way, which makes it publishable on its own.
- **Prevalence and priming effects**: qualitatively yes with the adaptive QT and history term; quantitative fits will need data the lab collects or requests from Wolfe.
- **Eye-movement statistics on simple displays**: fixation counts and durations plausible; exact scanpaths only at the level of MultiMatch/ScanMatch similarity comparable to human–human agreement.
- **Natural scenes**: only as good as the external priority map fed in. HAT/Gazeformer-level scanpath prediction is out of reach for a symbolic-feature visicon; the ACT-R contribution there is the timing, memory and quitting layer on top of a DNN map.
- **Fundamental limits**: ACT-R's discrete 50 ms cycle and single attention focus mean crowding, ensemble statistics and the non-selective pathway must be approximated as module-internal computations, not emergent behavior.

---

## 5. Is there a better model to implement than GS / PAAV?

Recommendation: **GS6 as the organizing theory, CGS as the quantitative engine, H&O/EPIC for the fixation and acuity layer, PAAV's iconic memory and buffer design as the ACT-R integration pattern.** Reasons:

- GS is the dominant framework and its serial selection maps naturally onto ACT-R's single attention focus. TCS is a strong alternative for the efficient regime but has no serial stage of its own; it can be adopted as the "parallel pre-stage" that sets initial priorities.
- CGS is the only model with published, near-exact fits to full RT distributions; reusing its mechanics lets the ACT-R model's accuracy be reported against a known benchmark.
- Pure saliency (Itti–Koch) and FIT are not competitive on their own.
- Deep scanpath models (HAT, Gazeformer, DeepGaze III) win on natural-scene benchmarks but are not cognitive architectures; they are best used as front ends.

---

## 6. Datasets and how to report accuracy

### 6.1 Datasets

| Dataset | Task | N / trials | Measures | URL | Verified |
|---|---|---|---|---|---|
| Wolfe, Palmer & Horowitz 2010 | Feature / conjunction / 2-vs-5, set sizes 3–18 | 9–10 obs, ~4k trials each | RT, errors | search.bwh.harvard.edu/new/data_set_files.html | Server unreachable during this check; email jwolfe@bwh.harvard.edu if it stays down |
| Adam, Patel, Rangan & Serences 2021 | Additional-singleton search | 190 pp, >210k trials | RT, accuracy | osf.io/u7wvy (CC BY 4.0) | Yes |
| Wu & Wolfe FVF | Simple search, eye tracking | — | fixations | osf.io/vzg28 | Exists |
| Lleras/Buetti conjunction 2025 | Conjunction search | — | RT | osf.io/ymv28 | Exists |
| Chapman & Störmer 2024 | Efficient search | — | RT | osf.io/u5trm | Exists |
| COCO-Search18 (Chen et al. 2021) | Categorical scene search TP/TA | 10 obs, ~300k fixations | RT, acc, fixations | sites.google.com/view/cocosearch | Yes (non-commercial) |
| COCO-FreeView | Free viewing control | 10 obs, 822k fix | fixations | same site | Yes |
| MCS (Zelinsky 2019) | Microwave/clock search | 60 obs, ~140k fix | fixations | www3.cs.stonybrook.edu/~cvl/projects/coco_search/MCS_dataset.zip | Yes |
| Ehinger et al. 2009 | Person search in 912 scenes | 14 obs | fixations, keypress | olivalab.mit.edu/SearchModels | Yes |
| ViSioNS (Travi et al. 2022) | Bundle: Interiors, Unrestricted, People, COCO-Search18, MCS | — | scanpaths | github.com/NeuroLIAA/visions | Yes |
| Zhang et al. 2018 "Waldo" | Arrays, scenes, Waldo | — | fixations | github.com/kreimanlab/VisualSearchZeroShot | Exists (license click-through) |
| FoMo (Clarke & Hughes 2026) | 7 foraging datasets | 16–64 pp each | selections | github.com/Riadsala/FoMo | Yes |
| VSGUI10K (Putkonen et al. 2025) | GUI target search | 84 pp, 10,282 trials | search time, fixations | osf.io/hmg9b (CC BY 4.0) | Yes |
| UEyes (Jiang et al. 2023) | UI free viewing | 62 pp, 1,980 UIs | fixations | zenodo.org/record/8010312 | Yes |
| Mathema et al. 2026 | Waldo search among other tasks | 139 pp | fixations | Figshare via *Sci Data* (CC BY 4.0) | Yes |

Not public: Zelinsky 1997/2008 behavioral data, Fleetwood & Byrne icon data, Hornof/Halverson menu data, Hulleman & Olivers, Treisman & Gelade replications.

### 6.2 Validation tiers

1. **Tier 1, behavioral RT/error (Wolfe 2010 + Adam 2021).** Report slope/intercept R² and RMSE per task; quantile misfit (ms) at .1/.3/.5/.7/.9 for TP and TA per set size; ex-Gaussian μ/σ/τ vs. human; miss and FA rates. Yardstick: CGS misfits of 35/22/5 ms.
2. **Tier 2, eye movements on simple displays (Wu & Wolfe FVF, own eye-tracking).** Fixations to target, fixation durations, saccade amplitudes, refixation rate, proportion of fixations on target-similar distractors; ScanMatch/MultiMatch vs. the human–human ceiling.
3. **Tier 3, natural scenes (COCO-Search18 via ViSioNS).** Sequence Score, Semantic Sequence Score, MultiMatch, TFP-AUC, cNSS/cIG. Human sequence score ≈ 0.49; HAT and Gazeformer are the baselines to cite.
4. **Tier 4, applied (VSGUI10K).** Search time and fixation count on real GUIs, the natural target for the group's existing JSegMan/VisiTor pipeline.

### 6.3 How to phrase "how accurate our model is"

State, per tier: the metric, the model value, the human value, the human–human consistency ceiling, and the best competing model. Example: "Conjunction TP slope 11 ms/item (human 9), TA 24 (human 22); quantile RMSE 28 ms across 24 cells (CGS 22 ms); miss rate 6.8% (human 7.1%)."

---

## 7. Suggested phases

1. **Weeks 1–2.** Fetch Wolfe 2010 and Adam 2021; re-implement CGS and the GS6 simulation in Python; confirm published fits.
2. **Weeks 3–6.** Fork `vision.lisp` into a guided-search module: extended features, acuity + iconic memory, priority map, FVF-limited WTA selection, diffuser, IOR. Python harness for batch runs.
3. **Weeks 7–8.** EMMA saccade integration; adaptive quitting; priming term. Fit Tier 1.
4. **Weeks 9–10.** Eye-movement validation (Tier 2); write-up comparing to PAAV, CGS, H&O.
5. **Later.** DNN priority front end and COCO-Search18 (Tier 3); GUI search with VSGUI10K (Tier 4).

---

## Key references

Wolfe 1994 *PB&R* 1:202; Wolfe 2007 GS4 in Gray (ed.); Wolfe 2021 *PB&R* 28:1060; Wolfe, Palmer & Horowitz 2010 *Vision Res* 50:1304; Palmer, Horowitz, Torralba & Wolfe 2011 *JEP:HPP*; Moran et al. 2013 *J Vision* 13(8):24; Moran et al. 2016 *PB&R* 23:1300; Lleras et al. 2020 *APP* 82:394; Hulleman & Olivers 2017 *BBS* 40:e132; Kieras & Meyer 2026 *PB&R* 33:76; Nyamsuren & Taatgen 2013 *Cogn Syst Res* 24:62; Nyamsuren 2014 PhD thesis (Groningen); Salvucci 2001 *Cogn Syst Res* 1:201; Fleetwood & Byrne 2006 *HCI* 21:153; Byrne 2006 ACT-R Workshop salience; Wiese, Lotz & Rußwinkel 2019 ICCM; Bothell, ACT-R 7.30+ Reference Manual; Chen et al. 2021 *Sci Rep* 11:8776; Yang et al. 2020 CVPR; Mondal et al. 2023 CVPR; Yang et al. 2024 CVPR (HAT); Zhang et al. 2018 *Nat Commun* 9:3730; Zelinsky 2008 *Psych Rev* 115:787; Adam et al. 2021 *J Cognition*; Putkonen et al. 2025 *IJHCS*; Travi et al. 2022 arXiv 2112.05808.
