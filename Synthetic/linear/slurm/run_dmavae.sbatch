#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=2
#SBATCH --job-name=run_dmavae
#SBATCH --output=logs/dmavae_%A_%a.out
#SBATCH --error=logs/dmavae_%A_%a.err
#SBATCH --time=02:30:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

# =============================================================================
# DMAVAE (Pyro). 700 epochs, N up to 4000, n_X up to 200, hidden=128, 4 layers.
# Runs on CPU; the code auto-detects (no CUDA -> CPU). 2 threads to let
# torch use both cores for matmul.
# =============================================================================

module purge
export PATH=/opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/bin:$PATH
source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1

# Match PyTorch thread count to allocated CPUs
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK

export PROJECT_ROOT="$HOME/cluster_linear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[dmavae] task_id=$task_id  cpus=$SLURM_CPUS_PER_TASK  $(date)"

cd "$PROJECT_ROOT/py"
/home/tu/tu_tu/tu_zxojs39/.conda/envs/dmavae/bin/python run_dmavae.py "$task_id"
