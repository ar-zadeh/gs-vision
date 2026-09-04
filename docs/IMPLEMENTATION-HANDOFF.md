# Implementation Handoff: Guided-Search Vision Module for ACT-R 7

Audience: an implementer (human or LLM agent) with no prior context. Everything needed to build, run, and validate the module is in this document plus the companion report `docs/visual-search-in-ACT-R-research-report.md` (theory background, dataset table, references). Read both before writing code. **Where the two disagree, this document wins**: the report's §3.2 buffer sketch and its "fork vision.lisp" wording in §3.4/§7 are superseded by §4 and §5.7 below.

Revision history: 2026-09-04 first version; 2026-09-04 (later) revised after a source-level review and after ACT-R and PAAV were copied into the repo. The revision corrected the ACT-R build facts (§1, §3), the acuity and weighting rules (§5.2, §5.3), the selection/quit arithmetic (§5.4, §5.6), the buffer API (§5.7), the benchmark geometry (§8.1), the fitting plan (§8.4) and several citations (§9, §13).

---

## 0. One-paragraph goal

Build a replacement vision module for ACT-R 7.31 (Lisp) that performs visual search the way humans do, following Guided Search 6 (Wolfe 2021) for the architecture, Competitive Guided Search (Moran et al. 2013) for the quantitative selection/identification/quitting engine, and PAAV (Nyamsuren & Taatgen 2013) / EMMA (Salvucci 2001) for ACT-R integration of acuity, iconic memory, and eye movements. Then validate it against public human data (Wolfe, Palmer & Horowitz 2010 RT distributions; Adam et al. 2021; eye-tracking sets) and report accuracy with standard metrics. The result must run existing ACT-R models unchanged and must produce human-like search slopes, RT distributions, error rates, and fixation statistics.

---

## 1. Environment

### 1.1 Already present and verified on this machine (checked 2026-09-04)

| Item | Location / value |
|---|---|
| Lisp | **SBCL 2.6.3**, `C:\Program Files\Steel Bank Common Lisp\sbcl.exe` (on `PATH`; `sbcl --version` prints `SBCL 2.6.3`) |
| QuickLisp | `C:\Users\ITXPC\quicklisp`, wired into `C:\Users\ITXPC\.sbclrc` (the init block appears twice there; harmless), so `(ql:quickload ...)` works in a bare `sbcl` session. `load-act-r.lisp` quickloads `bordeaux-threads`, `usocket` and `cl-json`. |
| Python interpreter | 3.12.4 (Anaconda, `C:\Users\ITXPC\anaconda3\python.exe`, on `PATH` as `python`), pip 25.3, `venv` module present. **Bootstrap interpreter only.** Do not install packages into it and do not use it directly for project code; create the project venv in §1.3. |
| Project root | `G:\VisualSearchModeling` (this repo). Not yet a git repository; see §1.4. |
| **ACT-R sources** | `G:\VisualSearchModeling\actr7.x` — **ACT-R 7.31.4**, the upstream build dated 2026-06-10 (472 files, 231 Lisp files, no `.fasl`, about 242 MB). Fingerprint: `framework/version-string.lisp` has `*actr-major-version-string* "31"` and `*actr-minor-version-string* "4"`; `core-modules/vision.lisp` is version **11.1**, **4666 lines**; `extras/emma/emma.lisp` is version **8.2a3**. Treat as a vendored dependency: read it, load it, never edit it. |
| **PAAV source** | `G:\VisualSearchModeling\paav-visual-module_2014.01.15.lisp` — PAAV **0.98e** (Nyamsuren, last modified 2014-01-08), 7136 lines, **written for ACT-R 6**, licensed **GPL v3**. It does not load in ACT-R 7. It is here as a reference implementation of acuity, iconic memory and activation maps; see §1.7 for what to read in it and §12 for the licence consequence of copying code out of it. |

There is a second, older ACT-R copy on this machine at `G:\ACT-RModels\actr7.x` (7.31 without minor version, vision.lisp 10.1, 4601 lines; identical to `G:\Downloads\actr7.x.zip`). **Do not mix the two.** Everything in this document refers to the 7.31.4 copy inside this repo. The only code difference between the builds in the vision module is that `printed-visicon` gained an optional `show-pending` argument, which shifts every line number in `vision.lisp` by +37 relative to the older copy; behaviour is unchanged.

No Lisp installation work is required. Do not install another Lisp or another Python.

### 1.2 Step 0a: verify the vendored ACT-R (already extracted)

ACT-R is already in place, so there is nothing to download. Before relying on the line numbers in §3, confirm the fingerprint from the project root:

```powershell
cd G:\VisualSearchModeling
Select-String -Path actr7.x\framework\version-string.lisp -Pattern 'actr-(major|minor)-version-string\* "'
(Get-Content actr7.x\core-modules\vision.lisp).Count        # expect 4666
Select-String -Path actr7.x\core-modules\vision.lisp,actr7.x\extras\emma\emma.lisp -Pattern ':version-string "'
```

Expected: major `"31"`, minor `"4"`, 4666 lines, vision `"11.1"`, EMMA `"8.2a3"`. If any of these differ, the copy is not the build this document was written against: locate every definition named in §3 with `Select-String` (or `grep -n`) by symbol name instead of trusting the line numbers.

If the folder ever needs to be replaced, the upstream archive is `https://act-r.psy.cmu.edu/actr7.x/actr7.x.zip` (112,323,646 bytes on 2026-09-04; single top-level folder `actr7.x`; `Expand-Archive` into the project root reproduces the current layout). Re-run the fingerprint check afterwards, because upstream rebuilds the archive in place without changing the URL.

### 1.3 Step 0b: create the project virtual environment

**All Python work happens in a venv at `G:\VisualSearchModeling\.venv`.** Never `pip install` into the Anaconda base environment, and never rely on packages that happen to be there (the base has numpy, pandas and torch, but the project must not depend on that).

Create it once, from the project root:

```powershell
cd G:\VisualSearchModeling
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

If PowerShell blocks the activation script, either run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` for that session, or skip activation and call the interpreter by full path: `.\.venv\Scripts\python.exe`. In Git Bash the activation is `source .venv/Scripts/activate`.

`requirements.txt` (create it at the project root as part of Step 0b):

```
numpy>=1.26
scipy>=1.13          # Wald/inverse-Gaussian sampling, ex-Gaussian MLE, differential evolution
pandas>=2.2
matplotlib>=3.8
tqdm>=4.66           # batch progress
pytest>=8.0          # tests/
multimatch-gaze>=0.1.0   # MultiMatch scanpath metric (Tier 2/3); PyPI latest is 0.1.3, pulls numpy/pandas/scipy only
```

Deliberately excluded from the base requirements, install only when the phase needs them:

- `torch` (CPU wheel) and `torchvision`, for the Tier 3 DNN priority front end only. Keep them in a separate `requirements-tier3.txt` so the core harness stays light.
- `pysaliency`, for NSS/AUC fixation-map metrics. It pulls heavy dependencies and is only needed for Tier 3; install into the same venv when you reach that phase.

The ACT-R Python interface (`actr7.x/tutorial/python/actr.py`) has no third-party dependencies (stdlib `socket`, `json`, `threading`, `os`, `sys`, `time`, `importlib`, `pathlib`), so it works in the venv with nothing extra installed. The 7.31.4 version tries to upgrade the connection to named pipes only where `os.mkfifo` exists, so on Windows it stays on TCP. Do not copy it into the project; add its directory to `sys.path` at runtime, or install it into the venv in editable form with a one-line `.pth` file:

```powershell
# optional convenience: makes `import actr` work from anywhere in the venv
"G:\VisualSearchModeling\actr7.x\tutorial\python" | Out-File -Encoding ascii .venv\Lib\site-packages\actr_path.pth
```

Every command in this document that starts with `python` assumes the venv is active. Every script under `harness/`, `reference/` and `tests/` must run under it.

