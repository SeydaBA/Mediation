# Nonlinear pipeline — DMAVAE / CMAVAE / LSEM / LSEM-I / DML

Mirrors the linear pipeline exactly. **Differences from linear:**

1. `R/shared_dgp_nonlinear.R` — adds `0.3 * sin(2 * X1)` to M and `0.5 * X1^2` to Y
2. `R/run_dml.R` — uses `order=2` polynomial expansion (catches X^2 in lasso)
3. sbatch files: bigger DML walltime/memory budget (`order=2` with n_X=200 expands to ~20k features)
4. `PROJECT_ROOT` is `$HOME/cluster_nonlinear/dmavae_sim` so results don't collide with linear

LSEM, LSEM-I, DMAVAE, CMAVAE estimators are **identical** to the linear pipeline — they don't know about the DGP, they just read CSVs the generator wrote. LSEM/LSEM-I will be more biased here (misspecified for nonlinear DGP); that's the point of the comparison.

## Setup

```bash
# 1. Upload the zip to the cluster
scp dmavae_sim_nonlinear.zip tu_zxojs39@helix-login.bwhpc.de:/home/tu/tu_tu/tu_zxojs39/

# 2. Unpack into the NONLINEAR root (separate from linear!)
ssh tu_zxojs39@helix-login.bwhpc.de
cd /home/tu/tu_tu/tu_zxojs39/
mkdir -p cluster_nonlinear
cd cluster_nonlinear
unzip ~/dmavae_sim_nonlinear.zip          # gives you cluster_nonlinear/dmavae_sim/

cd dmavae_sim
chmod +x slurm/run_sequential.sh
mkdir -p logs
```

Conda env (`dmavae`) and R library (`~/R/x86_64-pc-linux-gnu-library/4.3` with causalweight 1.0.3 etc) are already set up from the linear run — nothing new to install.

## Smoke-test ONE rep first

Same as linear — catches issues in 5 minutes:

```bash
cd ~/cluster_nonlinear/dmavae_sim
export PROJECT_ROOT=$HOME/cluster_nonlinear/dmavae_sim

# R side
module load math/R/4.3.3
Rscript R/generate_data.R 1
ls input/N1000_nX10_sx1/

Rscript R/run_lsem.R    1
Rscript R/run_lsem_i.R  1
Rscript R/run_dml.R     1     # slower than linear (order=2) — give it a couple minutes

# Python side
source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1
cd py
python run_dmavae.py 1
python run_cmavae.py 1
cd ..

# Verify all 8 result files exist
ls performance_*/N1000_nX10_sx1/rep001.csv
```

Each should have real (non-NA) numbers in the `_est` columns.

## Launch the full pipeline (sequential, stays under QOS cap)

```bash
cd ~/cluster_nonlinear/dmavae_sim

# Clean smoke-test outputs so the array jobs write fresh ones
rm -rf input/ performance_*/ logs/
mkdir -p logs

# Launch under nohup so you can disconnect
nohup bash slurm/run_sequential.sh > sequential_run.log 2>&1 &
disown

# Watch progress
tail -f sequential_run.log
```

This submits: `gen_data` → wait → `run_lsem` → wait → `run_lsem_i` → wait → `run_dml` → wait → `run_dmavae` → wait → `run_cmavae` → wait → `aggregate`. About 12–24 hours total wall time depending on cluster load.

## Monitor

```bash
squeue -u $USER
squeue -u $USER --noheader | wc -l

# How many tasks of each method have finished
for m in lsem lsem_i dml dmavae cmavae; do
  n=$(ls performance_$m/*/rep*.csv 2>/dev/null | grep -v loss_rep | wc -l)
  echo "$m: $n / 800"
done
```

## Results

After everything finishes:

```bash
ls performance_*/all_results.csv
cat summary_all_methods.csv
```

Pull to laptop:

```bash
# from your laptop
scp tu_zxojs39@helix-login.bwhpc.de:/home/tu/tu_tu/tu_zxojs39/cluster_nonlinear/dmavae_sim/summary_all_methods.csv ./summary_nonlinear.csv
scp -r tu_zxojs39@helix-login.bwhpc.de:/home/tu/tu_tu/tu_zxojs39/cluster_nonlinear/dmavae_sim/performance_* ./nonlinear/
```

## Re-running pieces

```bash
# Re-aggregate only
sbatch slurm/aggregate.sbatch

# Re-run one task (interactive debug)
export PROJECT_ROOT=$HOME/cluster_nonlinear/dmavae_sim
conda activate dmavae && export PYTHONNOUSERSITE=1
cd py && python run_dmavae.py 437

# Re-run a whole method (data already generated)
sbatch slurm/run_dmavae.sbatch
```

## Watching for DML OOM (n_X=200 scenarios)

With `order=2`, `n_X=200` expands to ~20000 features. The 8 GB allocation should hold, but if you see OOM kills in the n_X=200 scenarios (tasks 201–400 and 601–800), edit `slurm/run_dml.sbatch`:

```
#SBATCH --mem-per-cpu=16000   # was 8000
```

Then resubmit just those scenarios:

```bash
sbatch --array=201-400,601-800 slurm/run_dml.sbatch
```
