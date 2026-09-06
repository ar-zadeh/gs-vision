# gs-vision

A guided-search vision module for ACT-R 7.31, with its validation against the
Wolfe, Palmer and Horowitz (2010) visual-search benchmark and a comparison
with other models of visual search.

The module is a subclass of the stock ACT-R vision module. It implements a
Guided Search 6 priority map, covert selection into a capacity-limited
asynchronous identification stage (Competitive Guided Search arithmetic),
memory for rejected items, competitive and adaptive quitting, per-feature
acuity with iconic memory, and EMMA saccades. Existing models run unchanged.

| Where | What |
|---|---|
| `gs-vision/` | The module (Common Lisp). Start with [gs-vision/README.md](gs-vision/README.md). |
| `gs6-vision/` | A variant that uses Wolfe's posted Guided Search 6 engine instead. |
| `models/search-model.lisp` | The benchmark model used in the paper. |
| `reference/` | Python mirror of the module (`gs_hybrid.py`), the posted GS6 simulation, and the comparison models (`baselines.py`). |
| `harness/` | Human data import, display generation, ACT-R driver, fitting, evaluation and reports. |
| `tests/` | Lisp event assertions and Python tests. |
| `docs/paper/` | The Behavior Research Methods tutorial manuscript (`paper.md`, `.docx`, figures). |
| `docs/RESULTS*.md`, `docs/validation-*/` | Validation reports and every generated table and plot. |
| `data/model/*/` | Run records: fitted values, seeds, source hashes, commands and logs. Large trial logs are not committed. |

## Setup

- ACT-R 7.31.4 unpacked at `actr7.x/` (not committed; download from http://act-r.psy.cmu.edu/).
- Steel Bank Common Lisp on the path.
- Python 3.12 with `pip install -r requirements.txt` in a virtual environment at `.venv/`.
- Human data: `python harness/fetch_data.py` downloads the Wolfe et al. (2010) archive and verifies its hashes.

## Running

```
sbcl --load gs-vision/load-gs-vision.lisp          # install the module, then load a model
python harness/run_batch.py --help                  # drive the benchmark model from Python
python harness/report.py --manifest data/model/repair_20260905/run_manifest.json --final-test
python harness/compare_models.py evaluate && python harness/compare_models.py report
sbcl --non-interactive --load tests/test_module_events.lisp
python -m pytest reference/test_reference.py tests/ -q
```

See [HANDOFF.md](HANDOFF.md) for the project state and
[docs/CODE-WALKTHROUGH.md](docs/CODE-WALKTHROUGH.md) for the architecture.
The vendored `paav-visual-module_2014.01.15.lisp` is Nyamsuren and Taatgen's
PAAV module for ACT-R 6 (GPL v3), kept for reference; it is mirrored, not run.
