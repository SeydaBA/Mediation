"""
load_jobs2.py — Load JOBS II semi-synthetic rep files from input/<scenario>/.

JOBS II uses keys (n, eta, alpha_share, name) instead of the synthetic
pipeline's (N, n_X, sigma2_x). There's no Z column (no oracle).

Returns torch tensors (float32) matching the synthetic pipeline's contract.
"""

import os
import numpy as np
import pandas as pd
import torch


def load_data(input_dir: str, scenario_name: str, rep: int):
    """Return (X, m, t, y) as float32 torch tensors."""
    rep_tag = f"rep{rep:03d}"
    rep_dir = os.path.join(input_dir, scenario_name)

    X = pd.read_csv(os.path.join(rep_dir, f"{rep_tag}_x.csv")).values.astype(np.float32)
    m = pd.read_csv(os.path.join(rep_dir, f"{rep_tag}_m.csv"))["m"].values.astype(np.float32)
    t = pd.read_csv(os.path.join(rep_dir, f"{rep_tag}_t.csv"))["t"].values.astype(np.float32)
    y = pd.read_csv(os.path.join(rep_dir, f"{rep_tag}_y.csv"))["y"].values.astype(np.float32)

    return (torch.from_numpy(X),
            torch.from_numpy(m),
            torch.from_numpy(t),
            torch.from_numpy(y))


def get_true_effects(input_dir: str, scenario_name: str, rep: int) -> dict:
    """Read truth row. All effects are 0 by construction for JOBS II."""
    rep_tag = f"rep{rep:03d}"
    rep_dir = os.path.join(input_dir, scenario_name)
    truth   = pd.read_csv(os.path.join(rep_dir, f"{rep_tag}_truth.csv")).iloc[0]
    return {
        "ATE":    float(truth["ATE"]),
        "NDE_d1": float(truth["NDE_d1"]),
        "NDE_d0": float(truth["NDE_d0"]),
        "NIE_d1": float(truth["NIE_d1"]),
        "NIE_d0": float(truth["NIE_d0"]),
    }
