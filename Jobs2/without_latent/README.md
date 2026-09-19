# JOBS II semi-synthetic pipeline (Cheng et al. 2022)

This pipeline implements the JOBS II semi-synthetic experiments from
Cheng et al. (2022) "Causal Mediation Analysis with Hidden Confounders"
(WSDM '22), §5.2, and runs **5 mediation methods** on the resulting datasets:

| Method  | Description |
|---------|-------------|
| LSEM    | Baron-Kenny linear SEM (no T×M) — proxy X |
| LSEM-I  | Imai et al. LSEM with T×M interaction — proxy X |
| DML     | Farbmacher et al. medDML cross-fitted lasso, order=2 — proxy X |
| DMAVAE  | Three-way disentangled VAE — proxy X |
| CMAVAE  | Single-latent VAE (Cheng et al.'s own method) — proxy X |

There is **no oracle Z** because JOBS II has no ground-truth latent confounder.

## Scenario grid (8 scenarios × 100 reps = 800 array tasks per method)

| | n=500 | n=1000 |
|---|---|---|
| η=1,  share=10% | scen 1 | scen 2 |
| η=10, share=10% | scen 3 | scen 4 |
| η=1,  share=50% | scen 5 | scen 6 |
| η=10, share=50% | scen 7 | scen 8 |

- `n`     = bootstrap sample size
- `η`     = mediator selection strength (1 = normal, 10 = strong)
- `share` = target % of "mediated" observations I(M ≥ 3); α calibrated to hit this

True ATE, NDE, NIE are all **zero by construction** — all bootstrap rows come
from the (T=0, I(M)=0) pool, so any nonzero estimate is bias.

## File layout

```
~/cluster_jobs2/dmavae_sim/
├── R/
│   ├── scenarios.R              # 8-scenario grid, task_id ↔ (scenario_id, rep)
│   ├── calibrate_alpha.R        # ONE-OFF: find α per (n, η, share); writes alpha_lookup.rds
│   ├── generate_jobs2.R         # bootstrap + pseudo-T,M generation
│   ├── rep_io.R                 # CSV read/write helpers
│   ├── run_lsem.R               # LSEM proxy-X
│   ├── run_lsem_i.R             # LSEM-I proxy-X
│   ├── run_dml.R                # DML proxy-X (with patch_LARF source)
│   └── patch_LARF.R             # overflow-safe Generate.Powers replacement
├── py/
│   ├── scenarios.py             # mirror of R/scenarios.R
│   ├── load_jobs2.py            # reads input/<scenario>/rep<NNN>_*.csv
│   ├── dmavae_gpu.py            # DMAVAE model (unchanged from synthetic pipelines)
│   ├── cmavae_gpu.py            # CMAVAE model (unchanged)
│   ├── run_dmavae.py
│   ├── run_cmavae.py
│   └── aggregate_results.py
├── slurm/
│   ├── gen_data.sbatch          # 800 tasks, 10 min, 2 GB
│   ├── run_lsem.sbatch          # 800 tasks, 10 min, 2 GB
│   ├── run_lsem_i.sbatch
│   ├── run_dml.sbatch           # 800 tasks, 1 h, 4 GB
│   ├── run_dmavae.sbatch        # 800 tasks, 2.5 h, 4 GB × 2 CPU
│   ├── run_cmavae.sbatch
│   ├── aggregate.sbatch
│   └── run_sequential.sh        # chains everything end-to-end
├── input/                       # (generated) per-rep CSVs of (X, M, T, Y, truth)
├── performance_lsem/            # (generated)
├── performance_lsem_i/
├── performance_dml/
├── performance_dmavae/
├── performance_cmavae/
├── all_results.csv              # (generated) every rep, every method
└── summary_all_methods.csv      # (generated) 5 × 8 = 40 rows of bias/RMSE
```

## Run order

### Step 1: One-off α calibration (~2 min, run on login node)

```bash
cd ~/cluster_jobs2/dmavae_sim
module load math/R/4.3.3
export PROJECT_ROOT=$HOME/cluster_jobs2/dmavae_sim
Rscript R/calibrate_alpha.R
ls R/alpha_lookup.rds         # confirm it was written
```

This grid-searches α per (n, η, share) to produce 10% or 50% mediated samples.

### Step 2: Full pipeline (disconnect-safe)

```bash
cd ~/cluster_jobs2/dmavae_sim
nohup bash slurm/run_sequential.sh > sequential_run.log 2>&1 &
disown
tail -f sequential_run.log
```

This submits all 7 stages in order, waits for each to drain, and finally
runs the aggregator. Safe to close SSH after `disown`.

Expected total wallclock at full QOS concurrency: **3-6 hours** (dominated by
the two VAE stages, each ~2.5 h for the slowest reps).

### Step 3: When reconnecting

```bash
ssh ...
cd ~/cluster_jobs2/dmavae_sim

# Is the wrapper still running?
ps aux | grep run_sequential | grep -v grep

# If empty → done. Look at the summary:
tail -50 sequential_run.log
cat summary_all_methods.csv
```

## Differences from the synthetic linear/nonlinear pipelines

| Aspect | Synthetic | JOBS II |
|---|---|---|
| Data source | Generated from known DGP | Real X, Y from mediation::jobs; T, M simulated |
| Truth | Sample-computed ATE/NDE/NIE | 0 by construction |
| Scenario keys | N, n_X, σ²_x | n, η, alpha_share |
| Oracle Z | Yes (3-dim latent) | None (no ground truth) |
| Methods | 8 (5 + 3 oracle versions) | 5 |
| n_X | 10 or 200 | Fixed 8 |
| DML order | 1 (linear) or 2 (nonlinear) | 2 (always — only 44 features) |

## Comparing with the synthetic results

Once this pipeline finishes, you have three `summary_all_methods.csv` files:

- `~/cluster_linear/dmavae_sim/summary_all_methods.csv`     — linear DGP
- `~/cluster_nonlinear/dmavae_sim/summary_all_methods.csv`  — nonlinear DGP
- `~/cluster_jobs2/dmavae_sim/summary_all_methods.csv`      — semi-synthetic

These have slightly different column sets (the scenario keys differ), but all
contain `*_bias_mean`, `*_bias_sd`, `*_rmse` for the same five effect estimates
(ATE, NDE(d=1), NDE(d=0), NIE(d=1), NIE(d=0)) under the same five methods
(proxy-X versions). They can be stacked into a single comparison after
adding a "dataset" column.
