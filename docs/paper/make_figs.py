import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
import numpy as np, sys
OUT = sys.argv[1]
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.edgecolor": "#777", "axes.labelcolor": "#222",
                     "xtick.color": "#444", "ytick.color": "#444", "grid.color": "#e3e3e3"})
BLUE, ORANGE, AQUA, VIOLET, GRAY = "#2a78d6", "#eb6834", "#1baf7a", "#4a3aa7", "#9a9a9a"

# ---------- Figure: model comparison ----------
rows = [  # name, in ACT-R, test, validation
 ("Serial self-terminating (FIT)", False, 80.5, 189.9),
 ("Competitive Guided Search, shared timing", False, 82.9, 184.8),
 ("Competitive Guided Search, per task", False, 98.8, 196.1),
 ("gs-vision, refit", True, 100.1, 173.3),
 ("Fixation-based (Hulleman & Olivers)", False, 105.6, 204.8),
 ("GS6 engine, rates fitted", False, 114.3, 183.0),
 ("gs6-vision, rates fitted", True, 122.5, 191.8),
 ("GS6 engine, as posted", False, 123.3, 170.8),
 ("gs-vision, frozen fit", True, 127.7, 143.1),
 ("Parallel race", False, 129.4, 208.2),
 ("Default ACT-R vision, timing fitted", True, 137.3, 149.6),
 ("PAAV, fitted (mirror)", True, 275.4, 253.1),
 ("gs-vision, module defaults", True, 365.4, 411.1),
 ("PAAV, posted values (mirror)", True, 382.9, 343.5),
 ("Default ACT-R vision, default settings", True, 501.1, 515.5),
]
fig, axes = plt.subplots(1, 2, figsize=(7.5, 4.9), sharey=True)
names = [r[0] for r in rows][::-1]
y = np.arange(len(rows))
for ax, col, title, floor in zip(axes, (2, 3), ("Test participants", "Validation participants"), (93.3, 192.9)):
    vals = [r[col] for r in rows][::-1]
    cols = [BLUE if r[1] else GRAY for r in rows][::-1]
    ax.barh(y, vals, color=cols, height=0.62)
    for yi, v in zip(y, vals):
        ax.text(v + 6, yi, f"{v:.0f}", va="center", fontsize=7.5, color="#222")
    ax.axvline(floor, color=ORANGE, lw=1.4, ls="--")
    ax.set_xlim(0, 600); ax.set_title(title, fontsize=10, loc="left")
    ax.set_xlabel("Mean cell quantile RMSE (ms)" + chr(10) + f"dashed: training-group averages, {floor:.0f} ms", fontsize=8); ax.grid(axis="x"); ax.set_axisbelow(True)
axes[0].set_yticks(y); axes[0].set_yticklabels(names, fontsize=8)
fig.legend(handles=[Patch(color=BLUE, label="ACT-R vision module (default and PAAV: timing mirrors)"),
                    Patch(color=GRAY, label="Trial-level model (no display)")],
           loc="lower center", ncol=2, fontsize=7.5, frameon=False, bbox_to_anchor=(0.56, 0.0))
fig.tight_layout(rect=(0, 0.05, 1, 1)); fig.savefig(f"{OUT}/fig_comparison.png", dpi=300); plt.close(fig)

# ---------- Figure: miss rates ----------
N = [3, 6, 12, 18]
data = {
 "feature":     {"Human": [3.8,3.5,2.9,3.5], "gs-vision refit": [0.9,0.2,0.2,0.5], "gs-vision frozen": [2.0,1.3,2.2,2.7], "CGS shared": [1.6,1.0,1.1,2.1], "gs6-vision fitted": [3.7,5.5,5.2,5.4]},
 "conjunction": {"Human": [2.8,2.1,3.4,6.3], "gs-vision refit": [4.3,8.1,14.6,17.6], "gs-vision frozen": [4.2,5.7,10.0,10.8], "CGS shared": [1.6,2.4,4.5,7.4], "gs6-vision fitted": [18.2,17.5,10.8,8.4]},
 "spatial":     {"Human": [3.7,2.2,5.4,10.0], "gs-vision refit": [4.3,7.5,15.2,19.2], "gs-vision frozen": [3.8,8.3,14.3,20.9], "CGS shared": [2.8,6.2,11.5,13.2], "gs6-vision fitted": [19.1,20.5,11.5,7.4]},
}
style = {"Human": ("#111", "o", "-", 2.2), "gs-vision refit": (BLUE, "s", "-", 1.6), "gs-vision frozen": (BLUE, "^", "--", 1.6),
         "CGS shared": (GRAY, "D", "-", 1.6), "gs6-vision fitted": (VIOLET, "v", ":", 1.6)}
fig, axes = plt.subplots(1, 3, figsize=(7.5, 2.7), sharey=True)
for ax, (task, series) in zip(axes, data.items()):
    for name, vals in series.items():
        c, m, ls, lw = style[name]
        ax.plot(N, vals, marker=m, color=c, ls=ls, lw=lw, ms=5, label=name)
    ax.set_title(f"{task} search", fontsize=10, loc="left"); ax.set_xticks(N); ax.set_xlabel("Set size")
    ax.grid(axis="y"); ax.set_axisbelow(True)
axes[0].set_ylabel("Miss rate on present trials (%)"); axes[0].set_ylim(0, 24)
axes[0].legend(fontsize=7, frameon=False, loc="upper left")
fig.tight_layout(); fig.savefig(f"{OUT}/fig_misses.png", dpi=300); plt.close(fig)
# Figure 1 uses the publication styling in figs/fig_architecture.html.
# Regenerate its SVG and PNG with: python docs/paper/render_architecture.py
print("ok")