### 1.4 Step 0c: `git init` and `.gitignore`

The project is not a git repository yet. Initialise it and create `.gitignore` at the project root before the first commit, so that neither the ~242 MB of vendored ACT-R sources (more once `.fasl` files exist) nor the venv is ever committed:

```
.venv/
actr7.x/
actr7.x.zip
data/human/
data/model/
*.fasl
__pycache__/
*.pyc
```

The PAAV file is small and stays committed as-is (see §12 for the licence note).

### 1.5 Paths used throughout this document

| Item | Path |
|---|---|
| ACT-R sources | `G:\VisualSearchModeling\actr7.x` (7.31.4) |
| Loading ACT-R | `sbcl --load G:/VisualSearchModeling/actr7.x/load-act-r.lisp` (forward slashes; first load compiles all sources, taking several minutes, and writes `.fasl` files next to the sources; later loads are fast). Starts the remote dispatcher on TCP 2650 and writes the address and port to `C:\Users\ITXPC\act-r-address.txt` and `C:\Users\ITXPC\act-r-port-num.txt`. After loading, SBCL sits in its REPL; see §8.2 for how the harness keeps it alive and shuts it down. |
| PAAV reference source | `G:\VisualSearchModeling\paav-visual-module_2014.01.15.lisp` (read only; never loaded) |
| Python venv | `G:\VisualSearchModeling\.venv`; interpreter `G:\VisualSearchModeling\.venv\Scripts\python.exe` |
| ACT-R Python interface | `G:\VisualSearchModeling\actr7.x\tutorial\python\actr.py` (add that directory to `sys.path`) |
| Docs | `actr7.x\docs\reference-manual.pdf` (read "Defining New Modules" and the vision module chapter), `docs\remote.pdf`, `docs\Task_Interfacing.pdf` |
| Examples to read first | `actr7.x\examples\creating-modules\internal\demo-module.lisp` and `all-components-module.lisp`; `actr7.x\examples\vision-module\new_visicon_features.py`, `customize-visicon-features.lisp`, `dynamic-object-creation.lisp`; `actr7.x\extras\emma\emma.lisp` and `readme.txt` |

Everything you write lives in `G:\VisualSearchModeling` outside the `actr7.x` folder.

### 1.6 Sanity check before coding

1. `sbcl --load G:/VisualSearchModeling/actr7.x/load-act-r.lisp` and confirm the ACT-R version banner prints (first run compiles; allow several minutes and expect style warnings, which are normal).
2. Confirm the venv is the active interpreter: with it activated, `python -c "import sys; print(sys.executable)"` must print a path inside `G:\VisualSearchModeling\.venv`, not one inside `anaconda3`.
3. Leave the SBCL session running. From the venv, add `G:\VisualSearchModeling\actr7.x\tutorial\python` to `sys.path` and import `actr7.x\tutorial\python\demo2.py` (it loads `ACT-R:tutorial;unit2;demo2-model.lisp` itself at import; then call `demo2.experiment()`), to confirm the remote link works.
4. Import `actr7.x\examples\vision-module\new_visicon_features.py` under the venv (it loads its own model at import; call `new_visicon_features.example()`) to confirm you can add custom visicon features from Python.

If step 1 fails on a missing library, QuickLisp is not being loaded by that SBCL session; check `C:\Users\ITXPC\.sbclrc`. If step 2 prints an Anaconda path, activation did not take; call `.\.venv\Scripts\python.exe` explicitly instead.

### 1.7 What the vendored PAAV file is for

`paav-visual-module_2014.01.15.lisp` is the ACT-R 6 module described in the report's §2.3. It cannot be loaded into ACT-R 7 (it uses `verify-current-mp` 13 times, `current-device`/`current-device-interface` 17 times, the ACT-R 6 list form of buffer definitions, ACT-R 6 chunk-type inheritance for its feature chunks, and no locks). Do not port it; use it as a worked example of the pieces this project re-implements. It is also the precedent for §4: it defines `(defclass paav-vis-mod (vision-module) ...)` (line 249), then `(undefine-module :vision)` (line 6272) and `(define-module-fct :vision ...)` (line 6275) with the same buffer names plus `abstract-location` and `visual-memory`.

Read these parts (line numbers in the file as copied):

| What | Where | Notes |
|---|---|---|
| Module slots: iconic memory hash, activation tables, acuity and weight defaults | 249–432 | `iconic-memory` 255; acuity a/b per feature 335–351; `top-down-act-w` 0.45 and `bottom-up-act-w` 1.1 at 362–363; `vis-act-s` 364 (default **0.0** in the code, 0.2 in the paper); `persistence-time` 4000 ms at 368; saccade 20 ms + 2 ms/deg at 406–409 |
| Acuity rule | `get-acuity-params` 2804, `is-visible` 2863, `is-visible-text` 2886 | threshold = a·e² − b·e, available iff s + X > threshold with X ~ N(0, v·s) and v = 0 in practice. Defaults: colour a 0.104 b 0.85; shape 0.142/0.96; shading 0.147/0.96; size 0.14/0.96; orientation 0.1/0.601. These coefficients belong to this quadratic form only (see §5.2). |
| Bottom-up map | `calculate-dissimilarity` 2245, `calculate-bottom-up-activation-map` 2272 | binary dissimilarity per feature divided by √(pixel distance); note the paper says 1.1 was chosen to compensate for that √d scaling making BU small |
| Top-down map and decision threshold | `calculate-top-down-activation-map` 2554, `filter-by-top-down-relevancy` 2584 | 1 / 0 / 0.5 similarity rule; the "visual decision threshold" pruning |
| Selection with noise | `get-most-activ-abstr-locs` 2721 (noise added at 2748 via `act-r-noise`) | winner-take-all over iconic memory |
| Iconic memory decay | `remove-invisible-abstract-locations` 3147 | 4 s persistence |
| Saccade landing noise | 4546–4563 | Gaussian with SD = 0.5 × object width/height, `add-gaussian-noise` 2829 borrowed from EMMA |
| Chunk-types and buffers | 5859–5981, 6275–6345 | `feature-location`, `abstract-location`, `visual-object` with `fcolor fshape fshading forient fsize` slots |
| Parameters and defaults | 6346–6525 | the full `define-parameter` list |

---

## 2. Deliverables

```
G:\VisualSearchModeling\
  .venv/                    ; project virtual environment from Step 0b - gitignored
  actr7.x/                  ; vendored ACT-R 7.31.4 - read only, gitignored
  paav-visual-module_2014.01.15.lisp  ; vendored PAAV 0.98e (ACT-R 6, GPL v3) - read only, never loaded
  requirements.txt          ; core Python deps (§1.3)
  requirements-tier3.txt    ; torch + pysaliency, only for the Tier 3 phase
  .gitignore
  gs-vision/
    gs-vision.lisp          ; the module (subclass of vision-module, see §4)
    gs-params.lisp          ; define-parameter forms and defaults (§6)
    gs-priority.lisp        ; priority map computation (§5.3)
    gs-diffuser.lisp        ; selection + identification + quitting engine (§5.4, §5.6)
    gs-eye.lisp             ; FVF, acuity, iconic memory, saccade scheduling (§5.2, §5.5)
    load-gs-vision.lisp     ; loads ACT-R then the above, in order
    README.md               ; how to load, parameters, buffer API, trace events
    CHANGELOG.md
  reference/
    cgs.py                  ; Competitive Guided Search reference simulation (§7.1)
    gs6_sim.py              ; GS6 simulation reference (§7.2)
    gs_hybrid.py            ; Python mirror of THIS module's §5 rules; the fitting target (§7.3)
    test_reference.py       ; asserts cgs.py and gs6_sim.py reproduce published numbers
  harness/
    tasks.py                ; display generators for feature / conjunction / 2-vs-5 (§8.1)
    run_batch.py            ; drives ACT-R over the remote interface, writes CSV (§8.2)
    analyze.py              ; slopes, quantiles, ex-Gaussian, error rates, fixation stats (§8.3)
    fit.py                  ; parameter fitting on gs_hybrid.py, then Lisp confirmation (§8.4)
    metrics.py              ; MultiMatch / ScanMatch / Sequence Score wrappers (§9)
  models/
    search-model.lisp       ; ACT-R model using the new buffer API for the three tasks
    legacy-check-model.lisp ; tutorial unit-3-style model to prove backward compatibility
  data/
    human/                  ; downloaded datasets (not committed if license forbids)
    model/                  ; CSV outputs
  tests/
    test_module_events.lisp ; unit tests for scheduling, IOR, quit, buffer states
    test_backcompat.py      ; runs tutorial units 2 and 3 models with the module loaded (§4)
  docs/
    (existing report + this handoff)
    RESULTS.md              ; final accuracy report (§10)
```

