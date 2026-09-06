"""Tests for the gs6-vision Python mirror and its parameter schema."""
import json
from dataclasses import asdict, replace

import numpy as np
import pytest

from harness.parameters import (GS6_DEFAULTS, DEFAULTS, configuration, load, lisp_values,
                               validate, schema_for)
from harness.tasks import make_display
from reference.gs6_hybrid import GS6Hybrid, GS6Params, orient_channels_dual
from reference.gs_hybrid import GSHybrid, model_for, run_cells


def test_schema_detection_and_roundtrip(tmp_path):
    p = replace(GS6_DEFAULTS, diff_inc=.07, qt_init=2.2, memory=2)
    cfg = configuration(p)
    assert cfg["model"] == "gs6"
    path = tmp_path / "gs6.json"
    path.write_text(json.dumps({"gs6": cfg}))
    assert load(path, "gs6") == p
    assert schema_for(asdict(DEFAULTS)) is not GS6Params
    assert configuration(DEFAULTS)["model"] == "gs"
    lv = lisp_values(p)
    assert lv[":gs-diff-inc"] == .07 and lv[":gs-memory"] == 2
    assert ":gs-id-drift" not in lv
    assert ":gs-id-drift" in lisp_values(DEFAULTS)


def test_schema_rejects_bad_engine_values():
    with pytest.raises(ValueError, match="dist_thresh"):
        validate(asdict(replace(GS6_DEFAULTS, dist_thresh=0.5)))
    with pytest.raises(ValueError, match="similarity_drift"):
        validate(asdict(replace(GS6_DEFAULTS, similarity_drift=1.5)))


def test_frozen_configuration_still_loads():
    assert type(load("docs/validation-20260905/selected.json", "shared")).__name__ == "GSParams"


def test_dual_orientation_channels():
    assert orient_channels_dual(0) == ({"steep": 1.0}, {})
    assert orient_channels_dual(90) == ({"shallow": 1.0}, {})
    o, t = orient_channels_dual(45)
    assert o == pytest.approx({"steep": .5, "shallow": .5})
    assert t == pytest.approx({"right": 1.0})
    o, t = orient_channels_dual(-20)
    assert o == {"steep": 1.0}
    assert t == pytest.approx({"left": 15 / 17.5})


def test_best_channel_guides_a_tilted_target_among_verticals():
    m = GS6Hybrid(GS6_DEFAULTS, seed=1)
    rng = np.random.default_rng(3)
    d = make_display("conjunction", 12, True, rng)
    for it in d.items:
        it.color, it.hue = "green", 120.0
        it.orient = 20.0 if it.is_target else 0.0
    items = m._prepare(d)
    tmpl = m._template_channels({"orient": 20.0}, items)
    assert set(tmpl) == {"orient", "tilt"}
    iconic = {i.idx: {"color": 0.0, "orient": 0.0, "shape": 0.0, "size": 0.0, "lum": 0.0} for i in items}
    _, td = m._priority(items, iconic, [512.0, 384.0], tmpl, 0.0)
    tgt = d.target_index
    assert td[tgt] == pytest.approx(1.0)
    assert all(td[i] <= .5 for i in td if i != tgt)


def test_dispatch_by_parameter_type():
    assert isinstance(model_for(GS6_DEFAULTS, 0), GS6Hybrid)
    assert type(model_for(DEFAULTS, 0)) is GSHybrid
    rows = run_cells(GS6_DEFAULTS, tasks=("feature",), set_sizes=(3,), n_per_cell=3, seed=1)
    assert rows and {"start_point", "quit_sig"} <= set(rows[0])


def test_noise_free_diffuser_timing():
    p = replace(GS6_DEFAULTS, diff_noise=1e-6, quit_noise=1e-6, noise=0.0, w_bu=0.0, choice_beta=50.0)
    m = GS6Hybrid(p, seed=2)
    rng = np.random.default_rng(5)
    present = m.run_trial(make_display("feature", 6, True, rng))
    assert present["label"] == "hit"
    assert .24 <= present["search_time"] <= .30
    absent = m.run_trial(make_display("feature", 6, False, rng))
    assert absent["quit_reason"] == "threshold" and absent["label"] == "tn"
    assert absent["n_eff"] == 1 and absent["qt"] == pytest.approx(.15)
    assert .31 <= absent["search_time"] <= .40


def test_false_alarms_and_misses_are_emergent():
    m = GS6Hybrid(replace(GS6_DEFAULTS, diff_noise=40.0), seed=4)
    rng = np.random.default_rng(6)
    labels = {m.run_trial(make_display("feature", 12, False, rng))["label"] for _ in range(20)}
    assert "fa" in labels
    # A lone target with huge step noise reaches the distractor bound on about
    # half the trials; with a tiny quit threshold that rejection ends the trial.
    m = GS6Hybrid(replace(GS6_DEFAULTS, diff_noise=40.0, qt_init=0.01), seed=4)
    labels = {m.run_trial(make_display("feature", 1, True, rng))["label"] for _ in range(20)}
    assert labels == {"hit", "miss"}


def test_gs6_feedback_rules():
    m = GS6Hybrid(GS6_DEFAULTS, seed=0)
    m.feedback_outcome("tn", 1.0)
    assert m.qt_scale == pytest.approx(1.5 - .005 * .5)
    m.feedback_outcome("miss", 1.0)
    assert m.qt_scale == pytest.approx(1.5 - .0025 + .005 / (.08 * .5 * 2) * .5)
    m.feedback_outcome("hit", 1.0)
    m.feedback_outcome("fa", 1.0)
    assert m.start_offset == pytest.approx(.0008 - .05)
    assert m.start_point == pytest.approx(.0008 - .05)
