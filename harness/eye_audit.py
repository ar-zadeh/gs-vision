"""Audit exported Wu/Wolfe foraging fixations without relabeling them as keypress search.

Run MATLAB's harness/export_eye_data.m first. The table comes from the Results
folder of OSF component qwm6r; RealData.csv is the separate 42/80-item search task.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from harness.metrics import multimatch, scanmatch, sequence_score

INCLUDED = [1,4,5,6,7,10,11,12,13,14,15,16,17,18,19,20,21,22]


def audit(source, destination):
    df = pd.read_csv(source)
    required = {"Subj", "itrial", "nTarget", "iFix", "fixX", "fixY", "PauseTime",
                "TargetX", "TargetYs", "PPD", "N", "SacSize_deg_"}
    if required - set(df):
        raise ValueError(f"Missing fixation fields: {required-set(df)}")
    identity = ["Subj", "itrial", "nTarget"]
    if df.duplicated(identity + ["iFix"]).any():
        raise ValueError("Duplicate fixation identity after distinguishing target episodes")
    if (df.PauseTime < 0).any() or df["PPD"].nunique() != 1:
        raise ValueError("Invalid durations or inconsistent spatial scale")
    part = df[df.Subj.isin(INCLUDED)].copy()
    records, paths = [], []
    for subject, group in part.groupby("Subj"):
        counts = group.groupby(identity).size()
        refix = []
        for keys, episode in group.groupby(identity):
            episode = episode.sort_values("iFix")
            if episode.TargetX.nunique() != 1 or episode.TargetYs.nunique() != 1:
                raise ValueError("Target changes within an episode")
            xy = episode[["fixX", "fixY", "PauseTime"]].to_numpy()
            for i in range(1, len(xy)):
                refix.append(bool((np.linalg.norm(xy[:i,:2]-xy[i,:2],axis=1) < 47.76).any()))
            # Condition-match target grid location and first-gaze grid bin.
            condition = (int(episode.TargetX.iloc[0]), int(episode.TargetYs.iloc[0]),
                         int(xy[0,0]//120), int(xy[0,1]//120))
            if len(xy) >= 3:
                paths.append((subject, condition, xy))
        records.append(dict(subject=subject, episodes=len(counts), fixations=len(group),
            mean_count=float(counts.mean()), duration_ms=float(group.PauseTime.mean()),
            amplitude_deg=float(group["SacSize_deg_"].mean()), refixation_rate=float(np.mean(refix))))
    destination.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(records).to_csv(destination / "eye_human_participants.csv", index=False)
    rng = np.random.default_rng(901)
    subjects = np.array(INCLUDED)
    rng.shuffle(subjects)
    first_half, second_half = set(subjects[:9]), set(subjects[9:])
    first, second = {}, {}
    for subject, condition, path in paths:
        (first if subject in first_half else second).setdefault(condition, []).append(path)
    conditions = sorted(set(first) & set(second))
    rng.shuffle(conditions)
    centroids = np.array([(x,y) for y in range(120,961,120) for x in range(420,1501,120)])
    similarities = []
    for condition in conditions[:100]:
        a = first[condition][int(rng.integers(len(first[condition])))]
        b = second[condition][int(rng.integers(len(second[condition])))]
        similarities.append(dict(target_x=condition[0], target_y=condition[1],
            scanmatch=scanmatch(a,b,screen_size=(1920,1080)),
            sequence_score=sequence_score(a,b,centroids),
            **multimatch(a,b,screen_size=(1920,1080))))
    pd.DataFrame(similarities).to_csv(destination / "eye_human_split_half.csv", index=False)
    raw = ROOT / "data/human/wu_wolfe2022/Exp1Data.mat"
    result = dict(source="https://osf.io/qwm6r/ (Results/Exp1Data.mat)",
        sha256=hashlib.sha256(raw.read_bytes()).hexdigest(), raw_fixations=len(df),
        raw_participants=int(df.Subj.nunique()), included_participants=INCLUDED,
        included_fixations=len(part), participant_selection="author's ufov_analyze_Exp1.m Os list",
        duplicate_trial_fixation_without_target_episode=int(df.duplicated(["Subj","itrial","iFix"]).sum()),
        duplicate_full_records=int(df.duplicated().sum()), episode_identity=identity,
        geometry=dict(screen_pixels=[1920,1080], pixels_per_degree=47.76,
                      item_degrees=[1,1], grid=[10,8], grid_spacing_pixels=120,
                      horizontal_center_span_degrees=1080/47.76, vertical_center_span_degrees=840/47.76),
        task="continuous T-among-L foraging; target always present; click response",
        window="source target episode including pre-click fixations; no stimulus-onset timestamps",
        human_means=pd.DataFrame(records).drop(columns=["subject"]).mean().to_dict(),
        scanpath_split=dict(seed=901, first_half=sorted(map(int, first_half)), second_half=sorted(map(int, second_half)),
                           matched_conditions=len(similarities),
                           matching="target coordinates and initial-gaze 120px bin; rotations unobserved"),
        human_similarity=pd.DataFrame(similarities).drop(columns=["target_x","target_y"]).mean().to_dict(),
        model_comparison="not computed: keypress benchmark ends at visual result; continuous foraging uses "
                         "a click and uncentered starts. Source item rotations and exact onset/result timestamps "
                         "are absent. Human split-half values are conditional descriptive consistency, "
                         "not a ceiling for the unmatched benchmark.")
    (destination / "eye_audit.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result["human_means"], indent=2))
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", type=Path, default=ROOT / "data/model/repair_20260905/eye_exp1.csv")
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/repair_20260905/eye")
    args = ap.parse_args()
    audit(args.source,args.out)


if __name__ == "__main__":
    main()