---

## 3. Facts about ACT-R's vision module you must know

All line numbers refer to the vendored `G:\VisualSearchModeling\actr7.x\core-modules\vision.lisp` (ACT-R 7.31.4, vision module 11.1, 4666 lines) unless another file is named. They were read from that exact file. If the fingerprint check in §1.2 fails, find each definition by name, e.g. `Select-String -Path actr7.x\core-modules\vision.lisp -Pattern '^\(defmethod find-location'`.

- The module is a CLOS class `vision-module` (subclass of `attn-module`), defined at line 1292 (`:version-string "11.1"` at 1345). Its instance is created by `create-vision-module` (line 3064) and reset by `reset-vision-module` (line 3128) together with `dont-query-vis-loc` (3122). The `define-module-fct :vision ...` form starts at line 3437; it declares the buffers `visual-location` (request params `:attended :nearest :center`, query `attended`, status function `visual-location-status`) and `visual` (queries `scene-change-value scene-change modality preparation execution processor last-command`, status function `visual-buffer-status`), and the parameters whose defaults are listed in the report's header paragraph and §2.1 (`:visual-attention-latency 0.085`, `:visual-num-finsts 4`, `:visual-finst-span 3.0`, `:visual-onset-span 0.5`, `:visual-movement-tolerance 0.5`, `:delete-visicon-chunks t`, `:auto-attend nil`, `:visual-encoding-hook nil`). Its keyword arguments are `:creation 'create-vision-module :reset '(reset-vision-module dont-query-vis-loc) :query 'query-vision-module :request 'pm-module-request :params 'params-vision-module :warning 'warn-vision`.
- Requests arrive through `pm-module-request` (line 3245 for the vision method), which dispatches to generic functions. The ones you override:
  - `find-location (vis-mod chunk-spec)` at line 2921. Current behaviour: `find-current-locs-with-spec` filters the visicon, then `(random-item (objs-max-val it 'chunk-visual-tstamp))` picks the newest, breaking ties randomly, and `schedule-set-buffer-chunk 'visual-location ... 0 :time-in-ms t :priority 10` puts it in the buffer at **0 ms**.
  - `move-attention (vis-mod &key location scale)` at line 2992. Calls the `:visual-encoding-hook` (if set) at line 3022 with four arguments `(old-xyz new-xyz location scale)` where the xyz values are lists; hook returns `nil` (use the 85 ms default), a number (seconds to encode), or anything else (hook takes responsibility and must later call `(schedule-encoding-complete delay)`, line 3043). Then `change-state vis-mod :exec 'BUSY :proc 'BUSY`.
  - `encoding-complete (vis-mod loc position scale &key requested)` at line 2412 builds the object chunk via `get-obj-at-location` (line 2472) and sets the `visual` buffer.
- Finsts: `check-finsts` (2247), `feat-attended (loc vis-mod)` (2269), `assign-finst` (2327). Parameters `:visual-num-finsts 4`, `:visual-finst-span 3.0`.
- Visicon access: `visicon-chunks (vis-mod &optional sorted)` at line 1811 returns the visicon chunks; each has per-chunk properties `chunk-visicon-entry` (the stable identity of the feature, declared by `extend-chunks` at line 1378; key your iconic memory on this), `chunk-visual-tstamp`, `chunk-visual-obj-spec`, and position slots (default `screen-x screen-y distance`, configurable via `vis-loc-slots`). The visicon is protected by `visicon-lock` (a recursive lock); use `(bt:with-recursive-lock-held ((visicon-lock vis-mod)) ...)` when reading it. Marker state (`clof`, `current-marker`, `currently-attended`, tracking, failure flags) uses `marker-lock`; `vis-loc-slots` uses the non-recursive `vis-loc-lock`; parameters use `param-lock`.
- Degrees of visual angle: the conversion parameters `:pixels-per-inch 72.0` and `:viewing-distance 15.0` (inches) are **owned by the device interface**, not the vision module (vision declares them `:owner nil`). The helpers are `pm-pixels-to-angle (pixels &optional dist)` and `pm-angle-to-pixels (angle &optional dist)` in `actr7.x/framework/device-interface.lisp` lines 763 and 768; use them rather than reimplementing. There is no `xy-to-dmo` in ACT-R 7. With the defaults 1 px = 0.053°, so 12° ≈ 226 px.
- Time: `schedule-event-relative delay fn ...` takes seconds unless `:time-in-ms t`. Always pass `:module :vision :destination :vision` for module-internal events so the trace attributes them correctly. Use `randomize-time-ms` only where ACT-R's uniform randomisation is wanted; for Wald/Gaussian/logistic noise use your own sampler seeded from `act-r-random` so `(sgp :seed (n m))` reproduces runs. `act-r-noise s` is logistic with scale `s` (SD = s·π/√3); EMMA's `add-gaussian-noise (x stddev)` shows how to get a given SD out of it.
- Buffer failure: `set-buffer-failure` (framework/buffers.lisp) **refuses to set the failure flag while a chunk is in the buffer**, and `set-buffer-chunk` clears the flag. A failed search therefore ends with the buffer empty plus `state error`, exactly like a retrieval failure; it cannot also put a chunk in the buffer (§5.6).
- EMMA (`extras/emma/emma.lisp`, version 8.2a3) is a *separate* module named `:emma` (defined at line 885) that installs `emma-attention-hook (current-loc new-loc feat-chunk scale)` (line 502) as the encoding hook. It exposes `register-feature-frequency` (741), `set-eye-location` (750), `current-eye-location` (762), and signals `new-eye-location` (x y z). Saccade timing: preparation cost `:saccade-feat-time 0.050` per changed feature (style/distance/direction, 0 to 150 ms; distances match within 2°, directions within 90°), non-labile `:saccade-init-time 0.050`, execution `:saccade-base-time 0.020` + `:eye-saccade-rate 0.002` s/deg, landing noise Gaussian with SD 0.1 × saccade distance in pixels (implemented as logistic noise of matching SD). Encoding time `K·(−ln f)·e^{k·ε}` with `:visual-encoding-factor` K = 0.006, `:visual-encoding-exponent` k = 0.4, default frequency `:vis-obj-freq` f = 0.1 (so 14 ms at ε = 0). EMMA adds a buffer named `emma` for tracing only. Its `readme.txt` lists the differences from the 2001 paper.
- `undefine-module` (macro; `undefine-module-fct` at framework/modules.lisp line 652) prints "Cannot delete a module when there are models defined." and returns without doing anything if any model exists. Do it immediately after ACT-R loads, before any `clear-all`/`define-model`.
- `require-extra` is a macro in `load-act-r.lisp` (line 844); `(require-extra "emma")` is the documented way to load EMMA.
- Python-side API (`tutorial/python/actr.py`): `add_visicon_features(*feats)`, `modify_visicon_features`, `delete_visicon_features`, `delete_all_visicon_features`, `add_command`, `monitor_command`, `run(time)`, `run_n_events`, `run_until_condition`, `reset`, `load_act_r_model`, `load_act_r_code`, `set_parameter_value`, `schedule_event_relative`, `call_command`, `print_visicon`, `get_time`. Custom visicon slots are allowed if declared in a chunk-type (see `examples/vision-module/customize-visicon-features.lisp`).

