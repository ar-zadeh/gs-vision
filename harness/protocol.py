"""Shared synthetic display protocol; exact original coordinates are unavailable."""
import numpy as np
from harness.tasks import make_display


def observer_plan(task, set_sizes, n_per_cell, seed, practice=30, prevalence=.5):
    """Balance retained cells, insert synthetic practice before each block.

    A 4,000-trial observer has twelve 300-trial blocks and a final 400-trial
    block, as in Wolfe et al. Short diagnostic sessions use the same maximum
    block size. All practice is returned with a flag, never silently discarded.
    """
    rng = np.random.default_rng(seed + 1000)
    order = ([(n, pr) for n in set_sizes for pr in (True, False)] * n_per_cell
             if prevalence == .5 else
             [(n, bool(rng.random() < prevalence)) for n in set_sizes
              for _ in range(2 * n_per_cell)])
    rng.shuffle(order)
    plan, offset, block = [], 0, 0
    while offset < len(order):
        count = len(order) - offset if len(order) - offset <= 400 else 300
        warmup = [(int(rng.choice(set_sizes)), bool(rng.random() < prevalence))
                  for _ in range(practice)]
        for is_practice, cells in ((True, warmup), (False, order[offset:offset + count])):
            plan.extend((n, present, is_practice, block) for n, present in cells)
        offset += count
        block += 1
    return plan, rng
