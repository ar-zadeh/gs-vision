"""Lisp-versus-mirror parity for gs6-vision with the adaptive controller frozen.

The live model's quitting threshold and start point are slow random walks
driven by the outcome sequence, so two implementations with different random
streams drift apart in adaptive state, and a z-test on their cell means is
anti-conservative even when every mechanism agrees (see
docs/RESULTS-REFIT-20260905.md).  This script runs a candidate in ACT-R and in
the mirror with ``qt_step``, ``start_inc`` and ``start_dec`` set to zero and a
fixed threshold, on the same displays, and writes the parity table.  It is a
mechanism check, not a behavioural result: the frozen threshold is arbitrary.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from harness.evaluate import model_frame, parity                    # noqa: E402
from harness.gs6_fit import candidates_of                            # noqa: E402
from harness.parameters import lisp_values                          # noqa: E402
from harness.run_batch import ACTRSession, LOAD_FILES, run_batch    # noqa: E402
from harness.tasks import SET_SIZES, TASKS                          # noqa: E402
from reference.gs_hybrid import run_cells                           # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=ROOT / "data/model/gs6_20260905")
    ap.add_argument("--docs", type=Path, default=ROOT / "docs/validation-gs6-20260905")
    ap.add_argument("--candidates", nargs="+", required=True)
    ap.add_argument("-n", type=int, default=300)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--qt", type=float, default=4.0, help="frozen threshold scale")
    args = ap.parse_args()
    args.docs.mkdir(parents=True, exist_ok=True)
    work = args.out / "mechanism_parity"
    work.mkdir(exist_ok=True)
    cands = candidates_of(args.out)
    with ACTRSession(log_path=work / "lisp.log", load_file=LOAD_FILES["gs6"]) as session:
        for name in args.candidates:
            p = replace(cands[name], qt_step=0.0, start_inc=0.0, start_dec=0.0, qt_init=args.qt)
            tag = f"{name}_frozenctl"
            trials = work / f"{tag}_seed{args.seed}_trials.csv"
            if not trials.exists():
                run_batch(session.actr, TASKS, SET_SIZES, args.n, args.seed, lisp_values(p), work, tag,
                          session=session, progress=False)
            mirror = work / f"{tag}_mirror_seed{args.seed}.json"
            if not mirror.exists():
                mirror.write_text(json.dumps(run_cells(p, n_per_cell=args.n, seed=args.seed)))
            table = parity(model_frame([trials]), model_frame([mirror], mirror=True))
            table.to_csv(args.docs / f"{name}_parity_frozen_controller.csv", index=False)
            print(name, "frozen-controller parity:", int(table.exceeds_family_threshold.sum()), "of",
                  len(table), "exceed; max |z| =", round(float(table.z.abs().max()), 2), flush=True)


if __name__ == "__main__":
    main()
