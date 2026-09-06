"""Assemble every number that ``docs/RESULTS.md`` reports, from the saved runs.

Not part of the handoff's deliverable list; it exists so that no figure in the
report is typed by hand.  Run it after ``run_batch.py`` has produced the CSVs
and ``fit.py`` the parameter files::

    python harness/report.py > docs/results-tables.md

Every table is printed with its human reference beside the model value, and
with the source of the human number named, because section 9 requires each
metric to be reported against the human value, the human-human ceiling and
the best published competitor.
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from harness.analyze import (cell_means, error_table, exgaussian_table,  # noqa: E402
                             fixation_stats, load_trials, quantile_table, slopes)
from harness.fit import TIER1_INTERCEPTS, TIER1_SLOPES                    # noqa: E402

DATA = ROOT / "data" / "model"
TASKS = ("feature", "conjunction", "spatial")


def _fmt(v, nd=1):
    return "-" if v is None or (isinstance(v, float) and not np.isfinite(v)) else f"{v:.{nd}f}"


def table(rows: list, headers: list) -> str:
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---" for _ in headers) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(x) for x in r) + " |")
    return "\n".join(out)


# --------------------------------------------------------------------------

def tier1_slopes() -> str:
    rows = []
    for task in TASKS:
        p = DATA / f"phase1_{task}_seed1_trials.csv"
        if not p.exists():
            continue
        d = load_trials(p)
        s = slopes(d).iloc[0]
        h_tp, h_ta = TIER1_SLOPES[task]
        rows.append([task, "present", _fmt(s.tp_slope), _fmt(h_tp),
                     _fmt(abs(s.tp_slope - h_tp)), _fmt(s.tp_intercept, 0),
                     _fmt(TIER1_INTERCEPTS[task][0], 0)])
        rows.append([task, "absent", _fmt(s.ta_slope), _fmt(h_ta),
                     _fmt(abs(s.ta_slope - h_ta)), _fmt(s.ta_intercept, 0),
                     _fmt(TIER1_INTERCEPTS[task][1], 0)])
    return table(rows, ["task", "target", "model ms/item", "human ms/item",
                        "error", "model intercept", "human intercept"])


def tier1_errors() -> str:
    rows = []
    for task in TASKS:
        p = DATA / f"phase1_{task}_seed1_trials.csv"
        if not p.exists():
            continue
        e = error_table(load_trials(p))
        for kind in ("miss", "false_alarm"):
            sub = e[e.kind == kind].sort_values("set_size")
            rows.append([task, kind] + [_fmt(v, 3) for v in sub.error_rate])
    return table(rows, ["task", "kind", "n=3", "n=6", "n=12", "n=18"])


def lisp_vs_python() -> str:
    rows = []
    for task in TASKS:
        p = DATA / f"phase1_{task}.json"
        if not p.exists():
            continue
        for c in json.loads(p.read_text()).get("lisp_vs_python", []):
            rows.append([task, c["set_size"], "present" if c["target_present"] else "absent",
                         _fmt(c["lisp_mean"], 0), _fmt(c["python_mean"], 0),
                         _fmt(c["difference"], 0), _fmt(c["joint_se"], 1),
                         _fmt(c["z"], 1)])
    return table(rows, ["task", "set size", "target", "Lisp ms", "Python ms",
                        "difference", "joint SE", "z"])


def fixations() -> str:
    rows = []
    for task in TASKS:
        t = DATA / f"phase1_{task}_seed1_trials.csv"
        f = DATA / f"phase1_{task}_seed1_fixations.csv"
        if not (t.exists() and f.exists()):
            continue
        st = fixation_stats(f, load_trials(t))
        rows.append([task, _fmt(st["mean_fixations_per_trial"], 2),
                     _fmt(st["mean_fixation_duration_ms"], 0),
                     _fmt(st["median_fixation_duration_ms"], 0),
                     _fmt(st["mean_saccade_amplitude_deg"], 1),
                     _fmt(st["refixation_rate"], 3)])
    return table(rows, ["task", "fixations/trial", "mean duration ms",
                        "median duration ms", "amplitude deg", "refixation rate"])


def prevalence() -> str:
    rows = []
    for tag, prev in (("prev10", 0.10), ("prev50", 0.50)):
        p = DATA / f"{tag}_seed1_trials.csv"
        if not p.exists():
            continue
        d = load_trials(p)
        # the adaptive threshold needs a burn-in, so drop the first quarter
        d = d[d.trial >= d.trial.quantile(0.25)]
        pres, absent = d[d.target_present], d[~d.target_present]
        rows.append([f"{prev:.0%}",
                     _fmt(1 - pres.correct.mean(), 3),
                     _fmt(1 - absent.correct.mean(), 3),
                     _fmt(absent[absent.correct].rt_ms.mean(), 0),
                     _fmt(pres[pres.correct].rt_ms.mean(), 0),
                     _fmt(absent.n_rejected.mean(), 1), len(d)])
    return table(rows, ["prevalence", "miss rate", "false-alarm rate",
                        "absent RT ms", "present RT ms", "rejections", "trials"])


def priming() -> str:
    p = DATA / "priming_seed1_trials.csv"
    if not p.exists():
        return "_(no priming run found)_"
    d = load_trials(p)
    d = d[d.trial >= d.trial.quantile(0.2)]
    rows = []
    for present in (True, False):
        sel = d[(d.target_present == present) & d.correct]
        rep = sel[sel.color_repeat == 1].rt_ms
        sw = sel[sel.color_repeat == 0].rt_ms
        if len(rep) < 20 or len(sw) < 20:
            continue
        diff = sw.mean() - rep.mean()
        se = float(np.hypot(sw.std(ddof=1) / len(sw) ** 0.5,
                            rep.std(ddof=1) / len(rep) ** 0.5))
        rows.append(["present" if present else "absent",
                     _fmt(rep.mean(), 0), _fmt(sw.mean(), 0),
                     _fmt(diff, 0) + " +- " + _fmt(se, 0),
                     f"{len(rep)}/{len(sw)}"])
    return table(rows, ["target", "repeat ms", "switch ms",
                        "benefit ms", "n repeat/switch"])


def quantiles() -> str:
    rows = []
    for task in TASKS:
        p = DATA / f"phase1_{task}_seed1_trials.csv"
        if not p.exists():
            continue
        q = quantile_table(load_trials(p))
        for _, r in q.iterrows():
            rows.append([task, int(r.set_size),
                         "present" if r.target_present else "absent",
                         _fmt(r.q10, 0), _fmt(r.q30, 0), _fmt(r.q50, 0),
                         _fmt(r.q70, 0), _fmt(r.q90, 0)])
    return table(rows, ["task", "n", "target", ".1", ".3", ".5", ".7", ".9"])


def exgaussian() -> str:
    rows = []
    for task in TASKS:
        p = DATA / f"phase1_{task}_seed1_trials.csv"
        if not p.exists():
            continue
        e = exgaussian_table(load_trials(p))
        for _, r in e.iterrows():
            rows.append([task, int(r.set_size),
                         "present" if r.target_present else "absent",
                         _fmt(r.mu, 0), _fmt(r.sigma, 0), _fmt(r.tau, 0)])
    return table(rows, ["task", "n", "target", "mu", "sigma", "tau"])


def shared_set() -> str:
    p = DATA / "shared_seed1_trials.csv"
    if not p.exists():
        return "_(no shared-parameter run found)_"
    s = slopes(load_trials(p))
    rows = []
    for _, r in s.iterrows():
        h_tp, h_ta = TIER1_SLOPES[r.task]
        rows.append([r.task, _fmt(r.tp_slope), _fmt(h_tp),
                     _fmt(r.ta_slope), _fmt(h_ta), _fmt(r.ratio, 2)])
    return table(rows, ["task", "model present", "human present",
                        "model absent", "human absent", "absent/present"])


SECTIONS = [
    ("Tier 1 slopes and intercepts, per-task parameter sets", tier1_slopes),
    ("Tier 1 error rates", tier1_errors),
    ("One shared parameter set", shared_set),
    ("Lisp module against its Python mirror, module search time", lisp_vs_python),
    ("Eye movements", fixations),
    ("RT quantiles (ms)", quantiles),
    ("Ex-Gaussian fits (ms)", exgaussian),
    ("Prevalence", prevalence),
    ("Priming", priming),
]


def historical_report() -> int:
    print("<!-- generated by harness/report.py; do not edit by hand -->\n")
    for title, fn in SECTIONS:
        print(f"### {title}\n")
        try:
            print(fn() or "_(no data)_")
        except Exception as e:                       # keep going; report the gap
            print(f"_(not available: {e.__class__.__name__}: {e})_")
        print()
    return 0


BEGIN = "<!-- BEGIN VALIDATION GENERATED -->"
END = "<!-- END VALIDATION GENERATED -->"


def replace_generated(destination, generated):
    """Replace only an explicit generated region; preserve all surrounding prose."""
    destination = pathlib.Path(destination)
    text = destination.read_text(encoding="utf-8") if destination.exists() else "# Validation results\n"
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1:
        raise ValueError("Malformed generated-section markers")
    block = BEGIN + "\n\n" + generated.rstrip() + "\n\n" + END
    if BEGIN in text:
        start, tail = text.split(BEGIN)
        _, end = tail.split(END)
        text = start + block + end
    else:
        text += "\n\n" + block + "\n"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")


def validation_report(record, artifact_dir):
    artifact_dir = pathlib.Path(artifact_dir)
    chunks = ["## Raw-data validation\n\n"
              "Human values use validated source trials and equal participant weights. "
              "ACT-R RT runs from stimulus onset to first valid keypress. "
              "Practice is excluded from retained counts. Full cell tables, confidence "
              "intervals, quantiles, and plots are in the evaluation artifact directory.\n\n"
              f"Source rows: {record['human']['total_rows']:,}. "
              f"Split ID: `{record['human']['split_id']}`.\n"]
    rows = []
    for run in record["runs"]:
        for split, result in run["comparisons"].items():
            rows.append([run["id"], run["role"], split,
                         _fmt(result["mean_rt_rmse_ms"]), _fmt(result["mean_quantile_rmse_ms"]),
                         f"{result['slopes_pass']}/{result['slopes_total']}",
                         _fmt(result["max_miss_difference_points"]), result["timeouts"]])
    chunks.append(table(rows, ["Run", "Role", "Split", "Mean RT RMSE (ms)", "Quantile RMSE (ms)",
                              "Slopes within 5 ms/item", "Largest miss error (points)", "Timeouts"]))
    for run in record["runs"]:
        if run["role"] != "primary":
            continue
        for split in run["comparisons"]:
            cells = pd.read_csv(artifact_dir / f"{run['id']}_{split}_cells.csv")
            chunks.append(f"\n### Primary ACT-R fit: {split}\n\n"
                          "These are measured participant-average means. Error rates use "
                          "all behavioral trials independently of RT trimming.\n")
            chunks.append(table([[r.task, r.set_size, "present" if r.target_present else "absent",
                                  _fmt(r.mean_human), _fmt(r.mean_model), _fmt(r.median_human),
                                  _fmt(r.median_model), _fmt(r.quantile_rmse_ms),
                                  _fmt(100*r.error_rate_human, 2), _fmt(100*r.error_rate_model, 2),
                                  r.n_rt_human, r.n_rt_model, r.timeouts] for r in cells.itertuples()],
                                ["Task", "N", "Target", "Human mean", "ACT-R mean", "Human median",
                                 "ACT-R median", "Quantile RMSE", "Human error %", "ACT-R error %",
                                 "Human RT count", "Model RT count", "Timeouts"]))
        if "parity" in run:
            parity = run["parity"]
            chunks.append("\n### Implementation agreement\n\n"
                          f"{parity['min_retained_per_cell']} retained trials per cell or more. "
                          f"{parity['exceeds']} of {parity['cells']} search-time means exceed "
                          f"the Bonferroni family threshold; maximum |z| = {parity['max_abs_z']:.2f}. "
                          "The parity CSV also reports quantile, error, and fixation-count differences.\n")
    chunks.append("\n### Evidence limits\n\n"
                  "Two test participants per task give limited population precision. "
                  "Simulation seeds quantify Monte Carlo variation, not human individual differences. "
                  "Zero false alarms are a structural model limitation. Scanpath agreement "
                  "requires verified per-fixation coordinates and matched trial/display data; "
                  "aggregate fixation counts do not establish it. Historical CGS or GS6 "
                  "simulation output is not a measured human reference.\n")
    return "\n\n".join(chunks)


def main():
    import argparse
    from harness.evaluate import evaluate_manifest
    ap = argparse.ArgumentParser(description="Regenerate validation from explicit manifests without replacing narrative")
    ap.add_argument("--manifest", type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path, default=DATA / "repair_20260905/evaluation")
    ap.add_argument("--destination", type=pathlib.Path, default=ROOT / "docs/RESULTS.md")
    ap.add_argument("--final-test", action="store_true", help="requires a frozen model-selection manifest")
    ap.add_argument("--historical", action="store_true", help="print historical provisional tables, explicitly labeled")
    args = ap.parse_args()
    if args.historical:
        print("HISTORICAL PROVISIONAL TARGETS — NOT RAW HUMAN VALIDATION\n")
        return historical_report()
    if args.manifest is None:
        ap.error("--manifest is required")
    record = evaluate_manifest(args.manifest, args.out, args.final_test)
    replace_generated(args.destination, validation_report(record, args.out))
    print(f"Wrote {args.destination}; artifacts {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
