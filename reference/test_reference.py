"""Assert that the reference simulations reproduce their published behaviour.

Handoff section 7 and phase 1 of section 10.  Run with ``pytest reference``.

What is asserted, and what deliberately is not
----------------------------------------------
The Competitive Guided Search parameter values in the handoff were transcribed
from memory and the handoff itself says to verify them against Moran et al.
(2013) before asserting them.  That paper is not available offline, so these
tests assert the *behavioural* targets the handoff lists -- 2-vs-5 slopes near
43 ms/item present and 95 ms/item absent, feature slopes near 1 ms/item,
misses rising with set size, false alarms under 2 percent -- and never the
parameter numbers themselves.  Those targets are properties of the Wolfe,
Palmer and Horowitz (2010) data, not of the transcription, so they stay valid
whichever way the check comes out.  As it happens the transcribed values
reproduce them closely, which is evidence that the transcription is right.

The GS6 tests are stronger, because ``gs6_sim.py`` is a port of the MATLAB
that Wolfe posted rather than a reconstruction from prose.
"""

from __future__ import annotations

import pathlib
import sys

import numpy as np
import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference import cgs, gs6_sim                       # noqa: E402
from reference.gs_hybrid import DEFAULTS, run_cells, slopes   # noqa: E402
from harness.tasks import SET_SIZES, TASKS, make_display, matches_template  # noqa: E402


# --------------------------------------------------------------------------
# Competitive Guided Search
# --------------------------------------------------------------------------

@pytest.fixture(scope="module")
def cgs_summaries():
    return {t: cgs.summarise(t, n_per_cell=4000, seed=7)
            for t in ("feature", "conjunction", "spatial")}


def test_cgs_spatial_slopes(cgs_summaries):
    """2-vs-5: about 43 ms/item present and 95 ms/item absent."""
    s = cgs_summaries["spatial"]
    assert s["tp_slope"] == pytest.approx(43.0, abs=8.0)
    assert s["ta_slope"] == pytest.approx(95.0, abs=12.0)


def test_cgs_feature_is_efficient(cgs_summaries):
    """Feature search: about 1 ms/item, i.e. flat."""
    s = cgs_summaries["feature"]
    assert abs(s["tp_slope"]) < 3.0
    assert abs(s["ta_slope"]) < 3.0


def test_cgs_conjunction_between(cgs_summaries):
    """Conjunction sits between the two, and absent is steeper than present."""
    f, c, s = (cgs_summaries[k] for k in ("feature", "conjunction", "spatial"))
    assert f["tp_slope"] < c["tp_slope"] < s["tp_slope"]
    assert c["ta_slope"] > c["tp_slope"]


def test_cgs_misses_rise_with_set_size(cgs_summaries):
    for task in ("conjunction", "spatial"):
        m = cgs_summaries[task]["miss_rate"]
        assert m[18] > m[3], f"{task}: miss rate must grow with set size"


def test_cgs_false_alarms_are_rare(cgs_summaries):
    for task, s in cgs_summaries.items():
        assert max(s["fa_rate"].values()) < 0.02, task


def test_cgs_absent_slope_exceeds_present(cgs_summaries):
    for task in ("conjunction", "spatial"):
        s = cgs_summaries[task]
        assert s["ratio"] > 1.8, f"{task}: absent/present slope ratio {s['ratio']:.2f}"


# --------------------------------------------------------------------------
# Guided Search 6
# --------------------------------------------------------------------------

@pytest.fixture(scope="module")
def gs6_half():
    return gs6_sim.summarise(gs6_sim.run_block(prevalence=0.5, n_trials=6000, seed=3))


def test_gs6_slope_ratio_near_three(gs6_half):
    """Wolfe (2021): the absent/present slope ratio is about 3."""
    assert 2.3 < gs6_half["ratio"] < 3.8


def test_gs6_meets_its_error_goal(gs6_half):
    """The adaptive quitting threshold converges on the 8 percent error goal."""
    assert gs6_half["overall_miss"] == pytest.approx(0.08, abs=0.035)


def test_gs6_misses_rise_with_set_size(gs6_half):
    m = gs6_half["miss_rate"]
    assert m[20] > m[5]


