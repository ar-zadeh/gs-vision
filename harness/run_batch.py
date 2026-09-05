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
be in.  Starting a private SBCL and shutting it down with the module's
``gs-quit-lisp`` command is deterministic.

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
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "actr7.x" / "tutorial" / "python"))

from harness.tasks import SET_SIZES, TASKS, TEMPLATES, make_display  # noqa: E402

LOAD_FILE = (ROOT / "gs-vision" / "load-gs-vision.lisp").as_posix()
MODEL_FILE = (ROOT / "models" / "search-model.lisp").as_posix()
PORT_FILE = pathlib.Path.home() / "act-r-port-num.txt"
TIMEOUT_S = 20.0           # simulated seconds to allow one trial


# --------------------------------------------------------------------------
# Lisp process
# --------------------------------------------------------------------------

class ACTRSession:
    """A private SBCL running ACT-R with gs-vision installed."""

    def __init__(self, verbose: bool = False, startup_timeout: float = 900.0,
                 log_path=None):
        self.verbose = verbose
        self.startup_timeout = startup_timeout
        self.log_path = log_path
        self.log = None
        self.proc = None
        self.actr = None

    def check_alive(self):
        if self.proc is not None and self.proc.poll() is not None:
            tail = ""
            if self.log_path and pathlib.Path(self.log_path).exists():
                tail = pathlib.Path(self.log_path).read_text(errors="replace")[-2000:]
            raise RuntimeError(
                "SBCL exited (code %s).\n%s" % (self.proc.returncode, tail))

    def __enter__(self):
        stamp_before = PORT_FILE.stat().st_mtime if PORT_FILE.exists() else 0.0
        # Keep the Lisp output.  A crash inside SBCL otherwise leaves the run
        # hanging on a dead socket with nothing to read, which is the least
        # debuggable failure this harness can have.
        self.log = open(self.log_path, "w") if self.log_path else None
        self.proc = subprocess.Popen(
            ["sbcl", "--dynamic-space-size", "4096",
             "--load", LOAD_FILE, "--eval", "(loop (sleep 1))"],
            stdout=(None if self.verbose else (self.log or subprocess.DEVNULL)),
            stderr=subprocess.STDOUT,
            cwd=str(ROOT),
        )
        deadline = time.time() + self.startup_timeout
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"SBCL exited during startup (code {self.proc.returncode})")
            if PORT_FILE.exists() and PORT_FILE.stat().st_mtime > stamp_before:
                time.sleep(2.0)      # let the dispatcher finish coming up
                break
            time.sleep(1.0)
        else:
            raise TimeoutError("ACT-R did not write its port file in time")

        import actr                                              # noqa: E402
        self.actr = actr
        # actr.py connects at import time and leaves the handle in a module
        # variable, not behind a function.
        if actr.current_connection is None:
            raise RuntimeError("could not connect to the ACT-R dispatcher")
        return self

    def _quit_lisp(self):
        try:
            self.actr.call_command("gs-quit-lisp")
        except Exception:
            pass

    def __exit__(self, *exc):
        # gs-quit-lisp kills SBCL in the middle of answering, so the client
        # never sees a reply and actr.py blocks on the socket forever.  Send it
        # from a daemon thread, give it five seconds, then take the process
        # down directly.  Without this the harness writes its CSV and then
        # hangs, which looks exactly like a slow run.
        if self.actr is not None:
            t = threading.Thread(target=self._quit_lisp, daemon=True)
            t.start()
            t.join(5.0)
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if self.log:
            self.log.close()
        return False


# --------------------------------------------------------------------------
# One batch
# --------------------------------------------------------------------------

def param_hash(params: dict) -> str:
    return hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()[:12]


