"""Complete, versioned parameter transport shared by fitting and execution.

Two parameter schemas are supported: ``GSParams`` for gs-vision (the frozen
module) and ``GS6Params`` for gs6-vision.  A configuration is recognised by
its keys, so files written before gs6-vision existed load exactly as before.
"""
from dataclasses import asdict, fields
import hashlib
import json
import math
from pathlib import Path

from reference.gs_hybrid import DEFAULTS, GSParams
from reference.gs6_hybrid import DEFAULTS as GS6_DEFAULTS, GS6Params

SCHEMA_VERSION = 1
RESPONSE = {"motor_error", "t_nondecision", "response_first_extra", "response_switch_extra"}
PROTOCOL = {"max_trial_s", "trial_gap"}
STOCK = {name: ":" + name.replace("_", "-") for name in (
    "emma", "saccade_feat_time", "saccade_init_time", "saccade_base_time",
    "eye_saccade_rate", "visual_encoding_factor", "visual_encoding_exponent",
    "vis_obj_freq", "visual_attention_latency")}
MODELS = {GSParams: "gs", GS6Params: "gs6"}
DEFAULTS_OF = {GSParams: DEFAULTS, GS6Params: GS6_DEFAULTS}
GS6_ONLY = {f.name for f in fields(GS6Params)} - {f.name for f in fields(GSParams)}
# Fields added to gs-vision after the September 5 freeze.  Configurations
# written before them load with their defaults, which reproduce the frozen
# behaviour exactly.
OPTIONAL_NEW = {"id_sigma", "id_error", "onset_latency", "adaptive_quit_delta", "explore_proximity",
                "saccade_trigger"}
SECONDS = {"select_interval", "max_fixation", "iconic_span", "priming_tau", "onset_latency",
           "saccade_feat_time", "saccade_init_time", "saccade_base_time",
           "visual_attention_latency", "t_nondecision", "max_trial_s", "trial_gap",
           "response_first_extra", "response_switch_extra", "diff_step"}
_UNIT_OVERRIDES = dict(
    id_drift="evidence/second", id_threshold="evidence", choice_beta="1/priority",
    w_e="priority/degree", saccade_margin="priority", saccade_proximity="priority/degree",
    memory="items", diffuser_capacity="items", feedback_window="trials",
    motor_error="probability", error_goal="probability", qt_init="rejections/effective item",
    id_sigma="evidence/sqrt(second)", id_error="probability",
    diff_inc="evidence/step", diff_noise="multiple of diff_inc", targ_thresh="evidence",
    dist_thresh="evidence", similarity_drift="proportion", start_inc="evidence",
    start_dec="evidence", quit_inc="quit signal/step", quit_noise="multiple of quit_inc",
    quit_ss_ref="effective items", qt_step="quit signal")


def name_map(cls=GSParams) -> dict:
    out = {f.name: ":gs-" + f.name.replace("_", "-") for f in fields(cls)
           if f.name not in RESPONSE | PROTOCOL | STOCK.keys()}
    out.update(STOCK)
    return out


def units(cls=GSParams) -> dict:
    out = {f.name: ("seconds" if f.name in SECONDS else "degrees" if f.name in
                    {"attn_fvf", "explore_fvf", "saccade_trigger"} else "seconds/degree" if f.name ==
                    "eye_saccade_rate" else "model units") for f in fields(cls)}
    if cls is GS6Params:
        out["qt_init"] = "quit signal at quit_ss_ref effective items"
    out.update({k: v for k, v in _UNIT_OVERRIDES.items() if k in out and (k != "qt_init" or cls is GSParams)})
    return out


NAME_MAP = name_map(GSParams)
UNITS = units(GSParams)


def schema_for(values) -> type:
    """The parameter class a configuration dictionary belongs to."""
    return GS6Params if set(values) & GS6_ONLY else GSParams


