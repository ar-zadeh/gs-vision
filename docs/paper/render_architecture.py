"""Export Figure 1's authored HTML diagram as SVG and a 3x PNG.

Run from any directory: python docs/paper/render_architecture.py
Requires a local Chrome or Edge installation; no browser downloads are needed.
"""

from pathlib import Path
import os
import re
import subprocess
import tempfile


def main():
    figures = Path(__file__).resolve().parent / "figs"
    source = (figures / "fig_architecture.html").read_text(encoding="utf-8")
    svg = re.search(r'<svg viewBox="0 0 1390 820".*?</svg>', source, re.S).group()
    svg = svg.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ', 1)
    (figures / "fig_architecture.svg").write_text(svg, encoding="utf-8")
    browsers = [
        Path(os.environ.get("PROGRAMFILES", "C:/Program Files"))
        / "Google/Chrome/Application/chrome.exe",
        Path(os.environ.get("PROGRAMFILES(X86)", "C:/Program Files (x86)"))
        / "Microsoft/Edge/Application/msedge.exe",
    ]
    browser = next((path for path in browsers if path.is_file()), None)
    if browser is None:
        raise SystemExit("Install Chrome or Edge to render the PNG; SVG was exported.")
    with tempfile.TemporaryDirectory(prefix="gs-vision-figure1-") as temporary:
        page = Path(temporary) / "figure.html"
        page.write_text(
            '<!doctype html><meta charset="utf-8"><style>'
            'html,body{margin:0;background:white;width:1390px;height:820px;overflow:hidden}'
            'svg{display:block;width:1390px;height:820px}</style>' + svg,
            encoding="utf-8",
        )
        subprocess.run(
            [str(browser), "--headless", "--disable-gpu", "--hide-scrollbars",
             "--no-first-run", "--no-default-browser-check",
             f"--user-data-dir={temporary}/profile", "--window-size=1390,820",
             "--force-device-scale-factor=3",
             f"--screenshot={figures / 'fig_architecture.png'}", page.as_uri()],
            check=True, capture_output=True, timeout=60,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    print("Exported fig_architecture.svg and fig_architecture.png")


if __name__ == "__main__":
    main()
