"""Scanpath comparison metrics for the Tier 2 and Tier 3 validations.

Handoff section 9.  MultiMatch comes from the ``multimatch-gaze`` package;
ScanMatch and Sequence Score are implemented here, following Cristino et al.
(2010) and Chen et al. (2021) respectively, because neither has a maintained
package that installs cleanly.  ``pysaliency`` supplies NSS and AUC when it is
installed (``requirements-tier3.txt``); those functions raise a clear error
rather than a silent import failure when it is not.

A scanpath here is an ``(n, 3)`` array of ``x, y, duration_ms``, in pixels and
milliseconds, which is what ``run_batch.py`` writes and what eye trackers
export after fixation detection.

Every similarity in this file is in ``[0, 1]``, higher meaning more similar.
Report each one against two baselines, as section 9 requires: the human-human
consistency ceiling (leave-one-out over the human scanpaths) and the best
published model value.  :func:`human_ceiling` computes the first.
"""

from __future__ import annotations

import itertools
import math
from typing import Callable, Sequence

import numpy as np


# --------------------------------------------------------------------------
# MultiMatch
# --------------------------------------------------------------------------

MULTIMATCH_DIMENSIONS = ("vector", "direction", "length", "position", "duration")


def multimatch(a: np.ndarray, b: np.ndarray, screen_size=(1024, 768),
               grouping: bool = False, **kwargs) -> dict:
    """MultiMatch similarity on the five dimensions.

    ``a`` and ``b`` are ``(n, 3)`` arrays of x, y, duration_ms.  The package
    wants durations in seconds and a structured array, so we convert.
    """
    import multimatch_gaze as mm

    def _fmt(p):
        p = np.asarray(p, float)
        rec = np.empty(len(p), dtype=[("start_x", float), ("start_y", float),
                                      ("duration", float)])
        rec["start_x"], rec["start_y"] = p[:, 0], p[:, 1]
        rec["duration"] = p[:, 2] / 1000.0
        return rec

    if len(a) < 3 or len(b) < 3:      # MultiMatch needs a simplifiable path
        return {d: float("nan") for d in MULTIMATCH_DIMENSIONS}
    vals = mm.docomparison(_fmt(a), _fmt(b), screensize=list(screen_size),
                           grouping=grouping, **kwargs)
    return dict(zip(MULTIMATCH_DIMENSIONS, [float(v) for v in vals]))


# --------------------------------------------------------------------------
# ScanMatch (Cristino, Mathot, Theeuwes and Gilchrist 2010)
# --------------------------------------------------------------------------

def _grid_labels(path: np.ndarray, screen_size, grid, temporal_bin_ms):
    """Fixations to a letter string: spatial bin, repeated per temporal bin."""
    w, h = screen_size
    nx, ny = grid
    out = []
    for x, y, dur in path:
        cx = min(nx - 1, max(0, int(x / w * nx)))
        cy = min(ny - 1, max(0, int(y / h * ny)))
        idx = cy * nx + cx
        reps = 1 if not temporal_bin_ms else max(1, int(round(dur / temporal_bin_ms)))
        out.extend([idx] * reps)
    return out