---

## 4. Integration strategy: subclass, do not fork

Rationale: the motor module, AGI devices, Environment tracing and EMMA all reach into `vision-module` internals. A subclass inherits all of that; a fork would have to track upstream changes. PAAV did exactly this in ACT-R 6 (`paav-vis-mod` subclass, `undefine-module :vision`, `define-module-fct :vision` with the same buffer names; §1.7), so the route is known to work with ACT-R's module system. The report's §3.4 and §7 still say "fork"; this section supersedes them.

```lisp
;;; gs-vision.lisp (skeleton)
(defclass gs-vision-module (vision-module)
  ((eye-xyz        :accessor eye-xyz        :initform (vector 0 0 0))   ; current gaze, pixels
   (iconic         :accessor iconic         :initform (make-hash-table :test 'equal)) ; visicon-entry -> iconic-entry
   (template       :accessor template       :initform nil)   ; guiding template plist (channels)
   (priority       :accessor priority       :initform (make-hash-table :test 'equal)) ; visicon-entry -> priority value
   (rejected       :accessor rejected       :initform nil)   ; ring buffer of rejected entries (IOR)
   (diffuser       :accessor diffuser       :initform nil)   ; list of in-flight items
   (quit-weight    :accessor quit-weight    :initform 0.0)
   (quit-threshold :accessor quit-threshold :initform nil)   ; adaptive, persists across trials
   (feedback-log   :accessor feedback-log   :initform nil)   ; last :gs-feedback-window outcomes, for prevalence
   (history        :accessor history        :initform (make-hash-table :test 'equal)) ; feature value -> priming trace
   (search-active  :accessor search-active  :initform nil)
   (fixation-log   :accessor fixation-log   :initform nil)
   (gs-lock        :accessor gs-lock        :initform (bt:make-recursive-lock "gs-vision")) ; protects all of the above
   ;; parameter mirrors (see gs-params.lisp)
   ...))

(defun create-gs-vision-module (model-name)
  ;; Mirror create-vision-module (vision.lisp line 3064) exactly, but make-instance 'gs-vision-module.
  ...)

(defun gs-vision-params (vis-mod param)
  ;; Handle new :gs-* parameters; delegate everything else to params-vision-module.
  ...)

;; Redefine the module with the same name and buffers so all existing code keeps working.
(undefine-module :vision)
(define-module-fct :vision
  (list (define-buffer-fct 'visual-location :request-params (list :attended :nearest :center :guided)
                           :queries '(attended) :status-fn 'visual-location-status)
        (define-buffer-fct 'visual
          :queries '(scene-change-value scene-change modality preparation execution processor last-command
                     search-result)
          :status-fn 'visual-buffer-status))
  (append (original-vision-parameter-list) (gs-parameter-list))   ; copy the list from vision.lisp lines 3437-3527
  :version "GS-0.1" :documentation "Guided-search vision module (GS6 + CGS + PAAV + EMMA)"
  :creation 'create-gs-vision-module
  :reset '(reset-gs-vision-module dont-query-vis-loc)  ; call reset-vision-module inside, then clear gs state
  :query 'gs-query-vision-module                       ; delegate to query-vision-module for existing queries
  :request 'pm-module-request
  :params 'gs-vision-params
  :warning 'warn-vision)

;;; Override behaviour by CLOS method specialisation:
(defmethod find-location ((vis-mod gs-vision-module) chunk-spec) ...)   ; §5.3 guided selection
(defmethod move-attention ((vis-mod gs-vision-module) &key location scale) ...) ; §5.5 saccade + encoding
(defmethod encoding-complete ((vis-mod gs-vision-module) loc position scale &key (requested t)) ...)
```

Two hard requirements:

1. **Backward compatibility, in both modes.** With the default `:gs-enabled t`, any request that does not use the new API (no `:guided t`, no `gs-search`/`gs-feedback` chunk) must go straight to `(call-next-method)` so tutorial models produce identical traces. With `:gs-enabled nil` the new API is refused with a warning and everything else is the default module. `tests/test_backcompat.py` runs tutorial units 2 and 3 under both settings and compares the traces with the stock module's traces; they must be identical (trace lines do not carry module versions, so no exception is needed).
2. **Load order.** `gs-vision/load-gs-vision.lisp` is the single entry point and must load ACT-R first, then EMMA, then the gs files, then call `undefine-module` before any model exists:

```lisp
;;; gs-vision/load-gs-vision.lisp  -- start SBCL with: sbcl --load <this file>
(defvar *gs-root* (namestring (make-pathname :name nil :type nil
                                             :defaults (or *load-truename* *default-pathname-defaults*))))
(load (merge-pathnames "../actr7.x/load-act-r.lisp" *gs-root*))
(require-extra "emma")
(dolist (f '("gs-params" "gs-priority" "gs-diffuser" "gs-eye" "gs-vision"))
  (load (merge-pathnames (format nil "~a.lisp" f) *gs-root*)))
;; gs-vision.lisp performs (undefine-module :vision) and re-defines it; this must
;; happen here, before any clear-all / define-model.
;; Remote command so the Python harness can stop this Lisp cleanly (§8.2):
(add-act-r-command "gs-quit-lisp" (lambda () (sb-ext:exit :abort t)) "Exit SBCL. No params.")
```

Models then set `(sgp :emma t :gs-enabled t)`. `*gs-root*` is derived from the load file's own location, so nothing is hard-coded.

Fallback if `undefine-module :vision` proves too invasive: implement selection in a companion module (as EMMA does) that sets `:visual-encoding-hook` and adds a `gs-search` buffer; in that case `find-location` is not overridden and the `+visual-location> ... :guided t` request is replaced by a `+gs-search>` request. Prefer the subclass route; document the choice in `CHANGELOG.md`.

---

## 5. Functional specification

### 5.1 Extended visicon features and the two classes of feature

Continue to use `add-visicon-features`. Recognised slots, all optional, in addition to the standard ones (`screen-x screen-y distance kind color value height width size`):

| Slot | Type | Meaning |
|---|---|---|
| `hue` | degrees 0–360 | continuous colour; `color` symbol still used for template matching if `hue` absent |
| `orient` | degrees −90..90 | orientation |
| `lum` | 0–1 | luminance |
| `shape` | symbol | categorical shape / configuration (e.g. `two`, `five`, `t`, `l`) |
| `salience` | number | externally computed bottom-up salience (e.g. from an Itti–Koch or DNN front end); if present it replaces the internal BU computation |
| `prior` | number 0–1 | scene prior for this item (optional) |

Declare these in a chunk-type `(chunk-type (gs-feature (:include visual-location)) hue orient lum shape salience prior)` in the module's creation/reset function.

**Guiding versus identification-only features.** Guided Search's central claim is that only a small set of preattentive attributes can guide selection; spatial configuration (the "2" versus "5" of the benchmark) cannot. The module therefore keeps two classes:

- *Guiding features* (parameter `:gs-guiding-features`, default `(color orient size lum)`): enter iconic memory subject to acuity (§5.2), enter the bottom-up and top-down terms of the priority map (§5.3), and may be used in `:guided t` location requests.
- *Identification-only features* (everything else, in particular `shape` and `value`): never contribute to the priority map, even when available. They are compared only when an item is inside the diffuser (§5.4), and only if available at the current eccentricity; otherwise the item must be foveated (§5.5).

This is what makes 2-vs-5 inefficient and feature search efficient with one set of rules.

