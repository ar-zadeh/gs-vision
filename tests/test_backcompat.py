"""Prove that gs-vision leaves existing ACT-R models untouched.

Handoff section 4, hard requirement 1: with ``:gs-enabled t`` any request that
does not use the new API must go straight to ``call-next-method``, and with
``:gs-enabled nil`` the new API is refused and everything else is the stock
module.  In both cases the trace of a model that uses no guided-search feature
must be byte-for-byte what the stock module produces.

How the comparison is made
--------------------------
Each model is run three times in three separate SBCL processes:

1. stock ACT-R, nothing else loaded;
2. gs-vision with ``:gs-enabled t``;
3. gs-vision with ``:gs-enabled nil``.

Each run prints the ACT-R trace to standard output; the trace lines are pulled
out with a regular expression and compared verbatim.  Traces carry no module
version, so no exception is needed for the version string.

Models used
-----------
``models/legacy-check-model.lisp`` plus the tutorial unit 2 and unit 3 models
the handoff names.  The tutorial models that need an experiment window are
driven here with ``add-visicon-features`` instead, which exercises the same
vision code paths without the AGI.

Run with ``pytest tests/test_backcompat.py -v``.  Each case is a separate
SBCL start, so the file takes a few minutes.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import tempfile

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
ACTR_LOAD = (ROOT / "actr7.x" / "load-act-r.lisp").as_posix()
GS_LOAD = (ROOT / "gs-vision" / "load-gs-vision.lisp").as_posix()

# An ACT-R trace line: "   0.050   PROCEDURAL   PRODUCTION-FIRED FIND-LETTER"
TRACE_RE = re.compile(r"^\s{0,8}\d+\.\d{3}\s{2,}[-A-Z0-9]+\s{2,}\S.*$")

DISPLAY = """
(defun tbc-display ()
  (delete-all-visicon-features)
  (add-visicon-features
    (list 'screen-x 350 'screen-y 300 'kind 'text 'value "v" 'color 'black
          'height 10 'width 7)
    (list 'screen-x 450 'screen-y 300 'kind 'text 'value "k" 'color 'black
          'height 10 'width 7)
    (list 'screen-x 550 'screen-y 300 'kind 'text 'value "b" 'color 'black
          'height 10 'width 7)))
"""

CASES = {
    "legacy-check": {
        "model": (ROOT / "models" / "legacy-check-model.lisp").as_posix(),
        "run": 3.0,
    },
    "unit2-demo2": {
        "model": (ROOT / "actr7.x" / "tutorial" / "unit2" / "demo2-model.lisp").as_posix(),
        "run": 3.0,
    },
    "unit2-assignment": {
        "model": (ROOT / "actr7.x" / "tutorial" / "unit2"
                  / "unit2-assignment-model.lisp").as_posix(),
        "run": 3.0,
    },
    "unit3-subitize": {
        "model": (ROOT / "actr7.x" / "tutorial" / "unit3" / "subitize-model.lisp").as_posix(),
        "run": 5.0,
    },
    "unit3-perceptual-motor": {
        "model": (ROOT / "actr7.x" / "tutorial" / "unit3"
                  / "perceptual-motor-issues-model.lisp").as_posix(),
        "run": 5.0,
    },
}


def _script(model: str, run_for: float, mode: str) -> str:
    """Build the Lisp driver for one run.  ``mode`` is stock, on or off."""
    load = ACTR_LOAD if mode == "stock" else GS_LOAD
    enable = ""
    if mode == "on":
        enable = '(sgp :gs-enabled t)'
    elif mode == "off":
        enable = '(sgp :gs-enabled nil)'
    return f"""
(load "{load}")
{DISPLAY}
(load "{model}")
(sgp :v t :trace-detail high :seed (271828 0))
{enable}
(install-device (list "motor" "keyboard"))
(tbc-display)
(format t "~%%===TRACE-START===~%%")
(run {run_for})
(format t "~%%===TRACE-END===~%%")
(finish-output)
(sb-ext:exit :abort t)
"""


def _trace(model: str, run_for: float, mode: str) -> list:
    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False,
                                     dir=tempfile.gettempdir()) as f:
        f.write(_script(model, run_for, mode))
        path = f.name
    try:
        out = subprocess.run(
            ["sbcl", "--dynamic-space-size", "4096", "--non-interactive",
             "--load", path],
            capture_output=True, text=True, timeout=1800, cwd=str(ROOT),
        ).stdout
    finally:
        pathlib.Path(path).unlink(missing_ok=True)
    if "===TRACE-START===" not in out:
        raise RuntimeError(f"{mode} run of {model} produced no trace:\n{out[-3000:]}")
    body = out.split("===TRACE-START===", 1)[1].split("===TRACE-END===", 1)[0]
    return [ln.rstrip() for ln in body.splitlines() if TRACE_RE.match(ln)]


@pytest.fixture(scope="module")
def traces():
    """Run every model in every mode once and cache the traces."""
    out = {}
    for name, spec in CASES.items():
        out[name] = {mode: _trace(spec["model"], spec["run"], mode)
                     for mode in ("stock", "on", "off")}
    return out


@pytest.mark.parametrize("case", list(CASES))
def test_trace_is_not_empty(traces, case):
    assert len(traces[case]["stock"]) > 5, "the stock run produced no usable trace"


@pytest.mark.parametrize("case", list(CASES))
def test_gs_enabled_matches_stock(traces, case):
    """:gs-enabled t must not change a model that uses none of the new API."""
    stock, gs = traces[case]["stock"], traces[case]["on"]
    assert gs == stock, _diff(stock, gs)


@pytest.mark.parametrize("case", list(CASES))
def test_gs_disabled_matches_stock(traces, case):
    stock, gs = traces[case]["stock"], traces[case]["off"]
    assert gs == stock, _diff(stock, gs)


def _diff(a: list, b: list, context: int = 6) -> str:
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            lo = max(0, i - context)
            return ("first difference at trace line %d\n  stock: %s\n  gs   : %s\n"
                    "context:\n%s" % (i, x, y,
                                      "\n".join(f"    {ln}" for ln in a[lo:i + context])))
    return f"traces differ in length: stock {len(a)}, gs {len(b)}"


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
