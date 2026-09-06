import json
from dataclasses import asdict, replace
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from harness.human_data import import_file, participant_summary, group_summary, split_participants
from harness.parameters import configuration, load, lisp_values, apply, equivalent
from harness.protocol import observer_plan
from harness.tasks import make_display, SCREEN_CENTER_PX
from reference.gs_hybrid import DEFAULTS, GSHybrid, run_cells


def fixture_file(tmp_path, rows):
    path = tmp_path / "feature.txt"
    path.write_text("sinit\tCondReport\ttrialdigit\tsetsize\ttarget present\terror\tmessage\tRT\t\t\n" +
                    "\n".join(rows) + "\n")
    return path


def test_import_preserves_repeats_and_accuracy(tmp_path):
    path = fixture_file(tmp_path, ["a\tF\t1\t3\t1\t0\tHIT\t200\t\t",
                                  "a\tF\t1\t3\t1\t1\tMISS\t0",
                                  "a\tF\t1\t3\t0\t0\tTNEG\t4000",
                                  "a\tF\t1\t3\t0\t1\tFA\t4001"])
    df, audit = import_file(path, "feature")
    assert df.source_row.tolist() == [2, 3, 4, 5]
    assert df.rt_eligible.tolist() == [True, False, True, False]
    assert df.accuracy_eligible.all() and df.error.sum() == 2
    assert audit["repeated_trial_numbers"] == 3
    assert audit["errors_excluded_by_rt"] == 2


@pytest.mark.parametrize("row", ["a\tF\t1\t3\t1\t0\tMISS\t200",
                                  "a\tF\t1\t3\t1\t0\tHIT\t200\tdata\t",
                                  "a\tF\t1\t3\t1\t0\tHIT"])
def test_import_rejects_invalid_rows(tmp_path, row):
    with pytest.raises(ValueError, match=":2:"):
        import_file(fixture_file(tmp_path, [row]), "feature")


def test_equal_participant_quantiles_and_split():
    rows = []
    for i in range(9):
        rows.extend(dict(participant_key=f"feature:f:{i}", task="feature", set_size=3,
                         target_present=1, correct=True, error=0, rt_ms=200 + i * 100,
                         rt_eligible=True, positive_rt_eligible=True) for _ in range(i + 1))
    df = pd.DataFrame(rows)
    out = group_summary(participant_summary(df), bootstrap=100)
    assert out.iloc[0]["mean"] == 600
    assert out.iloc[0].q50 == 600
    a = split_participants(df)
    b = split_participants(df.assign(rt_ms=99999, error=1))
    assert a == b
    assert list(a["assignments"].values()).count("test") == 2


def test_parameter_roundtrip_and_rejection(tmp_path):
    p = replace(DEFAULTS, w_bu=3., id_threshold=.055, id_drift=.35, quit_delta=.08,
                qt_step=.005, qt_init=1.7, saccade_margin=.4, saccade_proximity=.2)
    path = tmp_path / "params.json"
    path.write_text(json.dumps({"_de": configuration(p)}))
    assert load(path, "_de") == p
    assert lisp_values(p)[":gs-w-bu"] == 3
    assert lisp_values(p)[":gs-id-threshold"] == .055
    with pytest.raises(ValueError, match="missing"):
        load(path, "shared")
    path.write_text(json.dumps({"shared": {"delta": {"w_bu": 3}}}))
    with pytest.raises(ValueError, match="Complete"):
        load(path)


def test_actr_readback_required():
    class Rejected:
        def set_parameter_value(self, key, value):
            pass
        def get_parameter_value(self, key):
            return .5
    with pytest.raises(ValueError, match="rejected"):
        apply(Rejected(), {":gs-w-bu": 3})


def test_protocol_retains_exact_cells_with_practice():
    plan, _ = observer_plan("feature", (3, 6, 12, 18), 500, 5, practice=30)
    assert sum(not r[2] for r in plan) == 4000
    assert sum(r[2] for r in plan) == 390
    assert len({r[3] for r in plan}) == 13


