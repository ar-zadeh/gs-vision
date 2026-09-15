# V5 manuscript consistency audit

The corrected manuscript reconciles the text, tables, and figure descriptions
with the archived evaluations and the implementation used for those runs.
The review began September 9 and finished September 10, 2026.

- [Corrected Word manuscript](gs-vision-BRM-tutorialV5-corrected.docx)
- [Corrected PDF](gs-vision-BRM-tutorialV5-corrected.pdf)
- [Detailed changes](gs-vision-BRM-tutorialV5-corrections.json)

The original V5 document was open in Microsoft Word, so the corrections are
delivered as a separate copy. The original Word document, original PDF,
`paper.md`, existing figure assets, and all scientific data remain unchanged.
V5 contains author edits that differ from `paper.md`; it was edited directly,
not rebuilt from that older Markdown source.

## Main findings and implemented corrections

The headline results in Tables 4, 7, and 8 agree with the archived evaluations.
The principal changes concern what those results support, the configurations
that produced them, and three numeric entries elsewhere in the manuscript.

1. **Validation selection and exploratory status.** The refit was presented
   as the best account without clearly stating that validation selection
   retained the frozen shared fit. The corrected abstract, protocol, results,
   table note, and conclusion distinguish the exploratory trigger candidate
   from that selection. Test quantile RMSE remains 100.1 ms for the trigger
   refit and 127.7 ms for the frozen fit; validation quantile RMSE is 173.3
   versus 143.1 ms. Selection used the full fitting objective, rather than
   quantile RMSE alone. See the [selection record](../../data/model/refit_20260905/selection.json)
   and [refit evaluation](../validation-refit-20260905/evaluation.json).

2. **Comparison protocol.** Common human splits and scoring criteria do not
   imply identical optimization budgets, display simulations, or candidate
   selection. The baseline driver keeps the training-objective winner and
   does not separately select candidates on validation participants. These
   differences are now explicit. See [compare_models.py](../../harness/compare_models.py).

3. **Model counts and ranking.** Tables 7 and 8 contain 18 model
   configurations from nine families, plus the human reference. Seven
   trial-level configurations represent five families. Three configurations
   have lower test quantile RMSE than the trigger refit: serial FIT (80.5),
   CGS shared timing (82.9), and CGS per task (98.8 ms). The original text
   inconsistently reported six trial-level models, eleven families, and only
   two configurations with lower error. See the [comparison evaluation](../validation-comparison-20260906/evaluation.json).

4. **Scope of the accuracy claim.** The exploratory trigger refit has the
   lowest numerical test RT-quantile error among the ACT-R accounts evaluated.
   This does not establish a statistically reliable or validation-selected
   advantage. The frozen fit's 127.7 ms exceeds fitted gs6-vision's 122.5 ms.
   Stock and PAAV results are mirrors, not direct runs of those modules.
   These qualifications now accompany the main claims.

5. **Human-reference interpretation.** The 93.3 ms training-to-test score is
   cross-group variability, not a lower bound, a confidence interval, or a
   significance threshold for model differences. Removed the unsupported
   inference that a smaller model difference demonstrates equivalence or
   falls within a measured noise bound. The value was independently
   recomputed from the archived human summaries.

6. **Table 5 numeric corrections.** Spatial fixation counts are **7.2** for
   old quit weights and **5.4** for threshold step 0.005, rather than 6.1 for
   both. These are counts across both target conditions, whereas the RT
   columns summarize absent trials. The caption now states that distinction.
   See [ablation_eyes.csv](../validation-20260905/ablation_eyes.csv).

7. **Ablation configuration and sample size.** Table 5 uses module defaults
   with revised policies, not the frozen fitted parameters. Its sample is
   150 retained trials per cell per seed, or 300 across two seeds. The
   reported 1,200 rows per target condition pool four set sizes. The prose
   now identifies the correct configuration and denominator. See the
   [configurations](../validation-20260905/ablation_configurations.json),
   [behavior summaries](../validation-20260905/ablation_behavior.csv), and
   [ablation driver](../../harness/repair.py).

8. **Capture manipulation.** The 7.6 ms ACT-R capture effect uses the frozen
   fitted bottom-up weight **1.049**, not the default 0.5. The comparison
   condition uses 3.0. Corrected both the prose and Table 6. See the
   [ACT-R study manifest](../validation-20260905/actr_study_manifest.json).

9. **Priming contrast.** The known-template contrast is switch minus repeat,
   not repeat minus switch. In the unknown-color protocol, removing history
   changes the contrast from −6.2 to −22.5 ms, a difference of −16.3 ms;
   −22.5 is the resulting contrast, not the size of the change. See the
   [study summary](../validation-20260905/actr_study_summary.json).