Categorical channels for guiding features (Guided Search 2 rule, simplified): colour channels = red, green, blue, yellow, black, white (assign from `hue`/`color`); orientation channels = steep (|θ| < 22.5°), shallow (|θ| > 67.5°), left (−67.5..−22.5), right (22.5..67.5); size channels = small/medium/large by terciles of the current display; luminance channels = dark/mid/bright by thirds. An item's channel response is 1 for its channel, 0 otherwise, with a soft boundary of ±10° for orientation (linear ramp) so that near-boundary items partially activate two channels. (GS2 proper lets an item activate a steep/shallow channel and a left/right channel at the same time; the exclusive binning here is a simplification, recorded as such.)

### 5.2 Acuity, functional visual field, iconic memory

For each visicon item at eccentricity `e` (degrees from current `eye-xyz`) and angular size `s`, where `s` is the mean of the item's width and height in degrees when `width`/`height` are given, else √`size` (the `size` slot is in deg²):

- Feature `f` of the item is *available* with probability `P = P(s > N(θ_f · e, σ))`, the EPIC availability function of Kieras & Meyer (2026). Defaults `:gs-acuity-theta (color 0.10 orient 0.20 shape 0.40 size 0.20 lum 0.10)` and `:gs-acuity-sigma 0.5`. The colour, orientation and shape values are the representative θ that Kieras & Meyer used for the Wolfe et al. (2010) tasks; size and luminance are provisional. **Do not mix in PAAV's `a`/`b` coefficients** (§1.7): they belong to a quadratic deterministic threshold `a·e² − b·e` and are not interchangeable with θ.
- The availability draw is made once per fixation per item per feature. Available features are written into the iconic-memory entry for that item with timestamp = now. Entries persist `:gs-iconic-span 4.0` s after they were last available (PAAV's 4 s), then are dropped.
- Two radii, both in degrees around `eye-xyz`: `:gs-attn-fvf 8.0` (items eligible for covert selection; Wu & Wolfe 2022 estimate 8°, plausible range 5–10°) and `:gs-explore-fvf 12.0` (candidates for the next saccade). Resolution is not a radius; it is handled per feature by the acuity rule above.
- Items outside `:gs-explore-fvf` still get priority values from whatever guiding features are available (typically only coarse colour/size), which is how peripheral guidance works.

### 5.3 Priority map

Computed for every item in iconic memory whenever a search starts, a saccade lands, or the visicon changes. Only guiding features enter it (§5.1):

```
P_i = w_BU·BU_i + w_TD·TD_i + w_H·H_i + w_V·V_i + w_S·S_i − w_E·e_i + ε_i
```

Items in the IOR ring buffer (§5.4) and items currently in the diffuser are simply excluded from selection; they keep a priority value for logging but no penalty term is needed.

- **BU_i** (bottom-up): for each guiding feature dimension k and each other item j among the 8 nearest neighbours (a deviation from GS2's 5×5 neighbourhood, chosen so displays of any density behave alike), `Δ_ijk = |channel_ik − channel_jk|` (0 or 1 for categorical, ramped near boundaries). `BU_i = (1/|N_i|) Σ_j Σ_k Δ_ijk / max(1, d_ij)` where `d_ij` is distance in degrees. If the `salience` slot is present, use it instead (scaled to the same range by dividing by the display max).
- **TD_i** (top-down): the guiding template is a plist of channels such as `(:color red :orient steep)`, built from the request (§5.7) and restricted to guiding features. For each template feature k: `TD_ik = 1` if the item's channel matches, `0` if it mismatches, `0.5` if the feature is not in iconic memory for this item (PAAV's uncertainty rule). `TD_i = Σ_k TD_ik / K`. **If the template contains no guiding feature** (2-vs-5: the template is `shape two`), `TD_i = 1` for every item, i.e. guidance is absent and all items are equal candidates.
- **H_i** (history/priming): each guiding feature value carries a trace `h_v` that is incremented by 1 whenever a target with that value is found and decays as `h_v ← h_v · exp(−Δt / τ_H)` with `τ_H = 10` s. `H_i = Σ_k h_{value_ik}` over the item's available features, normalised by the max trace in the display.
- **V_i** (value): default 0; hook `:gs-value-hook` lets a model supply a function `(lambda (chunk) number)`.
- **S_i** (scene prior): the `prior` slot, default 0.
- **e_i**: eccentricity in degrees, weight `w_E = 0.02` per degree (proximity preference; refit).
- **ε_i**: logistic noise with scale `:gs-noise 0.2` (PAAV's paper value), sampled via `act-r-noise`.

Normalise BU and TD to [0,1] over the display before weighting so the weights are comparable across set sizes. Because of that normalisation **PAAV's weights (1.1 bottom-up, 0.45 top-down) do not transfer**: PAAV chose the larger BU weight to compensate for its √distance scaling making raw BU small. Provisional defaults here are `w_TD 1.0, w_BU 0.5, w_H 0.3, w_V 0.0, w_S 1.0`; Phase 4 fits `w_BU` and `w_TD`.

### 5.4 Covert selection and identification (GS6 + CGS)

State: a diffuser holding up to `:gs-diffuser-capacity` (default 5) in-flight items.

Loop, driven by scheduled module events (not by productions):

1. **Select** every `:gs-select-interval` (0.050 s) while a search is active and the diffuser has a free slot: among iconic items not in the IOR ring, not already in the diffuser, and with eccentricity ≤ `:gs-attn-fvf`, pick with Luce choice `p_i = w_i / Σ_j w_j` where `w_i = exp(β · (P_i − P̄))`, `P̄` = mean priority of the eligible items, `:gs-choice-beta 4.0`. Centring on `P̄` keeps a typical distractor's weight near 1, which is the scale CGS's quit weight (§5.6) assumes; β → ∞ gives GS2 winner-take-all, and CGS's target weight `w_T` corresponds to `exp(β·(P_target − P̄))`. If no eligible item exists inside the attentional FVF, trigger §5.5.
2. **Identify**: on entering the diffuser, the item's completion time is drawn from a Wald (inverse Gaussian) with drift `:gs-id-drift` μ (0.25) and threshold `:gs-id-threshold` θ (0.03), noise σ fixed at 0.1, i.e. mean θ/μ = 120 ms, shape θ²/σ². Schedule an `item-decision` event at that time. Identification is error-free for the target/distractor decision (CGS); misses are produced by the quitting rule and by acuity, and false alarms by the response stage (§7.1's motor error), not by mis-identification.
   **Slope arithmetic to keep in mind**: CGS fitted μ and θ under a strictly serial model where RT is the sum of identification times. In this pipeline the diffuser is never full (5 × 50 ms > 120 ms), so throughput is one item per `:gs-select-interval` and the slope is set by the selection interval and the sampling/memory rules, not by the Wald mean. With the defaults expect roughly 25 ms/item target-present and 50–70 ms/item target-absent for unguided search, i.e. GS6-typical values, not the 43/95 of 2-vs-5. Reproducing 2-vs-5 needs a slower interval or a smaller capacity for that task; `reference/gs_hybrid.py` (§7.3) is where this is established before any Lisp is written.
3. **On item-decision**: compare the item to the *full* target template (guiding and identification-only features) using the features available in iconic memory.
   - All template features available and all match → **hit**: schedule `encoding-complete` for that location (EMMA encoding time if `:emma t`, else 85 ms) and finish the search.
   - All template features available and any mismatch → **rejection**: push the entry onto the IOR ring buffer, increment `quit-weight` by `:gs-quit-delta` (0.02), and evaluate the quit rule (§5.6).
   - Some template feature unavailable at this eccentricity → **pending foveation**: the item stays in the diffuser (it does not free its slot), a saccade to it is requested through §5.5, and its `item-decision` is rescheduled for 50 ms after landing. After landing the availability draw is repeated; if the feature is still unavailable (rare inside the fovea) the item is rejected as above.
4. **Trace events** (all with `:output 'medium` so they show in the standard trace): `GS-SELECT item priority`, `GS-DECIDE item hit|reject|pending`, `GS-SACCADE from to amplitude`, `GS-FIXATE x y`, `GS-QUIT reason`.

### 5.5 Overt eye movements

Triggered when no eligible item remains inside the attentional FVF, when the current fixation has lasted longer than `:gs-max-fixation` (0.4 s), or when an item's decision is pending foveation (§5.4).

- Saccade target: a pending-foveation item if there is one (oldest first); otherwise the item with the highest `P_i` inside `:gs-explore-fvf` that is neither in the IOR ring nor in the diffuser. If none, the highest-priority such item anywhere in iconic memory; if still none, quit (§5.6).
- Timing and landing: reuse EMMA. Call EMMA's preparation/execution scheduling (see `emma-attention-hook` in `extras/emma/emma.lisp`, line 502, and how it calls `schedule-encoding-complete`). Do not copy the arithmetic; call the same functions or, if they are not separable, refactor a small wrapper inside `gs-eye.lisp` that reproduces EMMA's numbers exactly (0 to 150 ms preparation by features, 50 ms non-labile, 20 ms + 2 ms/deg execution, landing noise SD 0.1 × amplitude).
- On landing: update `eye-xyz`, call `set-eye-location` so EMMA's marker and the Environment eye spot agree, redraw acuity availability (§5.2), recompute the priority map (§5.3), append to `fixation-log` (time, x, y, duration of the previous fixation), and resume the selection loop. Items already in the diffuser keep their remaining time (EMMA's "remaining proportion" rule can be applied if their eccentricity changed).
- Legacy `move-attention` requests without an active search behave exactly as before (call-next-method).

