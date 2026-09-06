"""Validated Wolfe trial import and participant-weighted evaluation protocol.

The archival table retains every source row, including errors and invalid RTs.
Only explicitly requested splits are summarized; the CLI defaults to development
splits so importing data does not expose test performance during model selection.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "feature": ("RVvGV.txt", 35948, 9,
                "cd3c9266103a84c8bdb449ff342c93e180b67d14f35638259645cda9b928323f"),
    "conjunction": ("RVvRHGV.txt", 39962, 10,
                    "6e06a1ae64ff474fea053dc08f787df721ed6b3b8a9bccb019e6c990e7b537b5"),
    "spatial": ("2_vs_5.txt", 35867, 9,
                "50190cfa880fc810f386f6306e9ef82b120788ce5ea6b572d276c287350391ef"),
}
QUANTILES = (.1, .3, .5, .7, .9)
CELLS = ["task", "set_size", "target_present"]
PROTOCOL = {
    "version": 1, "split_seed": 20260905, "bootstrap_seed": 50260905,
    "rt_lower_ms_inclusive": 200,
    "rt_upper_ms_inclusive": {"feature": 4000, "conjunction": 4000, "spatial": 8000},
    "accuracy": "all validated behavioral rows, independent of RT trimming",
    "primary": "equal participant weight; correct RTs; average participant quantiles",
    "sensitivity": "correct positive RTs without upper truncation",
    "source": "https://search.bwh.harvard.edu/new/data_set_files.html",
    "identity": "task:source_file:subject_id; source_row is physical line including header",
    "practice": "source rows retained; trial-number resets are not practice exclusions",
    "objective": "mean cell quantile RMSE ms + 1000 * absolute error rate difference; "
                 "2000 ms for empty correct cells; 2000 * timeout fraction",
}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def import_file(path, task):
    """Fail with a physical line number for malformed input; never deduplicate."""
    path = Path(path)
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)
        expected = (["sinit", "CondReport", "trialdigit", "setsize", "target present",
                     "error", "message", "RT", "", ""] if task == "feature" else
                    ["Subject", "Condition", "trial#", "setsize", "Targ_Pres",
                     "Error", "message", "RT(ms)"])
        if header != expected:
            raise ValueError(f"{path}: unexpected columns {header!r}")
        records, raw = [], []
        for line, values in enumerate(reader, 2):
            try:
                if not 8 <= len(values) <= len(header) or any(values[8:]):
                    raise ValueError("malformed width or nonempty unnamed columns")
                subject, condition, trial, size, present, error, outcome, rt = values[:8]
                trial_n, n, pr, err, rt_n = map(int, (trial, size, present, error, rt))
                if not subject or n not in (3, 6, 12, 18) or pr not in (0, 1) or err not in (0, 1):
                    raise ValueError("invalid behavioral fields")
                if outcome != {(1, 0): "HIT", (1, 1): "MISS", (0, 0): "TNEG", (0, 1): "FA"}[pr, err]:
                    raise ValueError("outcome disagrees with presence/error")
                upper = PROTOCOL["rt_upper_ms_inclusive"][task]
                records.append(dict(task=task, source_file=path.name, source_row=line,
                    subject_id=subject, participant_key=f"{task}:{path.name}:{subject}",
                    condition_source=condition, trial_source=trial, trial_number=trial_n,
                    set_size=n, target_present=pr, error=err, correct=err == 0,
                    outcome=outcome, rt_source=rt, rt_ms=rt_n, accuracy_eligible=True,
                    rt_eligible=200 <= rt_n <= upper, positive_rt_eligible=rt_n > 0,
                    rt_exclusion=("below_200" if rt_n < 200 else
                                  "above_upper" if rt_n > upper else "included")))
                raw.append(tuple(values))
            except (ValueError, TypeError) as exc:
                raise ValueError(f"{path.name}:{line}: {exc}") from exc
    df = pd.DataFrame(records)
    if df.empty:
        raise ValueError(f"{path}: no trials")
    audit = dict(source_file=path.name, task=task, bytes=path.stat().st_size,
                 sha256=hashlib.sha256(path.read_bytes()).hexdigest(), rows=len(df),
                 participants=df.participant_key.nunique(), malformed_rows=0,
                 duplicate_full_records=len(raw) - len(set(raw)),
                 repeated_trial_numbers=int(df.duplicated(["participant_key", "trial_number"]).sum()),
                 trial_number_resets=int((df.groupby("participant_key", sort=False).trial_number.diff() < 0).sum()),
                 conditions=sorted(df.condition_source.unique().tolist()),
                 exclusions=df.rt_exclusion.value_counts().to_dict(),
                 accuracy_denominator=len(df),
                 accuracy_denominator_if_rt_trimmed=int(df.rt_eligible.sum()),
                 errors_excluded_by_rt=int((~df.rt_eligible & ~df.correct).sum()))
    return df, audit


def split_participants(df, seed=20260905):
    rng = np.random.default_rng(seed)
    assignments = {}
    for task, part in df.groupby("task", sort=True):
        keys = sorted(part.participant_key.unique())
        rng.shuffle(keys)
        if len(keys) < 5:
            raise ValueError("At least five participants per task required")
        for i, key in enumerate(keys):
            assignments[key] = "train" if i < len(keys) - 4 else "validation" if i < len(keys) - 2 else "test"
    manifest = {"schema_version": 1, "seed": seed, "assignments": assignments}
    manifest["split_id"] = digest(manifest)
    return manifest


def participant_summary(df, sensitivity=False):
    records = []
    flag = "positive_rt_eligible" if sensitivity else "rt_eligible"
    for keys, group in df.groupby(["participant_key"] + CELLS, sort=True):
        ok = group.loc[group.correct & group[flag], "rt_ms"]
        errs = int(group.error.sum())
        record = dict(zip(["participant_key"] + CELLS, keys))
        record.update(n_trials=len(group), n_rt=len(ok), n_errors=errs,
                      n_rt_excluded=int((~group[flag]).sum()), mean=ok.mean(),
                      median=ok.median(), std=ok.std(), error_rate=errs / len(group),
                      misses=errs if keys[-1] else 0, false_alarms=0 if keys[-1] else errs)
        record.update({f"q{int(q*100)}": ok.quantile(q) for q in QUANTILES})
        records.append(record)
    return pd.DataFrame(records)


def group_summary(participants, bootstrap=2000, seed=50260905):
    """Bootstrap whole participants, preserving each participant's cell vector."""
    rng = np.random.default_rng(seed)
    measures = ["mean", "median", "std", "error_rate"] + [f"q{int(q*100)}" for q in QUANTILES]
    rows = []
    for task, block in participants.groupby("task", sort=True):
        keys = sorted(block.participant_key.unique())
        draws = rng.integers(0, len(keys), (bootstrap, len(keys)))
        for cell, group in block.groupby(CELLS, sort=True):
            group = group.set_index("participant_key").reindex(keys)
            rec = dict(zip(CELLS, cell))
            rec.update(n_participants=len(keys), n_trials=int(group.n_trials.sum()),
                       n_rt=int(group.n_rt.sum()), n_errors=int(group.n_errors.sum()))
            for metric in measures:
                vals = group[metric].to_numpy(float)
                rec[metric] = float(np.nanmean(vals))
                ci = np.nanmean(vals[draws], axis=1)
                rec[metric + "_lo"], rec[metric + "_hi"] = np.nanquantile(ci, [.025, .975])
            rows.append(rec)
    return pd.DataFrame(rows)