def apply_params(actr, params: dict):
    for name, value in params.items():
        actr.set_parameter_value(name, value)


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
              session=None):
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
    apply_params(actr, params)
    phash = param_hash(params)

    response = {"key": None}

    def on_key(model, key):
        response["key"] = key

    actr.add_command("gs-batch-key", on_key, "Record the model's keypress.")
    actr.monitor_command("output-key", "gs-batch-key")
    actr.install_device(["motor", "keyboard"])

    trial_rows, fix_rows = [], []
    rng = np.random.default_rng(seed)
    if abs(prevalence - 0.5) < 1e-9:
        plan = [(t, n, p) for t in tasks for n in set_sizes for p in (True, False)
                for _ in range(n_per_cell)]
    else:
        plan = [(t, n, bool(rng.random() < prevalence))
                for t in tasks for n in set_sizes for _ in range(2 * n_per_cell)]
    rng.shuffle(plan)

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
        tcolor = colors[trial]
        display = make_display(task, n, present, rng, target_color=tcolor)
        response["key"] = None
        actr.delete_all_visicon_features()
        actr.call_command("gs-reset-search")
        actr.add_visicon_features(*display.visicon_features())
        color, orient, shape = _template_args(task)
        if task == "feature":
            color = tcolor
        actr.call_command("gs-trial-setup", task, color, orient, shape)

        t0 = actr.get_time()
        actr.run(TIMEOUT_S, False)
        rt_ms = actr.get_time() - t0

        key = response["key"]
        said_present = key == "j"
        correct = said_present == present
        label = ("hit" if said_present else "miss") if present else \
                ("fa" if said_present else "tn")
        if key is not None:
            actr.call_command("gs-trial-feedback", label)
            actr.run(1.0, False)          # let report-outcome fire

        if session is not None and trial % 50 == 0:
            session.check_alive()
        stats = actr.call_command("gs-search-stats") or [0, 0, 0, "none"]
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
            "target_color": tcolor,
            "color_repeat": int(trial > 0 and colors[trial - 1] == tcolor),
            "prevalence": prevalence,
        })
        for idx, fx in enumerate(actr.call_command("gs-fixation-log") or []):
            fix_rows.append({"trial": trial, "idx": idx, "t": fx[0],
                             "x": round(fx[1], 1), "y": round(fx[2], 1),
                             "dur": fx[3]})

    actr.remove_command_monitor("output-key", "gs-batch-key")
    actr.remove_command("gs-batch-key")

    out_dir.mkdir(parents=True, exist_ok=True)
    trials_path = out_dir / f"{tag}_seed{seed}_trials.csv"
    fix_path = out_dir / f"{tag}_seed{seed}_fixations.csv"
    _write_csv(trials_path, trial_rows)
    _write_csv(fix_path, fix_rows)
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
    if not path:
        return {}
    data = json.loads(pathlib.Path(path).read_text())
    entry = data.get(task_key) or data.get("_de") or {}
    delta = entry.get("delta") or {}
    name_map = {
        "memory": ":gs-memory", "w_e": ":gs-w-e", "noise": ":gs-noise",
        "choice_beta": ":gs-choice-beta", "select_interval": ":gs-select-interval",
        "diffuser_capacity": ":gs-diffuser-capacity", "attn_fvf": ":gs-attn-fvf",
        "max_fixation": ":gs-max-fixation", "w_td": ":gs-w-td", "w_bu": ":gs-w-bu",
        "id_drift": ":gs-id-drift", "id_threshold": ":gs-id-threshold",
        "quit_delta": ":gs-quit-delta",
    }
    return {name_map[k]: v for k, v in delta.items() if k in name_map}


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
    args = ap.parse_args()

    params = load_params(args.params, args.params_key)
    if params:
        print("parameters:", params)

    log_path = pathlib.Path(args.out) / f"{args.tag}_lisp.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with ACTRSession(verbose=args.verbose, log_path=log_path) as s:
        for seed in args.seeds:
            t, f, rows = run_batch(s.actr, args.tasks, args.set_sizes,
                                   args.n_per_cell, seed, params,
                                   pathlib.Path(args.out), args.tag,
                                   prevalence=args.prevalence, priming=args.priming,
                                   session=s)
            done = sum(1 for r in rows if r["rt_ms"] != "")
            print(f"seed {seed}: {len(rows)} trials, {done} responded -> {t.name}, {f.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