10. **Prevalence interval and human reference.** The absent-RT contrast is
    now reported as **+87.3 ms [77.1, 97.5]**, directly rounded from the
    archive. The previous integer upper endpoint of 98 resulted from double
    rounding. Replaced the unsupported +20–25-point human entry for the
    stated 10%-50% contrast with a qualitative reference. The cited
    [Wolfe et al. article](https://www.nature.com/articles/435439a) supports
    increased misses for rare targets; its abstract does not establish that
    specific quantitative contrast. No new human estimate was invented.

11. **Feedback rules.** The hybrid subtracts a constant step after a true
    negative. The posted GS6 engine additionally multiplies its down-step
    by prevalence and its miss increment by one minus prevalence. Removed
    the claim that these implementations use identical feedback equations,
    the equilibrium derivation applied to the wrong implementation, and the
    proposed remedy that the hybrid already implements. See
    [hybrid feedback](../../gs-vision/gs-diffuser.lisp) and the
    [posted-engine replication](../../reference/gs6_sim.py).

12. **Competitive versus adaptive stopping.** Competitive quitting can
    interrupt pending identification; adaptive threshold stopping drains
    outstanding identifications. The manuscript now distinguishes them.
    Table 2 also includes the adaptive scaling of the competitive increment
    when `:gs-adaptive-quit-delta` is enabled.

13. **Missing parameters and units.** Added `:gs-onset-latency`,
    `:gs-adaptive-quit-delta`, and `:gs-explore-proximity` to Table 3. The
    onset parameter is an extra delay beyond the selection interval. The
    saccade margin is in priority units; the trigger is in degrees. Choice
    beta is an inverse temperature. See [parameter definitions](../../gs-vision/gs-params.lisp)
    and [selection scheduling](../../gs-vision/gs-diffuser.lisp).

14. **Fixed refit policies.** The reported trigger configuration fixes the
    saccade trigger at **6 degrees**; it was not a continuously optimized
    parameter that the fit selected weakly. Both refit bases enable adaptive
    quit increments and exploration proximity. Corrected the methods,
    eye-movement discussion, and limitations. See [refit.py](../../harness/refit.py)
    and the [trigger configuration](../../data/model/refit_20260905/refit_trigger_501.json).

15. **Cell-level result descriptions.** Frozen feature mean RT errors span
    54–118 ms. Refit spatial mean RT errors span 110–225 ms. At conjunction
    set size 3, the refit's 10th percentile is earlier than the human value,
    not later; the corresponding set-size-6 quantile is later. Large
    conjunction-absent quantile improvements occur at set sizes 12 and 18,
    not uniformly across all four sizes. See the [frozen cells](../validation-20260905/shared_test_cells.csv)
    and [refit cells](../validation-refit-20260905/refit_trigger_501_test_cells.csv).

16. **Eye-data limits.** Model observations end at visual result, not
    keypress. Reported refit amplitudes are 9.7, 12.1, and 12.3 degrees in
    feature, conjunction, and spatial search; spatial fixation duration is
    149 ms. The human foraging task is unmatched. Human split-half scanpath
    consistency is descriptive, not a ceiling for this benchmark. See the
    [refit eye summary](../validation-refit-20260905/refit_trigger_501_eyes.csv)
    and [secondary-results interpretation](../validation-20260905/SECONDARY-RESULTS.md).

17. **Baseline descriptions.** CGS with shared timing shares identification
    parameters across tasks; task differences come from guidance and quitting.
    The original claim that both leading models fit task-specific item timing
    was incorrect. PAAV has a Lisp source, but no runnable ACT-R 7 parity
    implementation was available for this comparison. Separately fitted GS6
    variants do not isolate a single causal embedding cost. See
    [baselines.py](../../reference/baselines.py).

18. **Figures.** Figure 1's caption now describes its actual colored paths.
    Figure 3 shows 15 selected configurations, not all 18. Rebuilt that plot
    from the archived evaluation, with one-decimal labels and a legend that
    distinguishes ACT-R accounts from trial-level models without claiming
    that every account has a display and eyes. Its caption identifies PAAV
    as a display-level mirror and stock vision as a timing mirror.

19. **Timing, fitting, and tutorial corrections.** Three 50 ms productions
    plus 85 ms encoding total 235 ms; Table 1 now distinguishes the
    two-production alternative. Removed the internally inconsistent 130 ms
    timing decomposition and the unsupported 72-evaluation total. The
    frozen fit used two four-generation searches with 18-member populations;
    refit evaluation counts are per completed restart. Corrected the module
    loading restriction, display clearing between trials, and the schematic
    event-loop comment. Regeneration commands now distinguish evaluating
    archived runs from refitting them.

## Verification and implementation record

Verification used the existing data; it did not rerun fits or alter outcomes.

- Checked **248 numeric entries** in Tables 4–8 against archived JSON/CSV
  evaluations or independently recomputed human summaries. All pass after
  the corrections above. Table 6 checks cover model estimates and intervals;
  external human literature values were not re-estimated.
- Reopened the corrected DOCX with `python-docx` and Microsoft Word.
- Preserved 217 body paragraphs, eight tables, and five embedded figures.
  Added three rows to the parameter table.
- Copied all original OOXML package parts unchanged except
  `word/document.xml` and the embedded Figure 3 image. This preserves
  styles, author metadata, references, hyperlinks, and the other figures.
- Exported a 45-page PDF with Microsoft Word. Checked all pages for text
  extending outside the page bounds, and visually reviewed the equation
  table, parameter table, ablation table, and revised comparison figure.
- Verified that the original V5 DOCX checksum was unchanged.

The detailed change file records each edited location, its original and final
wording, and the evidence used. No generic repository formatter applies to
the Word document; no model or code tests were needed for these document-only
changes.

The source reports and `paper.md` still contain some of the corrected
statements. Regenerating V5 from those files would require carrying these
corrections forward. This audit addresses the requested V5 document directly.