def _substitution_matrix(grid, threshold=0.5):
    """Distance-based substitution scores, as ScanMatch builds them.

    Score for substituting bin i by bin j is ``max_dist * threshold - dist``,
    so nearby bins score positive and distant ones negative.
    """
    nx, ny = grid
    n = nx * ny
    coords = np.array([[i % nx, i // nx] for i in range(n)], float)
    d = np.linalg.norm(coords[:, None, :] - coords[None, :, :], axis=-1)
    return d.max() * threshold - d


def _needleman_wunsch(a, b, sub, gap: float):
    m, n = len(a), len(b)
    f = np.zeros((m + 1, n + 1))
    f[:, 0] = np.arange(m + 1) * gap
    f[0, :] = np.arange(n + 1) * gap
    for i in range(1, m + 1):
        ai = a[i - 1]
        for j in range(1, n + 1):
            f[i, j] = max(f[i - 1, j - 1] + sub[ai, b[j - 1]],
                          f[i - 1, j] + gap, f[i, j - 1] + gap)
    return float(f[m, n])


def scanmatch(a: np.ndarray, b: np.ndarray, screen_size=(1024, 768),
              grid=(8, 6), temporal_bin_ms: float | None = 50.0,
              threshold: float = 0.5, gap: float = 0.0) -> float:
    """ScanMatch similarity in [0, 1].

    Normalised by the score of the better self-alignment, which is the
    normalisation the original toolbox uses.
    """
    sa = _grid_labels(a, screen_size, grid, temporal_bin_ms)
    sb = _grid_labels(b, screen_size, grid, temporal_bin_ms)
    if not sa or not sb:
        return float("nan")
    sub = _substitution_matrix(grid, threshold)
    score = _needleman_wunsch(sa, sb, sub, gap)
    norm = max(len(sa), len(sb)) * sub.max()
    return float(np.clip(score / norm, 0.0, 1.0)) if norm > 0 else float("nan")


# --------------------------------------------------------------------------
# Sequence Score (Chen, Yang, Ahn, Samaras, Hoai and Zelinsky 2021)
# --------------------------------------------------------------------------

def cluster_fixations(paths: Sequence[np.ndarray], n_clusters: int = 12,
                      seed: int = 0) -> np.ndarray:
    """K-means centroids over the pooled fixations of a set of scanpaths.

    Sequence Score needs a shared vocabulary of regions.  Cluster over every
    scanpath being compared -- model and human together -- so the two are
    quantised the same way; clustering them separately inflates the score.
    """
    pts = np.vstack([np.asarray(p, float)[:, :2] for p in paths if len(p)])
    if len(pts) <= n_clusters:
        return pts.copy()
    rng = np.random.default_rng(seed)
    cent = pts[rng.choice(len(pts), n_clusters, replace=False)]
    for _ in range(60):
        lab = np.argmin(((pts[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
        new = np.array([pts[lab == k].mean(0) if np.any(lab == k) else cent[k]
                        for k in range(len(cent))])
        if np.allclose(new, cent):
            break
        cent = new
    return cent


def _to_symbols(path: np.ndarray, centroids: np.ndarray) -> list:
    p = np.asarray(path, float)[:, :2]
    return list(np.argmin(((p[:, None, :] - centroids[None]) ** 2).sum(-1), axis=1))


def _lcs_len(a, b) -> int:
    m, n = len(a), len(b)
    prev = [0] * (n + 1)
    for i in range(1, m + 1):
        cur = [0] * (n + 1)
        for j in range(1, n + 1):
            cur[j] = prev[j - 1] + 1 if a[i - 1] == b[j - 1] else max(prev[j], cur[j - 1])
        prev = cur
    return prev[n]


def sequence_score(a: np.ndarray, b: np.ndarray, centroids: np.ndarray) -> float:
    """Longest-common-subsequence similarity of two cluster-label strings."""
    sa, sb = _to_symbols(a, centroids), _to_symbols(b, centroids)
    if not sa or not sb:
        return float("nan")
    return _lcs_len(sa, sb) / max(len(sa), len(sb))


# --------------------------------------------------------------------------
# Baselines
# --------------------------------------------------------------------------

def human_ceiling(paths: Sequence[np.ndarray],
                  metric: Callable[[np.ndarray, np.ndarray], float],
                  max_pairs: int = 500, seed: int = 0) -> dict:
    """Leave-one-out human-human agreement: the ceiling any model is judged against.

    Every reported similarity is meaningless without it, since scanpaths on a
    22.5 degree display agree with each other only moderately.
    """
    paths = [np.asarray(p, float) for p in paths if len(p) >= 2]
    pairs = list(itertools.combinations(range(len(paths)), 2))
    if not pairs:
        return {"mean": float("nan"), "sd": float("nan"), "n_pairs": 0}
    if len(pairs) > max_pairs:
        rng = np.random.default_rng(seed)
        pairs = [pairs[i] for i in rng.choice(len(pairs), max_pairs, replace=False)]
    vals = [metric(paths[i], paths[j]) for i, j in pairs]
    vals = [v for v in vals if np.isfinite(v)]
    return {"mean": float(np.mean(vals)) if vals else float("nan"),
            "sd": float(np.std(vals)) if vals else float("nan"),
            "n_pairs": len(vals)}


def model_vs_human(model_paths: Sequence[np.ndarray],
                   human_paths: Sequence[np.ndarray],
                   metric: Callable[[np.ndarray, np.ndarray], float]) -> dict:
    vals = []
    for m in model_paths:
        for h in human_paths:
            v = metric(np.asarray(m, float), np.asarray(h, float))
            if np.isfinite(v):
                vals.append(v)
    return {"mean": float(np.mean(vals)) if vals else float("nan"),
            "sd": float(np.std(vals)) if vals else float("nan"),
            "n_pairs": len(vals)}


# --------------------------------------------------------------------------
# Fixation-map metrics (Tier 3)
# --------------------------------------------------------------------------

def _require_pysaliency():
    try:
        import pysaliency          # noqa: F401
    except ImportError as e:
        raise ImportError(
            "NSS and AUC need pysaliency: pip install -r requirements-tier3.txt"
        ) from e
    return pysaliency


def nss(saliency_map: np.ndarray, fixations_xy: np.ndarray) -> float:
    """Normalised scanpath saliency: the mean z-scored map value at fixations."""
    m = np.asarray(saliency_map, float)
    sd = m.std()
    if sd == 0:
        return float("nan")
    z = (m - m.mean()) / sd
    xs = np.clip(np.asarray(fixations_xy, float)[:, 0].astype(int), 0, m.shape[1] - 1)
    ys = np.clip(np.asarray(fixations_xy, float)[:, 1].astype(int), 0, m.shape[0] - 1)
    return float(z[ys, xs].mean())


def auc_judd(saliency_map: np.ndarray, fixations_xy: np.ndarray,
             n_steps: int = 100) -> float:
    """AUC-Judd: the map's ability to tell fixated pixels from all pixels."""
    m = np.asarray(saliency_map, float)
    if m.max() == m.min():
        return float("nan")
    m = (m - m.min()) / (m.max() - m.min())
    xs = np.clip(np.asarray(fixations_xy, float)[:, 0].astype(int), 0, m.shape[1] - 1)
    ys = np.clip(np.asarray(fixations_xy, float)[:, 1].astype(int), 0, m.shape[0] - 1)
    pos = m[ys, xs]
    allv = m.ravel()
    thresholds = np.linspace(0.0, 1.0, n_steps)
    tp = np.array([(pos >= t).mean() for t in thresholds])
    fp = np.array([(allv >= t).mean() for t in thresholds])
    order = np.argsort(fp)
    return float(np.trapezoid(tp[order], fp[order]))


def tfp_auc(model_paths, human_paths, screen_size=(1024, 768), sigma: float = 40.0):
    """Target-fixation-probability AUC: how fast each side finds the target.

    Chen et al. (2021) plot cumulative probability of having fixated the
    target against fixation number and take the area under it; this returns
    both curves and their areas so the two can be reported side by side.
    """
    def _curve(paths, n=8):
        hit = np.zeros(n)
        for p in paths:
            p = np.asarray(p, float)
            for i in range(min(n, len(p))):
                if p[i, 2] < 0:          # convention: negative duration marks the target
                    hit[i:] += 1
                    break
        return hit / max(1, len(paths))

    mc, hc = _curve(model_paths), _curve(human_paths)
    return {"model_curve": mc.tolist(), "human_curve": hc.tolist(),
            "model_auc": float(mc.mean()), "human_auc": float(hc.mean())}