def validate(values, complete=True):
    cls = schema_for(values)
    names = {f.name for f in fields(cls)}
    unknown = set(values) - names
    missing = names - set(values) - (OPTIONAL_NEW if cls is GSParams else set())
    if unknown or (complete and missing):
        raise ValueError(f"Invalid parameter keys: unknown={sorted(unknown)}, missing={sorted(missing)}")
    merged = asdict(DEFAULTS_OF[cls]) | values
    for name, value in merged.items():
        if isinstance(value, (int, float)) and not math.isfinite(value):
            raise ValueError(f"Nonfinite parameter {name}")
    for name in ("id_drift", "id_threshold", "id_sigma", "select_interval", "max_fixation",
                 "attn_fvf", "explore_fvf", "acuity_sigma", "priming_tau", "error_goal", "max_trial_s",
                 "diff_step", "diff_inc", "diff_noise", "targ_thresh", "quit_inc", "quit_noise",
                 "quit_ss_ref"):
        if name in merged and merged[name] <= 0:
            raise ValueError(f"{name} must be positive")
    if "dist_thresh" in merged and merged["dist_thresh"] >= 0:
        raise ValueError("dist_thresh must be negative")
    for name in ("memory", "diffuser_capacity", "feedback_window"):
        if type(merged[name]) is not int or merged[name] < (0 if name == "memory" else 1):
            raise ValueError(f"{name} must be a valid integer")
    for name in ("noise", "choice_beta", "quit_delta", "qt_init", "qt_step", "iconic_span",
                 "saccade_margin", "saccade_proximity", "trial_gap", "t_nondecision",
                 "response_first_extra", "response_switch_extra", "onset_latency", "saccade_trigger",
                 "start_inc", "start_dec"):
        if name in merged and merged[name] < 0:
            raise ValueError(f"{name} must be nonnegative")
    for name in ("emma", "revised_saccades", "quit_noise_free", "recognition_extra",
                 "adaptive_quit_delta", "explore_proximity", "start_prevalence", "orient_dual",
                 "best_channel"):
        if name in merged and type(merged[name]) is not bool:
            raise ValueError(f"{name} must be boolean")
    if not 0 <= merged["motor_error"] <= 1 or merged["w_v"] != 0:
        raise ValueError("Invalid motor error or unsupported value-hook setting")
    for name in ("id_error", "similarity_drift"):
        if name in merged and not 0 <= merged[name] <= 1:
            raise ValueError(f"{name} must be a probability")
    merged["guiding_features"] = tuple(merged["guiding_features"])
    merged["acuity_theta"] = tuple(tuple(pair) for pair in merged["acuity_theta"])
    return cls(**merged)


def model_name(params) -> str:
    return MODELS[type(params)]


def configuration(params):
    values = asdict(validate(asdict(params)))
    cls = type(params)
    result = dict(schema_version=SCHEMA_VERSION, model=MODELS[cls], params=values, units=units(cls),
                  python_response_parameters=sorted(RESPONSE), protocol_parameters=sorted(PROTOCOL))
    result["config_hash"] = config_hash(values)
    return result


def config_hash(values):
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()


def load(path=None, key="shared"):
    if path is None:
        return DEFAULTS
    data = json.loads(Path(path).read_text())
    if "schema_version" in data and "params" in data:
        entry = data
    else:
        if key not in data:
            raise ValueError(f"Parameter entry {key!r} missing; available: {sorted(data)}")
        entry = data[key]
    if "params" not in entry:
        raise ValueError("Complete params required; legacy delta-only files must be explicitly migrated")
    if entry.get("schema_version", SCHEMA_VERSION) != SCHEMA_VERSION:
        raise ValueError("Unsupported parameter schema")
    if "config_hash" in entry and entry["config_hash"] != config_hash(entry["params"]):
        raise ValueError("Parameter hash does not match effective settings")
    params = validate(entry["params"])
    if "model" in entry and entry["model"] != MODELS[type(params)]:
        raise ValueError(f"Configuration claims model {entry['model']!r} but its keys are {MODELS[type(params)]!r}")
    return params


def lisp_values(params):
    values = asdict(validate(asdict(params)))
    out = {lisp: values[name] for name, lisp in name_map(type(params)).items()}
    return _lisp_finish(out, values)


NEW_LISP_DEFAULTS = {NAME_MAP[name]: getattr(DEFAULTS, name) for name in OPTIONAL_NEW}


def readback_matches(actual, expected):
    """True when a stored effective readback agrees with the expected settings.

    Runs recorded before a parameter existed have no readback for it; they
    agree only when the expected value is that parameter's default."""
    missing = set(expected) - set(actual)
    if set(actual) - set(expected) or missing - set(NEW_LISP_DEFAULTS):
        return False
    if any(not equivalent(expected[k], NEW_LISP_DEFAULTS[k]) for k in missing):
        return False
    return all(equivalent(actual[k], v) for k, v in expected.items() if k in actual)


def _lisp_finish(out, values):
    out[":gs-guiding-features"] = list(values["guiding_features"])
    out[":gs-acuity-theta"] = [v for pair in values["acuity_theta"] for v in pair]
    return out


def check_response_contract(params):
    expected = {"motor_error": 0., "t_nondecision": .160,
                "response_first_extra": .150, "response_switch_extra": .100,
                "trial_gap": 2., "max_trial_s": 20.}
    for name, value in expected.items():
        if getattr(params, name) != value:
            raise ValueError(f"{name} differs from the supported ACT-R response/protocol contract")


def equivalent(actual, expected):
    if isinstance(expected, bool):
        return actual in (True, "T", "t") if expected else actual in (False, None, "NIL", "nil")
    if isinstance(expected, (tuple, list)):
        return isinstance(actual, (tuple, list)) and len(actual) == len(expected) and all(
            equivalent(a, e) for a, e in zip(actual, expected))
    if isinstance(expected, str):
        return str(actual).lower() == expected.lower()
    return actual is not None and math.isclose(float(actual), expected, rel_tol=1e-6, abs_tol=1e-8)


def apply(actr, requested):
    """Check every readback; requested values alone do not establish acceptance."""
    for name, value in requested.items():
        actr.set_parameter_value(name, value)
    effective = {name: actr.get_parameter_value(name) for name in requested}
    for name, value in requested.items():
        if not equivalent(effective[name], value):
            raise ValueError(f"ACT-R rejected {name}: requested {value!r}, got {effective[name]!r}")
    return effective