### 5.6 Quitting

Two mechanisms, both on by default (`stop both`; see §5.7):

- **CGS quit unit**: after each rejection, `p_quit = quit-weight / (Σ_eligible w_i + quit-weight)` with the centred weights of §5.4 step 1; draw and quit with that probability. Quit-weight resets to 0 at search start.
- **GS6 adaptive threshold** (persists across trials within a model run): maintain `quit-threshold` QT in units of rejections. If the number of rejections in this search ≥ QT, quit. Initial QT = `:gs-qt-init` (1.0) × N_eff, where the **effective set size N_eff** is the number of items in iconic memory with `TD_i ≥ 0.5` at search start (conjunction: every item, since each distractor shares one of two guiding features; feature search: the target alone, or zero on absent trials, so the search quits after its first rejection; 2-vs-5: every item, because an empty guiding template gives `TD_i = 1`). δ = `:gs-qt-step` (0.05) × N_eff. After each trial the model (not the module) reports the outcome via a `+visual> isa gs-feedback outcome hit|miss|fa|tn` request and the module updates: TN → QT −= δ; miss → QT += δ / (`:gs-error-goal` 0.08 × prevalence × 2). Prevalence is the proportion of target-present feedbacks (hits + misses) among the last `:gs-feedback-window` (50) feedbacks, and is taken as 0.5 until at least 10 feedbacks exist. Hits and false alarms update the priming traces (§5.3) only. (GS6 also moves an identification start point on hits and false alarms; that mechanism controls identification false alarms, which this design does not model because identification is error-free. It is listed as an option in §12.)
- Note that in the GS6 simulation the only memory is the five items inside the diffuser; rejected items can be reselected. This module adds the `:gs-memory` IOR ring on top, so its TA:TP slope ratio will sit below GS6's ≈3.

On quit: the search ends with the `visual` buffer **empty**, `(set-buffer-failure 'visual)`, module state `error`, the query `search-result failed` true, and the `GS-QUIT` trace event. The counts (fixations, rejections, elapsed time, quit reason) are available through the `gs-search-stats` command (§6), not through the buffer.

### 5.7 Buffer API (what models write)

```lisp
;; Guided location request: returns the highest-priority matching location after one
;; module-internal selection step (costs one select interval, not 0 ms).
;; With :guided t the slot values are TEMPLATE CONSTRAINTS on channels, not equality tests on
;; visicon slots: a symbol names a channel (red, steep, small ...), a number is mapped to the
;; channel it falls in, and only guiding features are honoured. Standard slots such as
;; screen-x / :nearest still filter exactly as they do today.
+visual-location> isa visual-location color red orient steep :guided t

;; Full search: module runs selection/identification/saccades/quitting internally.
;; Returns the target object chunk in the visual buffer, or state error with an empty buffer.
+visual> isa gs-search color red orient steep       ; slots = target template (guiding + identification features)
                     guide (color)                  ; optional: restrict guidance to these template features
                     stop both                      ; adaptive | cgs | both (default both)
+visual> isa gs-search shape two                    ; 2-vs-5: no guiding feature, so unguided search

;; Feedback after the model has responded (needed for adaptive quitting and priming).
+visual> isa gs-feedback outcome hit                ; hit | miss | fa | tn

;; Queries
?visual> state busy / free / error
?visual> search-result found / failed / none        ; last gs-search outcome (none = no search yet)
```

Numbers about the last search (fixation count, rejections, elapsed ms, quit reason) are not buffer queries, because ACT-R queries test symbol equality; get them from `gs-search-stats` (§6) or from the trace events. Everything the default module supports keeps working unchanged.

---

## 6. Parameters (all `define-parameter`, owner :vision unless noted)

| Name | Default | Notes |
|---|---|---|
| `:gs-enabled` | t | nil → new API refused, module identical to default |
| `:gs-guiding-features` | `(color orient size lum)` | §5.1; everything else is identification-only |
| `:gs-select-interval` | 0.050 | s; sets slopes in the pipeline (§5.4) |
| `:gs-diffuser-capacity` | 5 | |
| `:gs-choice-beta` | 4.0 | Luce temperature on centred priorities |
| `:gs-id-drift` | 0.25 | Wald μ |
| `:gs-id-threshold` | 0.03 | Wald θ; σ fixed 0.1 |
| `:gs-quit-delta` | 0.02 | CGS Δw_quit |
| `:gs-memory` | 4 | IOR ring size |
| `:gs-attn-fvf` | 8.0 | deg (Wu & Wolfe 2022) |
| `:gs-explore-fvf` | 12.0 | deg |
| `:gs-max-fixation` | 0.4 | s |
| `:gs-iconic-span` | 4.0 | s |
| `:gs-acuity-theta` | `(color 0.10 orient 0.20 shape 0.40 size 0.20 lum 0.10)` | EPIC form, §5.2 |
| `:gs-acuity-sigma` | 0.5 | |
| `:gs-w-bu`, `:gs-w-td`, `:gs-w-h`, `:gs-w-v`, `:gs-w-s`, `:gs-w-e` | 0.5, 1.0, 0.3, 0, 1.0, 0.02 | provisional (§5.3) |
| `:gs-noise` | 0.2 | logistic scale |
| `:gs-priming-tau` | 10.0 | s |
| `:gs-qt-init`, `:gs-qt-step`, `:gs-error-goal` | 1.0, 0.05, 0.08 | GS6 |
| `:gs-feedback-window` | 50 | feedbacks used for the prevalence estimate |
| `:gs-value-hook` | nil | function or remote command name |
| `:gs-log-fixations` | t | keeps `fixation-log`; expose via command `gs-fixation-log` |

Add dispatcher commands `gs-fixation-log` (returns list of `(time x y dur)`) and `gs-search-stats` (returns `(fixations rejections elapsed-ms quit-reason)` for the last search) so Python can pull them after each trial.

---

## 7. Reference implementations in Python (do these first)

Purpose: have known-good targets before touching Lisp, and a fast fitting tool.

### 7.1 `reference/cgs.py` — Competitive Guided Search

Per trial with set size N, target present/absent:

1. Weights: distractors w = 1, target w = w_T.
2. Loop: choose item i with p_i = w_i / (Σ w + w_quit); with probability w_quit / (Σ w + w_quit) quit instead (respond absent).
3. Identification time ~ InverseGaussian(mean = θ/μ, shape = θ²/σ²), σ = 0.1. If item is target → respond present. Else set w_i = 0, w_quit += Δw.
4. RT = Σ identification times + T_min(yes|no) + Exponential(rate c). With probability m the response is flipped (motor error).