def test_fixations_close_without_movement_time_and_state_survives():
    model = GSHybrid(seed=12)
    rng = np.random.default_rng(4)
    for _ in range(3):
        row = model.run_trial(make_display("spatial", 18, True, rng))
        fixations = row["fixations"]
        assert fixations[0][1:3] == SCREEN_CENTER_PX
        assert all(f[3] >= 0 for f in fixations)
        assert all(a[0] + a[3] <= b[0] + 1e-9 for a, b in zip(fixations, fixations[1:]))
        assert fixations[-1][0] + fixations[-1][3] <= row["search_time"] + 1e-9
        assert len(fixations) == row["n_fixations"]
    assert len(model.feedback) == 3
    assert model.clock > sum(r[3] for r in fixations)


def test_timeout_not_success_or_feedback():
    model = GSHybrid(replace(DEFAULTS, max_trial_s=.001), seed=2)
    row = model.run_trial(make_display("feature", 3, False, np.random.default_rng(4)))
    assert row["timed_out"] and not row["correct"] and row["response"] is None
    assert not model.feedback
    assert row["search_time"] == .001


def test_missing_real_targets_fail():
    from harness.fit import quantile_cost
    with pytest.raises(ValueError, match="Validated human"):
        quantile_cost("feature", DEFAULTS, 5, 0)


def test_timeout_rows_survive_analysis(tmp_path):
    from harness.analyze import load_trials
    path = tmp_path / "trials.csv"
    path.write_text("rt_ms,correct,target_present,timed_out\n, ,1,1\n500,1,0,0\n".replace(", ,", ",,"))
    df = load_trials(path)
    assert len(df) == 2 and df.timed_out.sum() == 1


def test_report_regeneration_preserves_narrative(tmp_path):
    from harness.report import replace_generated, BEGIN, END
    path = tmp_path / "report.md"
    path.write_text(f"User narrative\n{BEGIN}\nold table\n{END}\nUser conclusion")
    replace_generated(path, "new table")
    once = path.read_text()
    replace_generated(path, "new table")
    assert path.read_text() == once
    assert once.startswith("User narrative") and once.endswith("User conclusion")
    assert "old table" not in once


def test_report_missing_inputs_fail(tmp_path):
    from harness.evaluate import evaluate_manifest
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps({"human": "missing", "runs": []}))
    with pytest.raises(FileNotFoundError):
        evaluate_manifest(path, tmp_path / "out")


def test_complete_transport_in_real_actr(tmp_path):
    from harness.run_batch import ACTRSession, MODEL_FILE, run_batch
    p = replace(DEFAULTS, w_bu=3., id_drift=.35, id_threshold=.055,
                qt_step=.005, qt_init=1.7, quit_delta=.08,
                saccade_margin=.4, saccade_proximity=.2, select_interval=.0274)
    assert p.select_interval == .027
    with ACTRSession(log_path=tmp_path / "actr.log") as session:
        session.actr.load_act_r_model(MODEL_FILE)
        actual = apply(session.actr, lisp_values(p))
        assert actual[":gs-w-bu"] == 3.
        assert equivalent(session.actr.call_command("gs-state")[0], 1.7)
        _, _, rows = run_batch(session.actr, ("feature",), (3,), 2, 15,
                               lisp_values(p), tmp_path, "roundtrip", progress=False,
                               practice=0, session=session)
        assert len(rows) == 4
        for row in rows:
            assert row["rt_ms"] == row["keypress_ms"] - row["stimulus_ms"]
            assert row["search_ms"] == row["result_ms"] - row["request_ms"]
            assert row["loop_end_ms"] >= row["keypress_ms"]
            assert row["feedback_count"] == row["trial"] + 1


