"""Assemble reviewable summaries from explicit, completed repair artifacts.

No simulation or parameter selection occurs here. Missing required inputs fail.
Full trial data remain in the run directory; the destination contains summaries,
plots, configurations, hashes, and the command record.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from harness.evaluate import eye_summary, model_frame
from harness.human_data import digest
from harness.report import replace_generated, table


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def interval(values):
    values = np.asarray(values, dtype=float)
    if not len(values) or not np.isfinite(values).all():
        raise ValueError("Missing contrast observations")
    boot = np.random.default_rng(7003).choice(values, (4000, len(values))).mean(axis=1)
    return dict(mean=float(values.mean()), lo=float(np.quantile(boot, .025)),
                hi=float(np.quantile(boot, .975)))


def summarize_studies(root, out):
    manifest = read(root / "actr_studies/manifest.json")
    rows, contrasts = [], []
    for study in manifest:
        paths = [root / "actr_studies" / f"{study['id']}_seed{s}_trials.csv" for s in study["seeds"]]
        frame = model_frame(paths)
        by_seed = []
        for seed, group in frame.groupby("subject_seed"):
            present = group[group.target_present.astype(bool)]
            absent = group[~group.target_present.astype(bool)]
            row = dict(study=study["id"], seed=int(seed), retained=len(group),
                       present_trials=len(present), absent_trials=len(absent),
                       miss_rate=float(present.error.mean()),
                       false_alarm_rate=float(absent.error.mean()) if len(absent) else None,
                       timeouts=int(group.timed_out.sum()),
                       absent_rt_ms=float(absent.loc[absent.correct, "rt_ms"].mean()) if len(absent) else None,
                       final_qt=float(group.qt_scale.iloc[-1]))
            if study["id"].startswith("capture"):
                condition, sign = "distractor_present", 1
            elif "priming" in study["id"] or "history" in study["id"]:
                condition, sign = "color_repeat", -1
            else:
                condition = None
            if condition:
                correct = present[present.correct & ~present.timed_out]
                means = correct.groupby(correct[condition].astype(bool)).rt_ms.mean()
                counts = correct.groupby(correct[condition].astype(bool)).size()
                row.update(condition=condition, contrast_ms=float(sign * (means.loc[True] - means.loc[False])),
                           correct_true=int(counts.loc[True]), correct_false=int(counts.loc[False]),
                           retained_true=int(present[condition].astype(bool).sum()),
                           retained_false=int((~present[condition].astype(bool)).sum()))
                by_seed.append(row["contrast_ms"])
            rows.append(row)
        if by_seed:
            contrasts.append(dict(study=study["id"],
                contrast="distractor cost" if study["id"].startswith("capture") else "switch minus repeat benefit",
                **interval(by_seed)))
    df = pd.DataFrame(rows)
    df.to_csv(out / "actr_studies_by_seed.csv", index=False)
    pd.DataFrame(contrasts).to_csv(out / "actr_study_contrasts.csv", index=False)
    prev = df[df.study.str.startswith("prevalence")].pivot(index="seed", columns="study")
    difference = dict(miss_increase_points=interval(100 * (prev.miss_rate.prevalence10 - prev.miss_rate.prevalence50)),
                      absent_rt_change_ms=interval(prev.absent_rt_ms.prevalence10 - prev.absent_rt_ms.prevalence50))
    result = dict(contrasts=contrasts, prevalence=difference,
                  uncertainty="95% seed bootstrap; two ACT-R seeds, not a population CI",
                  priming_window="correct target-present trials; includes response repetition effects",
                  practice="30 before each block; differs from continuous mirror prevalence practice")
    (out / "actr_study_summary.json").write_text(json.dumps(result, indent=2))
    return result


def summarize_ablations(root, out):
    configs = read(root / "ablations/configurations.json")
    eyes, behavior = [], []
    for name in configs:
        trials = model_frame([root / "ablations" / f"{name}_seed{s}_trials.csv" for s in (321, 322)])
        fixes = pd.concat([pd.read_csv(root / "ablations" / f"{name}_seed{s}_fixations.csv")
                           for s in (321, 322)], ignore_index=True)
        eyes.append(eye_summary(fixes, trials).assign(configuration=name))
        for (task, present), group in trials.groupby(["task", "target_present"]):
            behavior.append(dict(configuration=name, task=task, target_present=present,
                rt_ms=group.rt_ms.mean(), correct_rt_ms=group.loc[group.correct, "rt_ms"].mean(),
                error_rate=group.error.mean(), search_ms=group.search_ms.mean(),
                timeouts=int(group.timed_out.sum()), retained=len(group)))
    pd.concat(eyes, ignore_index=True).to_csv(out / "ablation_eyes.csv", index=False)
    pd.DataFrame(behavior).to_csv(out / "ablation_behavior.csv", index=False)


def summarize_mirror_counts(root, out):
    rows = []
    for name in ("known", "unknown", "unknown_no_history"):
        df = pd.read_csv(root / "experiments" / f"priming_{name}.csv")
        for (seed, present, repeat), group in df.groupby(["subject_seed", "target_present", "color_repeat"]):
            rows.append(dict(study=name, seed=seed, target_present=present, color_repeat=repeat,
                             retained=len(group), correct=int(group.correct.sum()),
                             timeouts=int(group.timed_out.sum()),
                             correct_rt_ms=1000*group.loc[group.correct, "rt"].mean()))
    pd.DataFrame(rows).to_csv(out / "mirror_priming_counts.csv", index=False)


def secondary_report(mirror, actr, eye):
    chunks = ["These manipulations use the frozen shared fit. Weight sweeps are calibration. "
        "Intervals resample simulation seeds (three mirror, two ACT-R); the human capture "
        "interval resamples participants. They do not measure model individual differences."]
    rows = []
    for name in ("known", "unknown", "unknown_no_history"):
        r = mirror["experiments"][name]
        rows.append(["mirror", name, "switch minus repeat", f"{-r['difference_true_minus_false_ms']:.2f}",
                     f"{-r['hi']:.2f} to {-r['lo']:.2f}"])
    for r in mirror["experiments"]["capture"]:
        rows.append(["mirror", f"capture w_bu={r['w_bu']:.3f}", "present minus absent",
                     f"{r['difference_true_minus_false_ms']:.2f}", f"{r['lo']:.2f} to {r['hi']:.2f}"])
    for r in actr["contrasts"]:
        rows.append(["ACT-R", r["study"], r["contrast"], f"{r['mean']:.2f}", f"{r['lo']:.2f} to {r['hi']:.2f}"])
    h = mirror["capture_human"]
    rows.append(["human", "Adam Search 1c, 24 participants", "present minus absent",
                 f"{h['mean_cost_ms']:.2f}", f"{h['lo']:.2f} to {h['hi']:.2f}"])
    chunks.append(table(rows, ["Implementation", "Study", "Contrast", "Mean ms", "95% interval ms"]))
    chunks.append("The capture analogue uses an orientation target; Adam uses a shape target. "
        "The shared mirror cost is below half the human mean, while w_bu=3 moves closer. "
        "That sweep does not establish a matched replication or justify the substantial "
        "conjunction-search cost. The known-template control reveals the target color; "
        "the unknown-color protocol instead identifies a two among fives without revealing "
        "the upcoming guiding color. Neither establishes the 20–60 ms priming target. "
        "Counts of retained and correct repeat/switch trials are in the accompanying CSVs.")
    prev = pd.DataFrame(mirror["experiments"]["prevalence"]).pivot(index="seed", columns="prevalence")
    m = interval(100 * (prev.miss_rate[.1] - prev.miss_rate[.5]))
    rt = interval(prev.absent_rt_ms[.1] - prev.absent_rt_ms[.5])
    a = actr["prevalence"]
    chunks.append("## Prevalence\n\nThe contrasts compare low with equal target prevalence.\n\n" + table([
        ["mirror", f"{m['mean']:.2f}", f"{m['lo']:.2f} to {m['hi']:.2f}",
         f"{rt['mean']:.1f}", f"{rt['lo']:.1f} to {rt['hi']:.1f}"],
        ["ACT-R", f"{a['miss_increase_points']['mean']:.2f}",
         f"{a['miss_increase_points']['lo']:.2f} to {a['miss_increase_points']['hi']:.2f}",
         f"{a['absent_rt_change_ms']['mean']:.1f}",
         f"{a['absent_rt_change_ms']['lo']:.1f} to {a['absent_rt_change_ms']['hi']:.1f}"]],
        ["Implementation", "10%-50% miss points", "95% interval", "Absent RT change ms", "95% interval"]))
    chunks.append("The original project target requires at least a 10-point miss increase "
        "and faster absent responses. This model fails that joint target. Mirror blocks "
        "use 1,000 practice then 2,000 retained trials per seed. ACT-R uses the benchmark "
        "block schedule and 3,200 retained trials per seed. These are separate checks; "
        "no matched secondary parity claim is made. The prevalence plot shows threshold "
        "and rolling errors; seed-level rare-target counts and final state are retained.")
    chunks.append("## Human eye consistency\n\nThese estimates compare matched human conditions across participant halves.\n\n" + table(
        [[name, f"{value:.4f}"] for name, value in eye["human_similarity"].items()],
        ["Metric", "Human split-half mean"]) + "\n\nModel-to-human comparison: " + eye["model_comparison"])
    return "\n\n".join(chunks)


def assemble(root, out):
    out.mkdir(parents=True, exist_ok=True)
    frozen, selected = read(root / "frozen.json"), read(root / "selected.json")
    if digest(selected) != frozen["selected_hash"]:
        raise ValueError("Selected parameters differ from the freeze")
    inputs = {}
    def copy(source, name=None):
        destination = out / (name or source.name)
        shutil.copy2(source, destination)
        inputs[source.relative_to(ROOT).as_posix()] = sha(source)
    for filename in ("selected.json", "frozen.json", "selection.json", "run_manifest.json", "sensitivity.json"):
        copy(root / filename)
    for filename in ("manifest.json", "protocol.json", "splits.json", "exclusions.csv"):
        copy(root / "human" / filename, "human_" + filename)
    for source in sorted((root / "evaluation").iterdir()):
        if source.suffix in (".json", ".csv", ".png"):
            copy(source)
    for source in sorted((root / "eye").iterdir()):
        if source.suffix in (".json", ".csv"):
            copy(source)
    for filename in ("experiments.json", "prevalence.png"):
        copy(root / "experiments" / filename)
    copy(root / "actr_studies/manifest.json", "actr_study_manifest.json")
    copy(root / "ablations/configurations.json", "ablation_configurations.json")
    summarize_ablations(root, out)
    summarize_mirror_counts(root, out)
    actr = summarize_studies(root, out)
    mirror, eye = read(root / "experiments/experiments.json"), read(root / "eye/eye_audit.json")
    # Keep the original freeze intact. Correct the old metadata label explicitly.
    overrides = {task: [k for k, v in cfg["params"].items() if v != selected["shared"]["params"][k]]
                 for task, cfg in selected.items() if task != "shared"}
    errata = dict(task_specific_overrides=overrides,
        note="Frozen conjunction extra_free_parameters=6 incorrectly described a historical candidate. "
             "It has 11 settings differing from shared and zero newly fitted settings in that candidate. "
             "New task-specific DE searches each fit six settings. Original frozen metadata is preserved.")
    (out / "selection_metadata_erratum.json").write_text(json.dumps(errata, indent=2))
    report = out / "SECONDARY-RESULTS.md"
    if not report.exists():
        report.write_text("# Secondary validation\n", encoding="utf-8")
    replace_generated(report, secondary_report(mirror, actr, eye))
    logs = {"validation": "final-validation-tests.log", "reference": "final-reference-tests.log",
            "backcompat": "final-backcompat-tests-isolated.log", "lisp": "final-lisp-tests.log",
            "cli_help": "cli-help-checks.log"}
    checks = {}
    for name, filename in logs.items():
        source = root / filename
        copy(source)
        checks[name] = source.read_text(encoding="utf-8", errors="replace")[-1600:]
    copy(root / "baseline/environment.txt", "baseline-environment.txt")
    copy(root / "final-environment.txt")
    copy(root / "verify_delivery.py")
    copy(root / "baseline/source_hashes.json", "baseline-source-hashes.json")
    copy(root / "baseline/status.txt", "baseline-status.txt")
    # Every reported secondary run has an explicit file identity, not a glob of old outputs.
    for directory, patterns in [("actr_studies", ("*_trials.csv", "*_manifest.json")),
                                ("ablations", ("*_trials.csv", "*_fixations.csv", "*_manifest.json")),
                                ("experiments", ("*.csv",)), ("eye", ("*.json", "*.csv"))]:
        for pattern in patterns:
            for source in sorted((root / directory).glob(pattern)):
                inputs[source.relative_to(ROOT).as_posix()] = sha(source)
    source_hashes = {}
    for directory in ("harness", "reference", "gs-vision", "models", "tests"):
        for source in sorted((ROOT / directory).rglob("*")):
            if source.suffix in (".py", ".lisp", ".m") and "vendor" not in source.parts:
                source_hashes[source.relative_to(ROOT).as_posix()] = sha(source)
    commands = [
        "& .venv/Scripts/python.exe harness/human_data.py",
        "& .venv/Scripts/python.exe harness/repair.py development --iterations 4 -n 30",
        "& .venv/Scripts/python.exe harness/repair.py final -n 1000",
        "& .venv/Scripts/python.exe harness/repair.py ablations -n 150",
        "& .venv/Scripts/python.exe harness/sensitivity.py",
        "& .venv/Scripts/python.exe harness/experiments.py --params data/model/repair_20260905/selected.json",
        "& .venv/Scripts/python.exe harness/study_batch.py",
        "& F:/Matlab/bin/matlab.exe -batch \"run('G:/VisualSearchModeling/harness/export_eye_data.m')\"",
        "& .venv/Scripts/python.exe harness/eye_audit.py",
        "& .venv/Scripts/python.exe harness/report.py --manifest data/model/repair_20260905/run_manifest.json --final-test",
        "sbcl --non-interactive --load tests/test_module_events.lisp",
        "& .venv/Scripts/python.exe -m pytest tests/test_validation.py -q",
        "& .venv/Scripts/python.exe -m pytest reference/test_reference.py -q",
        "& .venv/Scripts/python.exe -m pytest tests/test_backcompat.py -q",
        "& .venv/Scripts/python.exe data/model/repair_20260905/verify_delivery.py",
        "& .venv/Scripts/python.exe harness/archive_validation.py",
    ]
    record = dict(schema_version=1, run_id="repair_20260905", baseline_revision=(root / "baseline/revision.txt").read_text().strip(),
        baseline_working_tree="No tracked modifications; existing untracked handoff/walkthrough/specification and data preserved. See baseline-status.txt and source archive.",
        working_directory=str(ROOT), commands=commands, checks=checks, inputs_sha256=inputs,
        source_sha256=source_hashes, selected_hash=frozen["selected_hash"], split_id=frozen["human_manifest"]["split_id"],
        experiment_seeds=dict(final=[401,402], ablations=[321,322], mirror_secondary=[301,302,303],
                              threshold_steps=[311,312,313], actr_secondary=[501,502], eye_split=901),
        development="Two six-parameter DE restarts, four generations each; 18-member population, n=30/cell. "
                    "Validation n=250/cell with fresh seeds. Cached candidates revalidated after millisecond normalization. "
                    "Optimizer convergence is not claimed.",
        final_testing="Selection frozen before test summaries were first evaluated. No model tuning used test results.",
        post_freeze_changes="Session connection isolation, report assembly, and metadata correction only. "
                            "The secondary capture palette was repaired to avoid a green distractor on green background; "
                            "the pre-fix experiment summary is preserved separately. Final benchmark mechanics unchanged.",
        test_incident="Concurrent ACT-R/backcompat tests initially shared the home port file and failed. "
                      "Complete parameter readback rejected the wrong server. Private handshake plus per-session "
                      "client modules fix this; nested-session regression passes. Failed logs retained in full run directory.",
        limitations=["Two test participants per task; limited human population precision.",
                     "Quantile, slope, miss-rate, saccade, priming, and prevalence targets remain unmet.",
                     "Zero false alarms are structural; no arbitrary motor lapse was fitted.",
                     "Capture is an analogue calibration, not a matched shape-target replication.",
                     "Eye data are continuous foraging with missing item rotations and exact observation timestamps; model scanpath comparison unavailable.",
                     "StuffIt archive could not be decoded; never substituted for trial data.",
                     "Original source data and full event/trial logs are local ignored artifacts, not embedded in this review directory."])
    (out / "run-record.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(f"Assembled {out}; {len(inputs)} input hashes; selection unchanged")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, default=ROOT / "data/model/repair_20260905")
    ap.add_argument("--out", type=Path, default=ROOT / "docs/validation-20260905")
    args = ap.parse_args()
    assemble(args.root.resolve(), args.out.resolve())


if __name__ == "__main__":
    main()
