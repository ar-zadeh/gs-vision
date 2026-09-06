import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Patch
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
 ("Stock ACT-R vision, timing fitted", True, 137.3, 149.6),
 ("PAAV, fitted (mirror)", True, 275.4, 253.1),
 ("gs-vision, module defaults", True, 365.4, 411.1),
 ("PAAV, posted values (mirror)", True, 382.9, 343.5),
 ("Stock ACT-R vision, defaults", True, 501.1, 515.5),
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
fig.legend(handles=[Patch(color=BLUE, label="ACT-R vision module (PAAV and stock: timing mirrors)"),
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

# ---------- Figure: architecture ----------
NL = chr(10)
fig, ax = plt.subplots(figsize=(7.5, 5.2)); ax.set_xlim(0, 100); ax.set_ylim(-2.5, 70); ax.axis("off")
def box(x, y, w, h, text, fc="#f4f6fa", ec="#3b5a8a", fs=8, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.4,rounding_size=1.2", fc=fc, ec=ec, lw=1.1))
    ax.text(x + w/2, y + h/2, text, ha="center", va="center", fontsize=fs, fontweight="bold" if bold else "normal", color="#111")
def arrow(x1, y1, x2, y2, color="#3b5a8a", conn="arc3,rad=0"):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=11, color=color, lw=1.1, connectionstyle=conn))
ax.add_patch(FancyBboxPatch((2, 58), 96, 10, boxstyle="round,pad=0.4", fc="#fbf7ee", ec="#c9a45c", lw=1.2))
ax.text(4, 66.4, "Productions (the unchanged ACT-R procedural module)", fontsize=8.5, fontweight="bold", color="#5a4410")
box(6, 59.5, 24, 5.5, "+visual> isa gs-search" + NL + "color red  orient steep", fc="#fff", ec="#c9a45c", fs=7.5)
box(38, 59.5, 24, 5.5, "=visual> target object" + NL + "or  ?visual> state error", fc="#fff", ec="#c9a45c", fs=7.5)
box(70, 59.5, 24, 5.5, "+visual> isa gs-feedback" + NL + "outcome hit | miss | fa | tn", fc="#fff", ec="#c9a45c", fs=7.5)
ax.add_patch(FancyBboxPatch((2, 8), 96, 46, boxstyle="round,pad=0.4", fc="#f7f9fc", ec="#3b5a8a", lw=1.2))
ax.text(4, 52.3, "gs-vision module (subclass of the ACT-R 7.31.4 vision module; runs on its own scheduled events)", fontsize=8.5, fontweight="bold", color="#1e3a66")
box(4, 40, 20, 8, "Visicon + acuity" + NL + "per-feature availability" + NL + "by eccentricity", fs=7.5)
box(4, 28, 20, 8, "Iconic memory" + NL + "4 s persistence," + NL + "refreshed each fixation", fs=7.5)
box(29, 34, 22, 12, "Priority map" + NL + "bottom-up + top-down" + NL + "+ history + value + scene" + NL + "- IOR, + noise", fs=7.5)
box(56, 40, 18, 7, "Covert selection" + NL + "Luce choice every 50 ms" + NL + "inside attentional field", fs=7)
box(56, 28, 18, 8, "Asynchronous diffuser" + NL + "5 items, Wald" + NL + "identification time", fs=7)
box(79, 40, 17, 7, "Hit: build object," + NL + "attend, deliver" + NL + "to visual buffer", fc="#eaf5ee", ec="#2e7d4f", fs=7)
box(79, 28, 17, 8, "Reject: IOR ring," + NL + "quit-unit weight" + NL + "+= delta", fs=7)
box(56, 14, 18, 8, "Quit rules" + NL + "competitive lottery" + NL + "+ adaptive threshold", fs=7)
box(79, 14, 17, 8, "Failure: buffer" + NL + "empty, state error", fc="#fbeeee", ec="#a33", fs=7)
box(29, 14, 22, 8, "Saccades (EMMA)" + NL + "preparation, execution," + NL + "landing noise; triggered" + NL + "by peripheral guidance", fs=7)
box(4, 14, 20, 8, "Feedback learning" + NL + "threshold scale," + NL + "prevalence, priming", fs=7)
arrow(24, 44, 29, 42); arrow(24, 32, 29, 38); arrow(14, 40, 14, 36.4)
arrow(51, 41, 56, 43); arrow(65, 40, 65, 36.4); arrow(74, 32, 79, 44, conn="arc3,rad=-0.2"); arrow(74, 31, 79, 31)
arrow(87, 28, 87, 22.4); arrow(79, 31, 74, 19, conn="arc3,rad=0.2"); arrow(74, 17, 79, 17)
arrow(56, 17, 51, 18); arrow(40, 22, 40, 34); arrow(29, 18, 24, 18); arrow(14, 22, 14, 28)
arrow(18, 59.5, 18, 48.4, color="#c9a45c"); arrow(87.5, 47, 50, 59.5, color="#2e7d4f", conn="arc3,rad=0.15"); arrow(87.5, 22.4, 50, 59.5, color="#a33", conn="arc3,rad=-0.25")
ax.plot([82, 82, 97.2, 97.2, 14, 14], [59.5, 56.5, 56.5, 10.5, 10.5, 12.5], color="#c9a45c", lw=1.1, solid_capstyle="round")
arrow(14, 12.5, 14, 13.6, color="#c9a45c")
ax.text(50, -0.8, "Inside RT: search production, module events, response production, motor stage.   After the keypress: feedback.", fontsize=7.5, ha="center", color="#333", style="italic")
fig.savefig(f"{OUT}/fig_architecture.png", dpi=300, bbox_inches="tight"); plt.close(fig)
print("ok")