def load_split(directory, split):
    directory = Path(directory)
    manifest = json.loads((directory / "manifest.json").read_text())
    split_manifest = json.loads((directory / "splits.json").read_text())
    check = dict(split_manifest)
    split_id = check.pop("split_id")
    if digest(check) != split_id or manifest["split_id"] != split_id:
        raise ValueError("Split manifest integrity failure")
    protocol = json.loads((directory / "protocol.json").read_text())
    if digest(protocol) != manifest["protocol_id"]:
        raise ValueError("Preprocessing protocol integrity failure")
    trials_path = directory / "trials.csv.gz"
    if hashlib.sha256(trials_path.read_bytes()).hexdigest() != manifest["normalized_sha256"]:
        raise ValueError("Normalized data integrity failure")
    df = pd.read_csv(trials_path, dtype={"subject_id": str, "trial_source": str})
    mapped = df.participant_key.map(split_manifest["assignments"])
    if mapped.isna().any():
        raise ValueError("Participant missing from split")
    return df.loc[mapped == split].copy(), manifest


def targets(directory, split="train"):
    df, _ = load_split(directory, split)
    summary = group_summary(participant_summary(df), bootstrap=100)
    return {task: {(int(r.set_size), bool(r.target_present)):
                  {"q": np.array([getattr(r, f"q{int(q*100)}") for q in QUANTILES]),
                   "err": r.error_rate, "mean": r.mean}
                  for r in sub.itertuples()} for task, sub in summary.groupby("task")}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--raw", type=Path, default=ROOT / "data/Human-data-paper")
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/repair_20260905/human")
    ap.add_argument("--summarize", nargs="+", choices=["train", "validation", "test"],
                    default=["train", "validation"])
    args = ap.parse_args()
    frames, audits = [], []
    for task, (name, count, participants, sha) in SOURCES.items():
        frame, audit = import_file(args.raw / name, task)
        if (audit["rows"], audit["participants"], audit["sha256"]) != (count, participants, sha):
            raise ValueError(f"Source inventory differs: {name}")
        frames.append(frame)
        audits.append(audit)
    df = pd.concat(frames, ignore_index=True)
    splits = split_participants(df)
    args.out.mkdir(parents=True, exist_ok=True)
    split_path = args.out / "splits.json"
    if split_path.exists() and json.loads(split_path.read_text()) != splits:
        raise ValueError("Refusing to replace a frozen split")
    split_path.write_text(json.dumps(splits, indent=2))
    (args.out / "protocol.json").write_text(json.dumps(PROTOCOL, indent=2))
    df.to_csv(args.out / "trials.csv.gz", index=False, compression={"method": "gzip", "mtime": 0})
    manifest = dict(schema_version=1, sources=audits, total_rows=len(df),
                    split_id=splits["split_id"], protocol_id=digest(PROTOCOL),
                    normalized_sha256=hashlib.sha256((args.out / "trials.csv.gz").read_bytes()).hexdigest())
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    df.groupby(CELLS + ["rt_exclusion", "correct"]).size().rename("count").to_csv(args.out / "exclusions.csv")
    for split in args.summarize:
        sub = df[df.participant_key.map(splits["assignments"]) == split]
        for sensitivity in (False, True):
            suffix = "_positive" if sensitivity else ""
            part = participant_summary(sub, sensitivity)
            part.to_csv(args.out / f"{split}{suffix}_participants.csv", index=False)
            group = group_summary(part)
            group.to_csv(args.out / f"{split}{suffix}_summary.csv", index=False)
            pooled = participant_summary(sub.assign(participant_key="pooled"), sensitivity)
            pooled.to_csv(args.out / f"{split}{suffix}_pooled_descriptive.csv", index=False)
            slopes = []
            for (task, present), cell in group.groupby(["task", "target_present"]):
                slope, intercept = np.polyfit(cell.set_size, cell["mean"], 1)
                slopes.append(dict(task=task, target_present=present, slope_ms_per_item=slope,
                                   intercept_ms=intercept, reference="measured participant-average means"))
            pd.DataFrame(slopes).to_csv(args.out / f"{split}{suffix}_slopes.csv", index=False)
    print(f"Imported {len(df):,} trials; split {splits['split_id']}; summaries: {args.summarize}")


if __name__ == "__main__":
    main()
