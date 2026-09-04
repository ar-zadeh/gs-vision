"""Download the GS6 MATLAB simulation that ``gs6_sim.py`` was ported from.

The file is posted publicly by Jeremy Wolfe on OSF, project "Guided Search
6.0" (https://osf.io/9n4hf/), but it carries no explicit licence, so it is
not committed to this repository.  Run this script to put a copy in
``reference/vendor/`` for comparison; nothing in the project imports it.

Usage::

    python reference/fetch_gs6_matlab.py
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import urllib.request

OSF_NODE = "9n4hf"
API = f"https://api.osf.io/v2/nodes/{OSF_NODE}/files/osfstorage/"
VENDOR = pathlib.Path(__file__).resolve().parent / "vendor"
# Recorded 2026-09-04; the OSF file id and size are checked, not pinned.
EXPECTED_NAME = "GS6publicAsPostedJan2021.m"
EXPECTED_SIZE = 22961


def _get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def main() -> int:
    VENDOR.mkdir(parents=True, exist_ok=True)
    root = _get_json(API)
    folders = [d for d in root["data"] if d["attributes"]["kind"] == "folder"]
    if not folders:
        print("No folders in the OSF project; layout changed.")
        return 1
    code = _get_json(folders[0]["relationships"]["files"]["links"]["related"]["href"])
    for f in code["data"]:
        a = f["attributes"]
        if a["kind"] != "file":
            continue
        dest = VENDOR / a["name"]
        with urllib.request.urlopen(f["links"]["download"], timeout=120) as r:
            blob = r.read()
        dest.write_bytes(blob)
        digest = hashlib.sha256(blob).hexdigest()[:16]
        note = ""
        if a["name"] == EXPECTED_NAME and len(blob) != EXPECTED_SIZE:
            note = (f"  (WARNING: {len(blob)} bytes, expected {EXPECTED_SIZE}; "
                    "the upstream file changed since the port was written)")
        print(f"{dest}  {len(blob)} bytes  sha256:{digest}{note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
