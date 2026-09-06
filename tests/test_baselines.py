"""Behavioural checks for the comparison models in ``reference/baselines.py``.

These assert structural properties that each model family is known for, not
fitted values: the serial model's 2:1 slope ratio, the stock ACT-R loop's
235 ms per item, CGS reproducing the Wolfe et al. (2010) 2-vs-5 slopes at the
handoff's transcription of the published values, and that every model runs
through the shared observer plan and yields a finite objective.
"""
from __future__ import annotations

import pathlib
import sys

import numpy as np
import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference.baselines import MODELS, CGS, SerialFIT, ACTRStockFinst20, cell_cost, simulate  # noqa: E402
from reference.gs_hybrid import slopes  # noqa: E402
from harness.fit import synthetic_target  # noqa: E402


@pytest.mark.parametrize("name", sorted(MODELS))
def test_every_model_runs_and_scores(name):
    rows = simulate(MODELS[name](), n_per_cell=20, seed=3)
    assert len(rows) == 3 * 8 * 20
    assert all(np.isfinite(r["rt"]) or r["timed_out"] for r in rows)
    for task in ("feature", "conjunction", "spatial"):
        c = cell_cost(rows, task, synthetic_target(task))
        assert np.isfinite(c)


def test_serial_model_has_two_to_one_slope_ratio():
    rows = simulate(SerialFIT(dict(p_miss=0.0, m=0.0)), tasks=("spatial",), n_per_cell=600, seed=5)
    s = slopes(rows, "spatial")
    assert s["ta"][0] / s["tp"][0] == pytest.approx(2.0, abs=0.25)
    assert all(v == 0 for v in s["miss"].values())


def test_cgs_reproduces_published_two_versus_five_slopes():
    rows = simulate(CGS(), tasks=("spatial",), n_per_cell=1500, seed=7)
    s = slopes(rows, "spatial")
    assert s["tp"][0] == pytest.approx(43.0, abs=8.0)
    assert s["ta"][0] == pytest.approx(95.0, abs=12.0)


def test_stock_actr_loop_costs_235_ms_per_item():
    rows = simulate(ACTRStockFinst20(), tasks=("spatial",), n_per_cell=300, seed=9)
    absent = [r for r in rows if not r["target_present"]]
    for r in absent:
        assert r["search_time"] == pytest.approx(0.235 * r["set_size"] + 0.050, abs=1e-9)
    assert not any(r["response"] for r in absent)      # perfect memory, no false alarms


def test_paav_feature_absent_is_one_fixation_then_quit():
    """With no threshold before the first attend and TD = 0 for every green bar,
    PAAV attends one distractor, then the relevancy filter removes every
    remaining zero-top-down item and the request fails."""
    from reference.baselines import PAAV
    rows = simulate(PAAV(), tasks=("feature",), n_per_cell=200, seed=11)
    absent = [r for r in rows if not r["target_present"]]
    assert all(r["n_fixations"] == 1 for r in absent)
    assert not any(r["response"] for r in absent)          # no false alarms


def test_paav_never_revisits_and_never_times_out():
    from reference.baselines import PAAV
    rows = simulate(PAAV(), n_per_cell=100, seed=13)
    assert all(r["n_fixations"] <= r["set_size"] for r in rows)
    assert not any(r["timed_out"] for r in rows)
    present = [r for r in rows if r["target_present"] and r["task"] == "conjunction"]
    assert np.mean([r["correct"] for r in present]) > 0.9   # guidance finds the red vertical
