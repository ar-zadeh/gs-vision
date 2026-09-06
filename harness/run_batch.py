"""Drive the Lisp gs-vision module over the ACT-R remote interface.

Handoff section 8.2.  Starts its own SBCL, connects with the tutorial's
``actr.py``, runs the three benchmark tasks trial by trial, and writes one
trial-level CSV plus one fixation-level CSV per run.

Why the Lisp process is started here rather than attached to
--------------------------------------------------------------
``load-gs-vision.lisp`` calls ``undefine-module :vision``, which prints a
warning and does nothing once a model exists.  Sending it to an already
running ACT-R with ``load_act_r_code`` therefore only works before the first
model is defined, which is not a state a shared session can be relied on to
be in. A private handshake connects each session to its own SBCL; closing
the client and terminating that owned process avoids stale shared sockets.

Between trials the module's per-trial state is cleared with
``gs-reset-search`` rather than ``actr.reset()``.  A full reset would wipe the
adaptive quitting threshold, the priming traces and the prevalence window,
and those have to persist: one model run is one simulated subject.

Usage::

    python harness/run_batch.py --n-per-cell 500 --tag default
    python harness/run_batch.py --n-per-cell 2000 --tag fitted --params data/model/phase1.json
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import types
import time
from dataclasses import replace

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "actr7.x" / "tutorial" / "python"))

from harness.tasks import SET_SIZES, TASKS, TEMPLATES, make_display  # noqa: E402
from harness.parameters import apply as apply_effective, load as load_configuration, lisp_values
from harness.tasks import SCREEN_CENTER_PX
from harness.protocol import observer_plan

LOAD_FILES = {"gs": (ROOT / "gs-vision" / "load-gs-vision.lisp").as_posix(),
              "gs6": (ROOT / "gs6-vision" / "load-gs6-vision.lisp").as_posix()}
LOAD_FILE = LOAD_FILES["gs"]
MODEL_FILE = (ROOT / "models" / "search-model.lisp").as_posix()
TIMEOUT_S = 20.0           # simulated seconds to allow one trial


# --------------------------------------------------------------------------
# Lisp process
# --------------------------------------------------------------------------

class ACTRSession:
    """A private SBCL running ACT-R with gs-vision installed."""

    def __init__(self, verbose: bool = False, startup_timeout: float = 900.0,
                 log_path=None, load_file: str = LOAD_FILE):
        self.verbose = verbose
        self.load_file = load_file
        self.startup_timeout = startup_timeout
        self.log_path = log_path
        self.log = None
        self.proc = None
        self.actr = None
        self._startup_dir = None

    def check_alive(self):
        if self.proc is not None and self.proc.poll() is not None:
            tail = ""
            if self.log_path and pathlib.Path(self.log_path).exists():
                tail = pathlib.Path(self.log_path).read_text(errors="replace")[-2000:]
            raise RuntimeError(
                "SBCL exited (code %s).\n%s" % (self.proc.returncode, tail))

    def __enter__(self):
        self._startup_dir = tempfile.TemporaryDirectory(prefix="gs-actr-")
        handshake = pathlib.Path(self._startup_dir.name) / "dispatcher.txt"
        ready = ('(with-open-file (s "' + handshake.as_posix() + '" '
                 ':direction :output :if-exists :supersede) '
                 '(format s "~{~d~^.~}~%~d~%" (coerce *server-host* \'list) *server-port*))')
        # Keep the Lisp output.  A crash inside SBCL otherwise leaves the run
        # hanging on a dead socket with nothing to read, which is the least
        # debuggable failure this harness can have.
        self.log = open(self.log_path, "w") if self.log_path else None
        self.proc = subprocess.Popen(
            ["sbcl", "--dynamic-space-size", "4096",
             "--load", self.load_file, "--eval", ready, "--eval", "(loop (sleep 1))"],
            stdout=(None if self.verbose else (self.log or subprocess.DEVNULL)),
            stderr=subprocess.STDOUT,
            cwd=str(ROOT),
        )
        try:
            deadline = time.monotonic() + self.startup_timeout
            while time.monotonic() < deadline:
                self.check_alive()
                if handshake.exists() and len(handshake.read_text().splitlines()) == 2:
                    break
                time.sleep(.1)
            else:
                raise TimeoutError("ACT-R did not write its private handshake in time")
            host, port = handshake.read_text().splitlines()
            # The tutorial auto-connects at import. Redirect that one bootstrap
            # in memory to our private endpoint; never edit the vendored file or
            # briefly attach to another process via the shared home port file.
            client_path = ROOT / "actr7.x/tutorial/python/actr.py"
            source = client_path.read_text(encoding="utf-8")
            bootstrap = "current_connection = connection()"
            if source.count(bootstrap) != 1:
                raise RuntimeError("ACT-R tutorial bootstrap changed; review session adapter")
            source = source.replace(bootstrap,
                f"current_connection = start(host={host!r}, port={int(port)})")
            self.actr = types.ModuleType("gs_private_actr")
            self.actr.__file__ = str(client_path)
            exec(compile(source, str(client_path), "exec"), self.actr.__dict__)
            if self.actr.current_connection is None:
                raise RuntimeError("could not connect to the private ACT-R dispatcher")
            return self
        except Exception:
            self.__exit__()
            raise

    def __exit__(self, *exc):
        # Close the client before terminating only the process we own. Each
        # context has a separate module, so nested/repeated sessions stay valid.
        if self.actr is not None and self.actr.current_connection is not None:
            try:
                self.actr.stop()
            except OSError:
                pass
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=15)
        if self.log:
            self.log.close()
        if self._startup_dir:
            self._startup_dir.cleanup()
        return False


# --------------------------------------------------------------------------
# One batch
# --------------------------------------------------------------------------

def param_hash(params: dict) -> str:
    return hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()[:12]


def apply_params(actr, params: dict):
    return apply_effective(actr, params)


def _template_args(task: str) -> tuple:
    tpl = TEMPLATES[task]
    color = tpl.get("color")
    orient = tpl.get("orient")
    shape = tpl.get("shape")
    # orient reaches the model as a channel name, since :guided and gs-search
    # both accept a channel symbol in place of a number (handoff section 5.7)
    orient_name = None
    if orient is not None:
        a = abs(float(orient))
        orient_name = "steep" if a < 22.5 else ("shallow" if a > 67.5 else
                                                ("right" if orient > 0 else "left"))
    return color, orient_name, shape


def run_batch(actr, tasks, set_sizes, n_per_cell, seed, params, out_dir, tag,
              progress=True, prevalence: float = 0.5, priming: bool = False,
              session=None, practice=30, trial_gap=2.0, study="benchmark"):
    """Run one block.

    ``prevalence`` is the proportion of target-present trials; at 0.5 the plan
    is balanced exactly, otherwise presence is sampled.  ``priming`` alternates
    the feature target's colour in runs, so that repeat and switch trials can
    be compared (phase 6).
    """
    import numpy as np
    from tqdm import tqdm

    actr.load_act_r_model(MODEL_FILE)
    # :seed is a model parameter, so it has to be set after the model loads;
    # setting it before only draws "no current model" and is ignored.
    actr.set_parameter_value(":seed", [seed, 0])
    effective = apply_params(actr, params)
    phash = param_hash(effective)

    response = {"key": None, "time": None}

    def on_key(model, key):
        if key in ("j", "f") and response["key"] is None:
            response["key"] = key
            response["time"] = actr.get_time()
            said = key == "j"
            outcome = ("hit" if said else "miss") if response["present"] else ("fa" if said else "tn")
            actr.call_command("gs-trial-feedback", outcome)

    actr.add_command("gs-batch-key", on_key, "Record the model's keypress.")
    actr.monitor_command("output-key", "gs-batch-key")
    actr.install_device(["motor", "keyboard"])

    trial_rows, fix_rows, event_rows = [], [], []
    rng = np.random.default_rng(seed + 1000)
    plan, practices, blocks, task_rngs = [], [], [], {}
    for task in tasks:
        entries, task_rngs[task] = observer_plan(task, set_sizes, n_per_cell, seed, practice, prevalence)
        plan.extend((task, n, p) for n, p, _, _ in entries)
        practices.extend(pr for _, _, pr, _ in entries)
        blocks.extend(b for _, _, _, b in entries)

    # Priming: hold the target colour for a run of 1 to 4 trials, then switch.
    colors, cur, left = [], "red", 0
    for _ in plan:
        if not priming:
            colors.append("red")
            continue
        if left == 0:
            cur = "green" if cur == "red" else "red"
            left = int(rng.integers(1, 5))
        colors.append(cur)
        left -= 1

    it = tqdm(plan, desc=f"{tag} seed{seed}", disable=not progress)
    for trial, (task, n, present) in enumerate(it):
        if trial > 0 and task != plan[trial - 1][0]:
            actr.reset()
            actr.set_parameter_value(":seed", [seed, 0])
            effective = apply_params(actr, params)
            actr.install_device(["motor", "keyboard"])
        tcolor = colors[trial]
        distractor_present = present if study == "capture" else None
        if study == "capture":
            from harness.tasks import make_singleton_display
            col = str(task_rngs[task].choice(["red", "blue"]))
            display = make_singleton_display(n, present, task_rngs[task], distractor_color=col)
            present = True
        else:
            display = make_display(task, n, present, task_rngs[task], target_color=tcolor)
        if study == "unknown_priming":
            display.items = [replace(it, shape="two" if it.is_target else "five") for it in display.items]
        response["key"] = None
        response["time"] = None
        response["present"] = present
        actr.call_command("gs-reset-search")
        actr.delete_all_visicon_features()
        actr.call_command("gs-benchmark-gaze", *SCREEN_CENTER_PX)
        t0 = actr.get_time()
        actr.add_visicon_features(*display.visicon_features())
        color, orient, shape = _template_args(task)
        if task == "feature":
            color = tcolor
        setup_task = task
        if study == "capture":
            setup_task, color, orient, shape = "singleton", None, "shallow", None
        elif study == "unknown_priming":
            setup_task, color, orient, shape = "spatial", None, None, "two"
        actr.call_command("gs-trial-setup", setup_task, color, orient, shape)

        actr.run(TIMEOUT_S, False)
        loop_end = actr.get_time()
        rt_ms = response["time"] - t0 if response["time"] is not None else None

        key = response["key"]
        said_present = key == "j"
        correct = said_present == present
        label = ("hit" if said_present else "miss") if present else \
                ("fa" if said_present else "tn")
        if key is None:
            actr.call_command("gs-cancel-search")
        next_onset = (response["time"] if key is not None else loop_end) + trial_gap * 1000
        if actr.get_time() > next_onset:
            raise RuntimeError("Event-loop return exceeded the declared intertrial interval")
        actr.run_full_time((next_onset - actr.get_time()) / 1000, False)

        if session is not None and trial % 50 == 0:
            session.check_alive()
        stats = actr.call_command("gs-search-stats") or [0, 0, 0, "none"]
        events = actr.call_command("gs-event-log") or []
        request_time = next((e[0] for e in events if e[1] == "request"), None)
        result_time = next((e[0] for e in events if e[1] in ("buffer", "failure")), None)
        state = actr.call_command("gs-state")
        trial_rows.append({
            "subject_seed": seed, "task": task, "trial": trial, "set_size": n,
            "target_present": int(present),
            "response": "" if key is None else key,
            "correct": int(correct) if key is not None else "",
            "rt_ms": rt_ms if key is not None else "",
            "n_fixations": stats[0], "n_rejected": stats[1],
            # the module's own search time, excluding the production and motor
            # path, so it can be compared with the Python mirror directly
            "search_ms": stats[2],
            "quit_reason": stats[3], "param_hash": phash,
            "timed_out": int(key is None),
            "stimulus_ms": t0, "keypress_ms": response["time"], "loop_end_ms": loop_end,
            "request_ms": request_time, "result_ms": result_time,
            "practice": int(practices[trial]), "qt_scale": state[0],
            "block": blocks[trial],
            "feedback_count": state[2],
            "start_offset": state[3] if len(state) > 3 else "",
            "target_color": tcolor,
            "color_repeat": int(trial > 0 and colors[trial - 1] == tcolor),
            "prevalence": prevalence,
            "study": study, "distractor_present": distractor_present,
        })
        for idx, fx in enumerate(actr.call_command("gs-fixation-log") or []):
            fix_rows.append({"trial": trial, "task": task, "subject_seed": seed,
                             "practice": int(practices[trial]), "idx": idx, "t": fx[0],
                             "x": round(fx[1], 1), "y": round(fx[2], 1),
                             "dur": fx[3]})
        for timestamp, kind, item in events:
            event_rows.append(dict(trial=trial, task=task, subject_seed=seed,
                                   t_ms=timestamp, kind=kind, item=item))

    actr.remove_command_monitor("output-key", "gs-batch-key")
    actr.remove_command("gs-batch-key")

    out_dir.mkdir(parents=True, exist_ok=True)
    trials_path = out_dir / f"{tag}_seed{seed}_trials.csv"
    fix_path = out_dir / f"{tag}_seed{seed}_fixations.csv"
    _write_csv(trials_path, trial_rows)
    _write_csv(fix_path, fix_rows)
    _write_csv(out_dir / f"{tag}_seed{seed}_events.csv", event_rows)
    (out_dir / f"{tag}_seed{seed}_manifest.json").write_text(json.dumps(dict(
        schema_version=1, run_id=f"{tag}_seed{seed}", requested=params, effective=effective,
        effective_hash=phash, seed=seed, tasks=list(tasks), set_sizes=list(set_sizes),
        retained_per_cell=n_per_cell, synthetic_practice_per_block=practice,
        total_rt="stimulus_ms to first valid keypress_ms", fixation_window="request to result",
        gaze="untimed central fixation; preparation history reset; learned state retained",
        task_state="separate participant per task", feedback="requested at keypress, production 50 ms later",
        trial_gap_seconds=trial_gap,
        prevalence=prevalence, study=study), indent=2))
    return trials_path, fix_path, trial_rows


def _write_csv(path: pathlib.Path, rows: list):
    if not rows:
        path.write_text("")
        return
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


# --------------------------------------------------------------------------

def load_params(path: str | None, task_key: str = "shared") -> dict:
    """Translate a fit.json entry into :gs-* parameter settings."""
    from harness.parameters import check_response_contract
    params = load_configuration(path, task_key)
    check_response_contract(params)
    return lisp_values(params)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", nargs="*", default=list(TASKS))
    ap.add_argument("--set-sizes", nargs="*", type=int, default=list(SET_SIZES))
    ap.add_argument("-n", "--n-per-cell", type=int, default=100)
    ap.add_argument("--seeds", nargs="*", type=int, default=[1])
    ap.add_argument("--tag", default="default")
    ap.add_argument("--params", default=None, help="fit.json written by fit.py")
    ap.add_argument("--params-key", default="shared")
    ap.add_argument("--out", default=str(ROOT / "data" / "model"))
    ap.add_argument("--verbose", action="store_true", help="show the Lisp output")
    ap.add_argument("--prevalence", type=float, default=0.5,
                    help="proportion of target-present trials (phase 6)")
    ap.add_argument("--priming", action="store_true",
                    help="alternate the feature target colour in runs (phase 6)")
    ap.add_argument("--practice", type=int, default=30, help="synthetic practice trials per block; recorded separately")
    ap.add_argument("--module", choices=sorted(LOAD_FILES), default="gs",
                    help="which vision module to load: gs (gs-vision) or gs6 (gs6-vision)")
    args = ap.parse_args()

    params = load_params(args.params, args.params_key)
    if params:
        print("parameters:", params)

    log_path = pathlib.Path(args.out) / f"{args.tag}_lisp.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with ACTRSession(verbose=args.verbose, log_path=log_path, load_file=LOAD_FILES[args.module]) as s:
        for seed in args.seeds:
            t, f, rows = run_batch(s.actr, args.tasks, args.set_sizes,
                                   args.n_per_cell, seed, params,
                                   pathlib.Path(args.out), args.tag,
                                   prevalence=args.prevalence, priming=args.priming,
                                   session=s, practice=args.practice)
            done = sum(1 for r in rows if r["rt_ms"] != "")
            print(f"seed {seed}: {len(rows)} trials, {done} responded -> {t.name}, {f.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
