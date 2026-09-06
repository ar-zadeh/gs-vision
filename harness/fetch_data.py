"""Download the human validation datasets into ``data/human/``.

Availability checked 2026-09-04:

======================================  =========================================
Wolfe, Palmer and Horowitz (2010)       ``search.bwh.harvard.edu`` does not
                                        respond (connection error), exactly as
                                        the handoff's section 9 warned.  Tier 1
                                        therefore falls back to Adam et al.
                                        (2021), which is section 12 decision 2.
Adam, Patel, Rangan and Serences 2021   https://osf.io/u7wvy/, CC BY 4.0.
                                        Downloaded here: the long-format
                                        aggregate CSVs and the data README.
Wu and Wolfe 2022 (Tier 2)              https://osf.io/vzg28/, reachable; the
                                        eye-tracking files live in per-experiment
                                        components.  ``--tier2`` fetches them.
COCO-Search18, VSGUI10K (Tiers 3-4)     not fetched; report-only tiers.
======================================  =========================================

Usage::

    python harness/fetch_data.py             # Tier 1 (Adam et al. aggregates)
    python harness/fetch_data.py --tier2     # also Wu and Wolfe 2022
    python harness/fetch_data.py --check     # only probe reachability
"""

from __future__ import annotations

import argparse
import json
import pathlib
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
HUMAN = ROOT / "data" / "human"

WOLFE_2010 = "https://search.bwh.harvard.edu/new/data_set_files.html"
ADAM_DATA_NODE = "jmrb8"      # "Data" component of https://osf.io/u7wvy/
WU_WOLFE_NODE = "vzg28"


def _json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def _listing(node: str, href: str | None = None) -> list:
    url = href or f"https://api.osf.io/v2/nodes/{node}/files/osfstorage/"
    entries = []
    while url:
        page = _json(url)
        entries.extend(page.get("data", []))
        url = page.get("links", {}).get("next")
    return entries


def _download(entry: dict, dest_dir: pathlib.Path) -> pathlib.Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / entry["attributes"]["name"]
    if dest.exists():
        return dest                 # preserve already downloaded source bytes
    with urllib.request.urlopen(entry["links"]["download"], timeout=180) as r:
        dest.write_bytes(r.read())
    return dest


def check() -> dict:
    out = {}
    for name, url in (("wolfe2010", WOLFE_2010),
                      ("adam2021", "https://api.osf.io/v2/nodes/u7wvy/"),
                      ("wu_wolfe2022", f"https://api.osf.io/v2/nodes/{WU_WOLFE_NODE}/"),
                      ("vsgui10k", "https://api.osf.io/v2/nodes/hmg9b/")):
        try:
            with urllib.request.urlopen(url, timeout=25) as r:
                out[name] = r.status
        except (urllib.error.URLError, OSError) as e:
            out[name] = f"unreachable: {e.__class__.__name__}"
    return out


def fetch_adam() -> list:
    """Long-format aggregates plus the README: enough for RT and capture cost."""
    got = []
    dest = HUMAN / "adam2021"
    for entry in _listing(ADAM_DATA_NODE):
        a = entry["attributes"]
        if a["kind"] == "file" and a["name"].startswith("README_Data"):
            got.append(_download(entry, dest))
        elif a["kind"] == "folder" and a["name"] == "Aggregate files (csv long)":
            sub = _listing(ADAM_DATA_NODE,
                           entry["relationships"]["files"]["links"]["related"]["href"])
            for f in sub:
                if f["attributes"]["kind"] == "file":
                    got.append(_download(f, dest / "aggregate_long"))
    return got


def fetch_wu_wolfe() -> list:
    """Every file in the UFOV project's components (Tier 2 eye tracking)."""
    got = []
    kids = _json(f"https://api.osf.io/v2/nodes/{WU_WOLFE_NODE}/children/").get("data", [])
    def walk(node, destination, href=None):
        for entry in _listing(node, href):
            if entry["attributes"]["kind"] == "folder":
                walk(node, destination / entry["attributes"]["name"],
                     entry["relationships"]["files"]["links"]["related"]["href"])
            else:
                got.append(_download(entry, destination))
    for kid in kids:
        title = kid["attributes"]["title"].strip().replace(" ", "_")
        walk(kid["id"], HUMAN / "wu_wolfe2022" / title)
    return got


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="only probe reachability")
    ap.add_argument("--tier2", action="store_true", help="also fetch Wu and Wolfe 2022")
    args = ap.parse_args()

    status = check()
    for k, v in status.items():
        print(f"{k:14s} {v}")
    if args.check:
        return 0

    print("\nAdam et al. 2021:")
    for p in fetch_adam():
        print("  ", p.relative_to(ROOT), p.stat().st_size, "bytes")
    if args.tier2:
        print("\nWu and Wolfe 2022:")
        for p in fetch_wu_wolfe():
            print("  ", p.relative_to(ROOT), p.stat().st_size, "bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