def test_capture_distractor_colors_differ_from_background():
    from harness.tasks import make_singleton_display
    rng = np.random.default_rng(2)
    for color in ("red", "blue"):
        display = make_singleton_display(6, True, rng, distractor_color=color)
        assert sum(item.color != "green" for item in display.items) == 1


def test_private_actr_sessions_keep_independent_models(tmp_path):
    from harness.run_batch import ACTRSession, MODEL_FILE
    with ACTRSession(log_path=tmp_path / "first.log") as first:
        first.actr.load_act_r_model(MODEL_FILE)
        first.actr.set_parameter_value(":gs-w-bu", 2.)
        with ACTRSession(log_path=tmp_path / "second.log") as second:
            second.actr.load_act_r_model(MODEL_FILE)
            assert second.actr.get_parameter_value(":gs-w-bu") == .5
            second.actr.set_parameter_value(":gs-w-bu", 3.)
            assert first.actr.get_parameter_value(":gs-w-bu") == 2.
        assert first.actr.get_parameter_value(":gs-w-bu") == 2.


def test_legacy_configuration_loads_with_new_defaults(tmp_path):
    from harness.parameters import OPTIONAL_NEW, readback_matches, NAME_MAP
    values = {k: v for k, v in asdict(DEFAULTS).items() if k not in OPTIONAL_NEW}
    cfg = configuration(DEFAULTS)
    cfg["params"] = values
    from harness.parameters import config_hash
    cfg["config_hash"] = config_hash(values)
    path = tmp_path / "legacy.json"
    path.write_text(json.dumps({"shared": cfg}))
    assert load(path, "shared") == DEFAULTS
    expected = lisp_values(DEFAULTS)
    legacy = {k: v for k, v in expected.items() if k not in {NAME_MAP[n] for n in OPTIONAL_NEW}}
    assert readback_matches(legacy, expected)
    assert not readback_matches(legacy, lisp_values(replace(DEFAULTS, id_error=.01)))
    with pytest.raises(ValueError, match="probability"):
        configuration(replace(DEFAULTS, id_error=1.5))


def test_identification_error_produces_false_alarms_and_misses():
    rng = np.random.default_rng(7)
    model = GSHybrid(replace(DEFAULTS, id_error=1.0), seed=3)
    absent = model.run_trial(make_display("feature", 6, False, rng))
    assert absent["label"] == "fa"
    clean = GSHybrid(DEFAULTS, seed=3)
    assert clean.run_trial(make_display("feature", 6, False, np.random.default_rng(7)))["label"] == "tn"


def test_onset_latency_delays_first_selection():
    rng = np.random.default_rng(9)
    late = GSHybrid(replace(DEFAULTS, onset_latency=.1, attn_fvf=16.), seed=1).run_trial(make_display("spatial", 6, False, rng))
    first_select = next(t for t, kind, _ in late["events"] if kind == "select")
    assert abs(first_select - .15) < 1e-9


def test_adaptive_quit_delta_scales_with_threshold():
    """A higher adaptive scale shrinks the competitive increment, so competitive
    quits come later; with the switch off the scale has no such effect."""
    def rejections(p):
        model = GSHybrid(p, seed=5)
        rng = np.random.default_rng(5)
        total = 0
        for _ in range(25):
            row = model.run_trial(make_display("spatial", 12, False, rng), stop="cgs")
            model.qt_scale = p.qt_init          # hold the scale fixed for the comparison
            total += row["n_rejected"]
        return total / 25
    low = rejections(replace(DEFAULTS, adaptive_quit_delta=True, qt_init=1.0, quit_delta=.05))
    high = rejections(replace(DEFAULTS, adaptive_quit_delta=True, qt_init=4.0, quit_delta=.05))
    off = rejections(replace(DEFAULTS, adaptive_quit_delta=False, qt_init=4.0, quit_delta=.05))
    assert high > low * 1.3
    assert abs(off - low) < abs(high - low)
