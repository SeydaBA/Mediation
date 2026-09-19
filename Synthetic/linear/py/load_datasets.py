"""
load_datasets.py — read one replication written by R/generate_data.R.

The R generator writes to:
    $INPUT_DIR/<scenario_name>/rep<rep>_{x,m,t,y,z,truth}.csv

where <scenario_name> looks like 'N1000_nX10_sx1'.
"""

import os

import numpy as np
import pandas as pd
import torch


def scenario_name(N: int, n_X: int, sigma2_x: int) -> str:
    return f"N{N}_nX{n_X}_sx{sigma2_x}"


def load_data(input_dir: str, N: int, n_X: int, sigma2_x: int, rep: int):
    """
    Returns (x, m, t, y) as float32 tensors on the default device.
    `rep` is 1-based (rep001, rep002, ...) to match the R-side filenames.
    """
    sdir = os.path.join(input_dir, scenario_name(N, n_X, sigma2_x))
    tag  = f"rep{rep:03d}"

    X = pd.read_csv(os.path.join(sdir, f"{tag}_x.csv")).values.astype(np.float32)
    m = pd.read_csv(os.path.join(sdir, f"{tag}_m.csv"))["m"].values.astype(np.float32)
    t = pd.read_csv(os.path.join(sdir, f"{tag}_t.csv"))["t"].values.astype(np.float32)
    y = pd.read_csv(os.path.join(sdir, f"{tag}_y.csv"))["y"].values.astype(np.float32)

    return (torch.from_numpy(X),
            torch.from_numpy(m),
            torch.from_numpy(t),
            torch.from_numpy(y))


def get_true_effects(input_dir: str, N: int, n_X: int, sigma2_x: int, rep: int):
    sdir = os.path.join(input_dir, scenario_name(N, n_X, sigma2_x))
    tag  = f"rep{rep:03d}"
    df = pd.read_csv(os.path.join(sdir, f"{tag}_truth.csv"))
    row = df.iloc[0]
    return {
        "ATE":    float(row["ATE"]),
        "NDE_d1": float(row["NDE_d1"]),
        "NDE_d0": float(row["NDE_d0"]),
        "NIE_d1": float(row["NIE_d1"]),
        "NIE_d0": float(row["NIE_d0"]),
    }