def test_gs6_rt_is_linear_in_set_size(gs6_half):
    xs = np.array(gs6_sim.SET_SIZES, float)
    for key in ("hit_rt", "tneg_rt"):
        ys = np.array([gs6_half[key][n] for n in gs6_sim.SET_SIZES], float)
        fit = np.polyval(np.polyfit(xs, ys, 1), xs)
        ss_res = float(np.sum((ys - fit) ** 2))
        ss_tot = float(np.sum((ys - ys.mean()) ** 2))
        assert 1 - ss_res / ss_tot > 0.98, f"{key} is not linear in set size"


def test_gs6_rt_distribution_is_positively_skewed(gs6_half):
    assert gs6_half["hit_rt_skew"] > 0.8


def test_gs6_prevalence_shifts_the_criterion():
    """Low prevalence lowers the start point, so false alarms become rarer and
    the quitting threshold climbs.  Note that in the posted MATLAB the *miss*
    rate moves the other way from the empirical low-prevalence effect, because
    the adaptive rule punishes misses hardest when targets are rare; that is
    the code's behaviour, not a port error, and gs6_sim.py records it."""
    lo = gs6_sim.summarise(gs6_sim.run_block(prevalence=0.1, n_trials=3000, seed=5))
    hi = gs6_sim.summarise(gs6_sim.run_block(prevalence=0.9, n_trials=3000, seed=5))
    assert lo["overall_fa"] < hi["overall_fa"]
    assert lo["final_quit_thresh"] > hi["final_quit_thresh"]
    assert lo["ta_slope"] > hi["ta_slope"]


# --------------------------------------------------------------------------
# Displays
# --------------------------------------------------------------------------

def test_displays_have_exactly_one_target():
    rng = np.random.default_rng(4)
    for task in TASKS:
        for n in SET_SIZES:
            d = make_display(task, n, True, rng)
            assert sum(matches_template(i, task) for i in d.items) == 1
            d = make_display(task, n, False, rng)
            assert sum(matches_template(i, task) for i in d.items) == 0


def test_spatial_display_is_unguided():
    """Colour, orientation, size and luminance are identical for every item, so
    only the identification-only shape slot separates target from distractor."""
    rng = np.random.default_rng(4)
    d = make_display("spatial", 18, True, rng)
    for slot in ("color", "orient", "lum"):
        assert len({getattr(i, slot) for i in d.items}) == 1, slot
    assert len({i.size_deg2 for i in d.items}) == 1
    assert len({i.shape for i in d.items}) == 2


# --------------------------------------------------------------------------
# The hybrid model, phase 1
# --------------------------------------------------------------------------

@pytest.fixture(scope="module")
def hybrid_rows():
    return run_cells(DEFAULTS, n_per_cell=120, seed=0)


def test_hybrid_orders_the_three_tasks(hybrid_rows):
    """Feature flat, conjunction steeper, spatial configuration steepest.

    This is the qualitative claim the architecture has to make at *any*
    parameter setting: it follows from the two-class feature rule alone.  The
    quantitative slope targets belong to the fitted parameter sets and are
    reported in docs/RESULTS.md, not asserted here.
    """
    s = {t: slopes(hybrid_rows, t) for t in TASKS}
    assert abs(s["feature"]["tp"][0]) < 12.0
    assert s["conjunction"]["tp"][0] > s["feature"]["tp"][0]
    assert s["spatial"]["tp"][0] > s["conjunction"]["tp"][0]
    assert s["spatial"]["ta"][0] > s["spatial"]["tp"][0]


def test_hybrid_absent_is_slower_than_present(hybrid_rows):
    for t in ("conjunction", "spatial"):
        s = slopes(hybrid_rows, t)
        assert s["ta"][0] > s["tp"][0], t


def test_hybrid_error_rates_are_plausible(hybrid_rows):
    for t in TASKS:
        s = slopes(hybrid_rows, t)
        assert max(s["fa"].values()) < 0.10, f"{t}: too many false alarms"
        assert max(s["miss"].values()) < 0.35, f"{t}: too many misses"


def test_hybrid_needs_more_fixations_for_spatial(hybrid_rows):
    """Shape has the steepest acuity slope, so 2-vs-5 has to be foveated."""
    f = slopes(hybrid_rows, "feature")["mean_fixations"]
    s = slopes(hybrid_rows, "spatial")["mean_fixations"]
    assert s > 2 * f
