"""
run_dmavae.py — Run DMAVAE on ONE JOBS II semi-synthetic replication.

Usage:
    python run_dmavae.py <task_id>   # task_id in 1..800

Writes one row to $PROJECT_ROOT/performance_dmavae/<scenario>/rep<rep>.csv
plus a per-rep loss curve.
"""

import os
import sys
import logging

import numpy as np
import pandas as pd
import torch
import pyro

from scenarios   import task_id_to_indices
from load_jobs2  import load_data, get_true_effects
from dmavae_gpu  import DMA_VAE

logging.getLogger("pyro").setLevel(logging.WARNING)

# ---- Settings ----
NUM_EPOCHS       = 700
BATCH_SIZE       = 128
LR               = 1e-4
LR_DECAY         = 0.01
WEIGHT_DECAY     = 1e-4
CONVERGENCE_FRAC = 0.05
FLAT_SD_FRAC     = 0.05


def check_convergence(losses, num_epochs, n_batches_per_epoch):
    losses = np.asarray(losses)
    if len(losses) >= num_epochs * n_batches_per_epoch:
        per_epoch = losses[: num_epochs * n_batches_per_epoch].reshape(
            num_epochs, n_batches_per_epoch).mean(axis=1)
    else:
        per_epoch = np.array_split(losses, num_epochs)
        per_epoch = np.array([c.mean() for c in per_epoch])

    first_10   = per_epoch[:10].mean()
    last_10    = per_epoch[-10:].mean()
    last_10_sd = per_epoch[-10:].std()

    rel_drop = (first_10 - last_10) / abs(first_10) if first_10 != 0 else 0.0
    rel_sd   = last_10_sd / abs(last_10) if last_10 != 0 else float("inf")

    return {
        "first_10_mean": float(first_10),
        "last_10_mean":  float(last_10),
        "last_10_sd":    float(last_10_sd),
        "relative_drop": float(rel_drop),
        "relative_sd":   float(rel_sd),
        "converged":     bool(rel_drop >= CONVERGENCE_FRAC and rel_sd <= FLAT_SD_FRAC),
        "per_epoch":     per_epoch,
    }


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: python run_dmavae.py <task_id>")
    task_id = int(sys.argv[1])

    project_root = os.environ.get("PROJECT_ROOT")
    if not project_root:
        sys.exit("PROJECT_ROOT env var not set.")
    input_dir = os.path.join(project_root, "input")
    perf_dir  = os.path.join(project_root, "performance_dmavae")

    idx = task_id_to_indices(task_id)
    print(f"[run_dmavae] task={task_id}  scenario={idx['name']}  rep={idx['rep']}",
          flush=True)

    pyro.enable_validation(__debug__)
    torch.set_default_tensor_type("torch.FloatTensor")

    x, m, t, y = load_data(input_dir, idx["name"], idx["rep"])
    n_features = x.shape[1]
    n_obs      = x.shape[0]
    assert n_obs == idx["n"], (
        f"Expected n={idx['n']} rows, got {n_obs}.")

    pyro.clear_param_store()
    model = DMA_VAE(
        feature_dim    = n_features,
        latent_Ztm_dim = 1,
        latent_Zty_dim = 1,
        latent_Zmy_dim = 1,
        hidden_dim     = 128,
        num_layers     = 4,
        num_samples    = 10,
    )

    losses = model.fit(
        x, m, t, y,
        num_epochs          = NUM_EPOCHS,
        batch_size          = BATCH_SIZE,
        learning_rate       = LR,
        learning_rate_decay = LR_DECAY,
        weight_decay        = WEIGHT_DECAY,
    )

    n_batches = max(1, (n_obs + BATCH_SIZE - 1) // BATCH_SIZE)
    conv = check_convergence(losses, NUM_EPOCHS, n_batches)

    NDE, NIEr, NIE, ATE = model.effect_estimation(x)
    NDE  = float(NDE.cpu().detach().numpy().mean())
    NIEr = float(NIEr.cpu().detach().numpy().mean())
    NIE  = float(NIE.cpu().detach().numpy().mean())
    ATE  = float(ATE.cpu().detach().numpy().mean())

    truth = get_true_effects(input_dir, idx["name"], idx["rep"])

    scen_dir = os.path.join(perf_dir, idx["name"])

    # __SKIP_IF_DONE__: if the output file already exists, skip this task.
    _out_csv = os.path.join(scen_dir, f"rep{idx['rep']:03d}.csv")
    if os.path.exists(_out_csv):
        print(f"[{os.path.basename(__file__)}] task={task_id}  scenario={idx['name']}  rep={idx['rep']}  SKIP (output exists)", flush=True)
        sys.exit(0)


    os.makedirs(scen_dir, exist_ok=True)

    pd.DataFrame({"epoch": np.arange(len(conv["per_epoch"])),
                  "loss":  conv["per_epoch"]}).to_csv(
        os.path.join(scen_dir, f"loss_rep{idx['rep']:03d}.csv"),
        index=False, float_format="%.4f")

    row = {
        "method":      "dmavae",
        "scenario_id": idx["scenario_id"],
        "scenario":    idx["name"],
        "rep":         idx["rep"],
        "n":           idx["n"],
        "eta":         idx["eta"],
        "alpha_share": idx["alpha_share"],

        "ATE_est":    ATE,
        "NDE_d0_est": NDE,
        "NIE_d1_est": NIEr,
        "NIE_d0_est": NIE,

        "ATE_true":    truth["ATE"],
        "NDE_d0_true": truth["NDE_d0"],
        "NIE_d1_true": truth["NIE_d1"],
        "NIE_d0_true": truth["NIE_d0"],

        "ATE_bias":    ATE  - truth["ATE"],
        "NDE_d0_bias": NDE  - truth["NDE_d0"],
        "NIE_d1_bias": NIEr - truth["NIE_d1"],
        "NIE_d0_bias": NIE  - truth["NIE_d0"],

        "converged":       conv["converged"],
        "first_10_loss":   conv["first_10_mean"],
        "last_10_loss":    conv["last_10_mean"],
        "last_10_loss_sd": conv["last_10_sd"],
        "relative_drop":   conv["relative_drop"],
        "relative_sd":     conv["relative_sd"],
    }
    pd.DataFrame([row]).to_csv(
        os.path.join(scen_dir, f"rep{idx['rep']:03d}.csv"),
        index=False, float_format="%.6f")

    print(f"[run_dmavae] done. converged={conv['converged']}  "
          f"ATE_est={ATE:+.3f}  truth={truth['ATE']:+.3f}",
          flush=True)


if __name__ == "__main__":
    main()
