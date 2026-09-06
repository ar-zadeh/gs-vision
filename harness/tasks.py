"""Display generators for the Wolfe, Palmer and Horowitz (2010) benchmark tasks.

Three tasks, matching the handoff document section 8.1:

``feature``
    red vertical bar among green vertical bars (efficient search)
``conjunction``
    red vertical among green verticals and red horizontals (inefficient)
``spatial``
    a digital 2 among digital 5s.  Colour, orientation, size and luminance
    channels are identical for every item, so only the identification-only
    ``shape`` slot separates target from distractor.  That is what makes the
    task unguided under the section 5.1 two-class rule.

Geometry
--------
A 22.5 deg square field is divided into an invisible 5x5 grid of 4.5 deg
cells; each item sits at a uniformly random position inside its own cell, far
enough from the cell edge that the item stays inside the cell.  Bars are
1 deg by 3.5 deg, digits 1.5 deg by 2.7 deg.  Set sizes 3, 6, 12, 18 and 50
percent target present.

Degrees / pixel conversion
--------------------------
ACT-R owns this conversion in the device interface, not in the vision module.
``pm-angle-to-pixels`` is round(2 * D * tan(a/2)) and ``pm-pixels-to-angle``
is 2 * atan(p / 2 / D), with D = :viewing-distance * :pixels-per-inch.  The
two are exact inverses, so an item placed with :func:`deg2px` here and
measured with ``pm-pixels-to-angle`` in Lisp round-trips.  We copy ACT-R's
convention rather than the geometrically correct off-axis projection
D * tan(d), because agreeing with the module matters more than agreeing with
optics, and the module measures every eccentricity with ``pm-pixels-to-angle``.

At the ACT-R defaults (72 ppi, 15 in) one pixel is 0.053 deg.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field
from typing import Iterator, Sequence

import numpy as np

# --- device parameters (ACT-R defaults) ------------------------------------
PIXELS_PER_INCH = 72.0
VIEWING_DISTANCE_IN = 15.0
VIEWDIST_PX = PIXELS_PER_INCH * VIEWING_DISTANCE_IN  # 1080

# --- display geometry ------------------------------------------------------
FIELD_DEG = 22.5
GRID = 5
CELL_DEG = FIELD_DEG / GRID  # 4.5
BAR_W_DEG, BAR_H_DEG = 1.0, 3.5
DIGIT_W_DEG, DIGIT_H_DEG = 1.5, 2.7
SCREEN_CENTER_PX = (512, 384)

TASKS = ("feature", "conjunction", "spatial")
SET_SIZES = (3, 6, 12, 18)


def deg2px(deg: float) -> int:
    """Degrees of visual angle to pixels, exactly as ``pm-angle-to-pixels``."""
    return int(round(2.0 * VIEWDIST_PX * math.tan(math.radians(deg / 2.0))))


def px2deg(px: float) -> float:
    """Pixels to degrees of visual angle, exactly as ``pm-pixels-to-angle``."""
    return math.degrees(2.0 * math.atan(px / 2.0 / VIEWDIST_PX))


@dataclass
class Item:
    """One display element, in both degrees (for Python) and pixels (for ACT-R)."""

    x_deg: float          # signed offset from field centre
    y_deg: float
    x_px: int             # absolute screen coordinate
    y_px: int
    w_deg: float
    h_deg: float
    color: str
    hue: float            # 0-360
    orient: float         # -90..90, 0 is vertical (steep)
    lum: float            # 0-1
    shape: str            # identification-only slot
    kind: str
    is_target: bool

    @property
    def size_deg2(self) -> float:
        return self.w_deg * self.h_deg

    def visicon_feature(self) -> list:
        """Argument list for ``actr.add_visicon_features``.

        The custom slots (hue, orient, lum, shape) come from the ``gs-feature``
        chunk-type the module defines at creation, so the caller does not have
        to declare a chunk-type of its own.
        """
        return [
            "isa", ["gs-feature"],
            "screen-x", self.x_px,
            "screen-y", self.y_px,
            "kind", self.kind,
            "color", self.color,
            "value", self.shape,
            "shape", self.shape,
            "hue", round(self.hue, 3),
            "orient", round(self.orient, 3),
            "lum", round(self.lum, 3),
            "width", deg2px(self.w_deg),
            "height", deg2px(self.h_deg),
            "size", round(self.size_deg2, 3),
        ]


@dataclass
class Display:
    task: str
    set_size: int
    target_present: bool
    items: list = field(default_factory=list)

    @property
    def target_index(self):
        for i, it in enumerate(self.items):
            if it.is_target:
                return i
        return None

    def visicon_features(self) -> list:
        return [it.visicon_feature() for it in self.items]

    def as_dict(self) -> dict:
        d = {k: v for k, v in asdict(self).items() if k != "items"}
        d["items"] = [asdict(i) for i in self.items]
        d["target_index"] = self.target_index
        return d


# --- item constructors -----------------------------------------------------

_HUE = {"red": 0.0, "green": 120.0, "blue": 240.0, "white": 0.0}


def _bar(x_deg, y_deg, color, vertical, is_target):
    w, h = (BAR_W_DEG, BAR_H_DEG) if vertical else (BAR_H_DEG, BAR_W_DEG)
    return Item(
        x_deg=x_deg, y_deg=y_deg,
        x_px=SCREEN_CENTER_PX[0] + deg2px(x_deg),
        y_px=SCREEN_CENTER_PX[1] + deg2px(y_deg),
        w_deg=w, h_deg=h,
        color=color, hue=_HUE[color],
        orient=0.0 if vertical else 90.0,
        lum=0.5, shape="bar", kind="bar",
        is_target=is_target,
    )


def _digit(x_deg, y_deg, shape, is_target):
    return Item(
        x_deg=x_deg, y_deg=y_deg,
        x_px=SCREEN_CENTER_PX[0] + deg2px(x_deg),
        y_px=SCREEN_CENTER_PX[1] + deg2px(y_deg),
        w_deg=DIGIT_W_DEG, h_deg=DIGIT_H_DEG,
        color="white", hue=0.0,
        orient=0.0, lum=0.9, shape=shape, kind="digit",
        is_target=is_target,
    )


# --- placement -------------------------------------------------------------

def grid_for(set_size: int) -> int:
    """Side of the invisible grid: 5 for the benchmark, larger when needed.

    The benchmark set sizes all fit the 5x5 grid of section 8.1.  The Tier 2
    comparison uses set sizes 42 and 80, so the grid grows and the field grows
    with it, which holds item density and item size constant rather than
    packing more items into the same 22.5 degrees.
    """
    g = GRID
    while g * g < set_size:
        g += 1
    return g


def field_deg(set_size: int) -> float:
    return grid_for(set_size) * CELL_DEG


def _cell_positions(n: int, w_deg: float, h_deg: float, rng: np.random.Generator):
    """Pick ``n`` distinct grid cells and jitter one point inside each."""
    grid = grid_for(n)
    cells = rng.choice(grid * grid, size=n, replace=False)
    half = grid * CELL_DEG / 2.0
    out = []
    for c in cells:
        row, col = divmod(int(c), grid)
        cx0 = -half + col * CELL_DEG        # cell origin, signed deg from centre
        cy0 = -half + row * CELL_DEG
        mx = max(0.0, (CELL_DEG - w_deg) / 2.0)   # keep the item inside its cell
        my = max(0.0, (CELL_DEG - h_deg) / 2.0)
        cx = cx0 + CELL_DEG / 2.0 + rng.uniform(-mx, mx)
        cy = cy0 + CELL_DEG / 2.0 + rng.uniform(-my, my)
        out.append((cx, cy))
    return out


FEATURE_COLORS = ("red", "green")


def make_display(task: str, set_size: int, target_present: bool,
                 rng: np.random.Generator, target_color: str = "red") -> Display:
    """Build one display of ``task`` at ``set_size``.

    ``target_color`` only applies to the feature task, where it swaps which of
    red and green is the singleton.  Alternating it between trials is how the
    priming manipulation of phase 6 is run.
    """
    if task not in TASKS:
        raise ValueError(f"unknown task {task!r}; expected one of {TASKS}")

    if task == "spatial":
        w, h = DIGIT_W_DEG, DIGIT_H_DEG
    else:
        w, h = BAR_H_DEG, BAR_H_DEG   # bars may be rotated: reserve the long side

    pos = _cell_positions(set_size, w, h, rng)
    tgt = int(rng.integers(set_size)) if target_present else -1

    items = []
    for i, (x, y) in enumerate(pos):
        is_t = i == tgt
        if task == "feature":
            other = FEATURE_COLORS[1 - FEATURE_COLORS.index(target_color)]
            items.append(_bar(x, y, target_color if is_t else other, True, is_t))
        elif task == "conjunction":
            if is_t:
                items.append(_bar(x, y, "red", True, True))
            elif rng.random() < 0.5:
                items.append(_bar(x, y, "green", True, False))
            else:
                items.append(_bar(x, y, "red", False, False))
        else:  # spatial
            items.append(_digit(x, y, "two" if is_t else "five", is_t))

    return Display(task=task, set_size=set_size,
                   target_present=target_present, items=items)


def trial_plan(tasks: Sequence[str] = TASKS,
               set_sizes: Sequence[int] = SET_SIZES,
               n_per_cell: int = 500,
               seed: int = 0) -> Iterator[Display]:
    """Yield ``n_per_cell`` displays for every task x set size x presence cell."""
    rng = np.random.default_rng(seed)
    for task in tasks:
        for n in set_sizes:
            for present in (True, False):
                for _ in range(n_per_cell):
                    yield make_display(task, n, present, rng)


# --- target templates ------------------------------------------------------
# What the model is told to look for.  Guiding features are honoured by the
# priority map; identification-only features are not (section 5.1).

# Each template is the smallest set of slots that picks the target out of its
# own display.  Feature search needs colour alone, which is what makes it
# efficient: every distractor mismatches on the single guiding dimension.
# Conjunction needs both guiding dimensions, so every distractor matches half
# the template.  Spatial configuration needs ``shape``, which is
# identification-only, so nothing guides at all.
TEMPLATES = {
    "feature":     {"color": "red"},
    "conjunction": {"color": "red", "orient": 0.0},
    "spatial":     {"shape": "two"},
}


def matches_template(item: Item, task: str, target_color: str = "red") -> bool:
    """Ground truth: does this item satisfy the full target template?"""
    tpl = dict(TEMPLATES[task])
    if task == "feature":
        tpl["color"] = target_color
    for k, v in tpl.items():
        iv = getattr(item, k)
        if isinstance(v, str):
            if iv != v:
                return False
        elif abs(float(iv) - float(v)) > 1e-6:
            return False
    return True


if __name__ == "__main__":  # small smoke test
    rng = np.random.default_rng(1)
    for t in TASKS:
        d = make_display(t, 12, True, rng)
        assert d.target_index is not None
        assert sum(matches_template(i, t) for i in d.items) == 1, t
        ecc = [math.hypot(i.x_deg, i.y_deg) for i in d.items]
        tg = d.items[d.target_index]
        print(f"{t:12s} n={d.set_size:2d} ecc {min(ecc):4.1f}-{max(ecc):4.1f} deg "
              f"target={tg.shape}/{tg.color}")
    print("field 22.5 deg =", deg2px(22.5), "px; 1 px =", round(px2deg(1), 4), "deg")


# --- additional-singleton task (Adam, Patel, Rangan and Serences 2021) -----
#
# Tier 1's second dataset is the additional-singleton paradigm: the target is a
# singleton on one dimension and, on half the trials, an irrelevant singleton
# on another dimension competes for selection.  Adam et al.'s target is a shape
# singleton and their distractor a colour singleton; shape does not guide in
# this module (section 5.1), so the target here is an *orientation* singleton
# instead, which is the same paradigm expressed in the module's guiding
# dimensions.  Their experiment 1c is the comparison condition: variable
# distractor colour, so no learned suppression, and homogeneous non-targets.

SINGLETON_SET_SIZES = (3, 4, 5, 6)
SINGLETON_TEMPLATE = {"orient": 90.0}      # the odd, horizontal bar


def make_singleton_display(set_size: int, distractor_present: bool,
                           rng: np.random.Generator,
                           distractor_color: str | None = None) -> Display:
    """One additional-singleton display; the target is always present."""
    pos = _cell_positions(set_size, BAR_H_DEG, BAR_H_DEG, rng)
    tgt = int(rng.integers(set_size))
    dis = -1
    if distractor_present:
        choices = [i for i in range(set_size) if i != tgt]
        dis = int(rng.choice(choices))
    if distractor_color is None:
        distractor_color = "red"
    items = []
    for i, (x, y) in enumerate(pos):
        if i == tgt:
            items.append(_bar(x, y, "green", False, True))       # horizontal
        elif i == dis:
            items.append(_bar(x, y, distractor_color, True, False))
        else:
            items.append(_bar(x, y, "green", True, False))
    d = Display(task="additional_singleton", set_size=set_size,
                target_present=True, items=items)
    d.distractor_present = distractor_present
    return d