Published fits to reproduce (Moran et al. 2013, averaged observer, seconds; **these values were transcribed from memory and could not be re-checked against the paper during the 2026-09-04 review, so verify them against the paper's parameter table before asserting them in tests**): 2-vs-5: w_T 1.51, μ 0.252, θ 0.029, Δw 0.019, T_min 0.413/0.410, c 11.8, m 0.012 → conjunction w_T 4.96, Δw 0.162; feature w_T 600, Δw 870. `test_reference.py` must show: 2-vs-5 mean slopes ≈ 43 ms/item TP and ≈ 95 ms/item TA; feature slopes ≈ 1 ms/item; miss rate rising with set size, FA < 2%.

### 7.2 `reference/gs6_sim.py` — GS6 simulation

Reproduce Wolfe (2021), "Simulation specifics": diffuser capacity 5; a new item selected every 50 ms if there is space; the only memory is the items currently in the diffuser (a selected item cannot be reselected, all others can); diffuser updated every 10 ms; drift = 1/20 of distance to bound (200 ms noiseless); noise SD = 2.5 × drift; quitting diffuser starts after the first identification; QT ∝ set size; TN → QT down one step; miss → QT up by (step)/(error goal), further scaled by prevalence; hit → identification start point up one step; FA → start point down 16 steps; 10,000 trials × prevalence {.1,.3,.5,.7,.9} × set sizes {5,10,15,20}, error goal 8%. Expected: linear RT×N, TA:TP slope ratio ≈ 3, misses ≈ 8% rising with set size, positive skew, prevalence criterion shift. The exact prevalence scaling and any zROC target are not spelled out in the paper text; take them from the MATLAB at https://osf.io/9n4hf/ (project "Guided Search 6.0") and record what you find in the docstring.

### 7.3 `reference/gs_hybrid.py` — this module, in Python

A trial-level simulation of §5.2–§5.6 exactly as specified here (same parameter names and defaults, same channel rules, same centred Luce weights, same IOR ring, same quit rules, EMMA saccade timing, EPIC acuity), run on the displays from `harness/tasks.py`. It exists because neither CGS nor the GS6 simulation is the architecture being built, so neither predicts what the defaults will do. Use it to (a) find `:gs-select-interval`/`:gs-diffuser-capacity`/β settings that give the Tier 1 slopes per task before writing Lisp, (b) serve as the fitting target in §8.4, and (c) check the Lisp module against it at the end of Phase 4 (the same seed policy is not possible across languages, so compare cell means and quantiles over ≥ 2,000 trials per cell).

---

## 8. Harness

### 8.1 `harness/tasks.py`

Generate displays matching Wolfe, Palmer & Horowitz (2010):

- Feature: red vertical bar among green vertical bars.
- Conjunction: red vertical among green vertical and red horizontal.
- Spatial configuration: digital "2" among digital "5"s. Represent as `shape two` versus `shape five` with identical colour, orientation and size channels, so only identification-only comparison distinguishes them (§5.1).
- Geometry: a 22.5° × 22.5° field divided into an invisible 5 × 5 grid of 4.5° cells; each item is placed at a random position inside its cell. Bars are 1° × 3.5°; the digits are 1.5° × 2.7° character-like shapes. Set sizes 3, 6, 12, 18; 50% target present. Convert degrees to pixels with `pm-angle-to-pixels` under the default 72 ppi / 15 in (1 px ≈ 0.053°), or set `:pixels-per-inch`/`:viewing-distance` and convert consistently in Python. Return a list of `add_visicon_features` argument lists plus ground truth.

### 8.2 `harness/run_batch.py`

- Start Lisp itself, then connect via `actr.py`: `subprocess.Popen(["sbcl", "--non-interactive", "--load", "G:/VisualSearchModeling/gs-vision/load-gs-vision.lisp", "--eval", "(loop (sleep 1))"])`; the `(loop (sleep 1))` keeps the process alive after loading, and `actr.call_command("gs-quit-lisp")` (defined in `load-gs-vision.lisp`, §4) ends it. Wait for `act-r-port-num.txt` to be rewritten before importing `actr`. Loading `load-gs-vision.lisp` into an already running ACT-R via `load_act_r_code` only works if no model is defined, so do not rely on it.
- Per trial: `actr.reset()` only when needed (adaptive QT, priming and the prevalence window must persist, so prefer `delete_all_visicon_features` + `add_visicon_features` and a goal chunk reset instead of a full reset); `monitor_command("output-key", handler)`; run until response or 6 s timeout; call `gs-search-stats` and `gs-fixation-log`.
- Output `data/model/<task>_<paramset>.csv` with columns: `subject_seed, task, trial, set_size, target_present, response, correct, rt_ms, n_fixations, n_rejected, quit_reason, param_hash` and a second file with fixations `(trial, idx, t, x, y, dur)`.
- Batch size: 2,000 trials per cell for the Phase 4 confirmation runs, 500 for quick checks. Use `:seed` per simulated subject.

### 8.3 `harness/analyze.py`

- Slopes/intercepts by task × presence (least squares on cell means); TA:TP ratio.
- RT quantiles (.1,.3,.5,.7,.9) per cell; ex-Gaussian μ, σ, τ per cell (use `scipy.optimize` MLE).
- Miss and FA rates by set size.
- Fixation stats: count by set size and presence, duration distribution, saccade amplitude, refixation rate (return to an item within `:gs-memory` rejections).
- Plots: RT × set size with human overlay; quantile-probability plots; fixation-count histograms.

### 8.4 `harness/fit.py`

Differential evolution (scipy) over `{β, μ, θ, Δw, w_TD, w_BU, noise, memory, select-interval}` minimising the sum over 24 cells (3 tasks × 4 set sizes × presence) of quantile RMSE plus 10 × |error-rate difference|, **run against `reference/gs_hybrid.py`**, not against the Lisp module: one evaluation is 24 × 2,000 trials, and DE needs thousands of evaluations, which is hours in numpy and months over the JSON-RPC link. Then run the Lisp module once per task at the fitted values (§8.2, 2,000 trials per cell) and report both the Python and the Lisp misfit per cell like Moran et al. (mean quantile misfit in ms). If the two disagree by more than the Monte Carlo error, the Lisp port is wrong, not the fit.

---

## 9. Validation data and metrics

| Tier | Dataset | Get it from | What to compare | Acceptance target |
|---|---|---|---|---|
| 1 | Wolfe, Palmer & Horowitz 2010 (feature, conjunction, 2-vs-5); paper text in PMC2891283 | https://search.bwh.harvard.edu/new/data_set_files.html (server unreachable on 2026-09-04, connection timeout; if still down, email jwolfe@bwh.harvard.edu) | slopes, quantiles, ex-Gaussian, errors | slope error ≤ 5 ms/item; mean quantile misfit ≤ 40 ms (CGS: 35/22/5); miss rate within 3 points |
| 1 | Adam, Patel, Rangan & Serences 2021, *J Cognition* 4(1):34 (8 sub-experiments, 190 participants, >210,000 trials) | https://osf.io/u7wvy/ (CC BY 4.0) | RT/accuracy, singleton capture cost | capture cost sign and magnitude within 50% |
| 2 | Wu & Wolfe 2022 FVF eye tracking, *Vision Research* 190:107965 (T among L and colour × orientation conjunction; 18 observers in Exp 1) | https://osf.io/vzg28/ (OSF project "Useful Field of View (UFOV)"; preregistration plus data files) | fixations/trial, fixation duration, saccade amplitude | fixation count within 1 per trial; MultiMatch vector/position ≥ human–human mean − 0.05 |
| 3 | COCO-Search18 via ViSioNS | https://github.com/NeuroLIAA/visions ; https://sites.google.com/view/cocosearch/ (non-commercial) | Sequence Score, MultiMatch, TFP-AUC, cNSS | report only; requires an external priority front end (`salience`/`prior` slots) |
| 4 | VSGUI10K | https://osf.io/hmg9b/ (CC BY 4.0) | search time, fixations on GUIs | report only |

Metrics code: use `multimatch-gaze` (already in `requirements.txt`) for MultiMatch, implement ScanMatch and Sequence Score in `harness/metrics.py` following Chen et al. 2021 / the `cvlab-stonybrook/Scanpath_Prediction` repo, and `pysaliency` for NSS/AUC where fixation maps are compared. `pysaliency` and `torch` arrive with `requirements-tier3.txt`; install them into the same venv (§1.3) when you reach Tier 3, not before.

Always report alongside each metric: the human value, the human–human consistency ceiling (split-half), and the best published model value (CGS for tier 1, HAT/Gazeformer for tier 3).

---

## 10. Phases, milestones, and definition of done

0. **Setup** (§1.2 to §1.4): ACT-R 7.31.4 fingerprint confirmed and loading in SBCL; venv created at `.venv` with `requirements.txt` installed; `git init` done and `.gitignore` in place. Done when all four sanity checks in §1.6 pass.
1. **Reference sims** (`reference/`): `test_reference.py` passes with published numbers for `cgs.py` and `gs6_sim.py`; `gs_hybrid.py` runs the three tasks and a first parameter set per task giving Tier 1 slopes within 10 ms/item is recorded in its docstring. Done when slopes and error patterns match §7.
2. **Module skeleton**: subclass loads; with both `:gs-enabled t` (no new requests) and `:gs-enabled nil`, tutorial unit 2/3 traces are identical to the stock module's. `tests/test_backcompat.py` passes.
3. **Priority + acuity + iconic memory**: `+visual-location> ... :guided t` returns the target first in feature search ≥ 95% of the time at set size 18; in conjunction search with `guide (color)` the first selection is a colour-matching item ≥ 90% of the time; in 2-vs-5 the first selection is at chance level.
4. **Diffuser + IOR + CGS quit**: `+visual> isa gs-search` on the three tasks reproduces `gs_hybrid.py` cell means within Monte Carlo error at the Phase 1 parameter sets, and those give slopes within 5 ms/item of the Tier 1 human means; TA:TP ratio between 2 and 3. Any residual misfit at a single shared parameter set is documented, not hidden.
5. **EMMA saccades**: fixation counts scale with set size; fixation durations 180–275 ms; saccade amplitudes 3–7°; no fixations outside the display.
6. **Adaptive QT + priming + feedback**: prevalence 10% vs 50% shows miss rate increase ≥ 10 points and faster TA RTs; repeated target colour speeds RT by 20–60 ms.
7. **Fitting and RESULTS.md**: table per §9 tier 1 and 2, plots, parameter table, comparison to CGS and PAAV published values, list of failures.

Definition of done for the whole handoff: phases 1–7 complete, README documents the API, and `RESULTS.md` states accuracy in the form "metric: model / human / ceiling / best competitor".

---

## 11. Pitfalls and rules

- Do not edit anything under `G:\VisualSearchModeling\actr7.x`. It is a vendored dependency that must stay replaceable by a fresh download. Load your code after ACT-R.
- Two ACT-R copies exist on this machine (§1.1). Only the one inside this repo is 7.31.4; line numbers from the older copy are 37 lower in `vision.lisp`.
- Do not load or port `paav-visual-module_2014.01.15.lisp`; it targets ACT-R 6 (§1.7). Copying code from it makes the result GPL v3 (§12).
- Run every Python command inside the project venv (§1.3). The machine's Anaconda base happens to contain numpy, pandas and torch, so code that forgets the venv will appear to work and then fail for anyone else. Any new dependency goes into `requirements.txt` in the same commit that first imports it.
- `undefine-module` prints a warning and does nothing if a model exists; call it right after load.
- `schedule-event-relative` uses seconds; pass `:time-in-ms t` if you compute in ms. Mixing them is the most common timing bug.
- The visicon and marker state are lock-protected; hold the locks when reading/writing (`visicon-lock`, `marker-lock`) or you will get intermittent errors under the Environment. Protect the module's own state with `gs-lock`.
- `:delete-visicon-chunks t` (default) deletes location chunks after use; iconic memory must key on the visicon feature identity (`chunk-visicon-entry`), not on the buffer chunk name.
- A buffer cannot hold a chunk and a failure flag at the same time (§3); a failed search leaves the `visual` buffer empty.
- Luce weights must be centred (§5.4); uncentred `exp(β·P)` values make the CGS quit weight negligible and the search never quits.
- Shape and other identification-only features must never enter the priority map (§5.1), or 2-vs-5 becomes a feature search.
- Use ACT-R's `act-r-random`/`act-r-noise` so `:seed` controls all randomness; document any numpy-side randomness separately.
- Per-trial `reset` wipes adaptive state. Persist QT/priming/prevalence window across trials in the module instance and only clear them on `reset` (i.e. simulate a subject as one model run).
- Productions still cost 50 ms. The response path after a hit is: `encoding-complete` → production reads `visual` → motor request. Include this in intercept comparisons; do not tune the module to absorb it.
- Report failures honestly in `RESULTS.md`; a documented misfit is worth more than a hidden one.

---

## 12. Decisions left to the project owner

1. Whether to keep the `visual-location`/`visual` buffer names (recommended) or add a third `gs-search` buffer.
2. Which Tier 1 dataset to fit first if the Wolfe server remains unreachable (Adam et al. 2021 is the fallback).
3. Whether the pixel front end for Tier 3 uses Itti–Koch (fast, weak) or a DNN target-modulated map (IVSN/HAT, stronger, needs GPU).
4. Licensing. ACT-R is LGPL 2.1; a subclass that loads separately can be any licence, but copying `define-module` parameter lists from `vision.lisp` keeps it LGPL-derived. **PAAV is GPL v3**: reading it and re-implementing the ideas is fine, copying its code into `gs-vision/` makes the module GPL v3. Decide whether that is acceptable before any code is copied; also decide whether the PAAV file stays at the repo root or moves to `third-party/paav/` (update §1.5 if moved).
5. Whether to model identification errors (GS6's adjustable start point, which produces false alarms from the item diffuser) or keep CGS's error-free identification with a response-level motor error, as specified in §5.4.
6. Whether `:gs-select-interval`/`:gs-diffuser-capacity` may differ per task (needed for 2-vs-5 slopes, §5.4) or must be shared across tasks with the misfit reported.

---

## 13. Primary references (full list in the companion report)

Wolfe 2021 *Psychon Bull Rev* 28:1060 (GS6, sim code https://osf.io/9n4hf/; full text PMC8965574); Wolfe 1994 *PB&R* 1:202 (GS2 rules); Moran, Zehetleitner, Müller & Usher 2013 *J Vision* 13(8):24 (CGS); Wolfe, Palmer & Horowitz 2010 *Vision Res* 50:1304 (benchmark data; PMC2891283); Nyamsuren & Taatgen 2013 *Cogn Syst Res* 24:62 (PAAV; code for ACT-R 6 at http://www.ai.rug.nl/~n_egii/models/ per the paper, and vendored here); Salvucci 2001 *Cogn Syst Res* 1:201 (EMMA); Hulleman & Olivers 2017 *BBS* 40:e132 (FVF model); Kieras 2010 ICCM and Kieras & Meyer 2026 *PB&R* 33:76, "Covert-attention shifting superseded" (acuity, EPIC; PMC12913267); Wu & Wolfe 2022 *Vision Res* 190:107965 (functional visual fields; PMC8976560); Adam, Patel, Rangan & Serences 2021 *J Cognition* 4(1):34 (open dataset; PMC8323537); Bothell, ACT-R 7.30+ Reference Manual, `actr7.x/docs/reference-manual.pdf`; Chen et al. 2021 *Sci Rep* 11:8776 (COCO-Search18).
