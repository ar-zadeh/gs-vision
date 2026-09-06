from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
out = root / "data/model/repair_20260905"
scripts = ["human_data", "run_batch", "fit", "repair", "report", "sensitivity",
           "experiments", "study_batch", "eye_audit", "archive_validation"]
with (out / "cli-help-checks.log").open("w", encoding="utf-8") as log:
    for name in scripts:
        command = [sys.executable, f"harness/{name}.py", "--help"]
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=45)
        log.write(f"COMMAND: .venv/Scripts/python.exe harness/{name}.py --help\n")
        log.write(result.stdout + result.stderr + f"EXIT: {result.returncode}\n\n")
        if result.returncode:
            raise RuntimeError(f"Help failed: {name}")
    log.write("10 CLI help checks passed\n")
with (out / "final-environment.txt").open("w", encoding="utf-8") as log:
    for command in (["sbcl", "--version"], [sys.executable, "--version"], [sys.executable, "-m", "pip", "freeze"]):
        subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
print("10 CLI help checks passed; final environment saved")
