#!/bin/bash
#SBATCH --array=1-1000
#SBATCH --cpus-per-task=1
#SBATCH --job-name=dml_j2
#SBATCH --output=logs/dml_%A_%a.out
#SBATCH --error=logs/dml_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

# JOBS II has 8 covariates -> order=2 = 44 features. Fast and light.

module purge
module load math/R/4.3.3
module load compiler/gnu/14.1

export PATH=/opt/bwhpc/common/compiler/gnu/14.1/bin:$PATH
export LD_LIBRARY_PATH=/opt/bwhpc/common/compiler/gnu/14.1/lib64:$LD_LIBRARY_PATH

export PROJECT_ROOT="/home/tu/tu_tu/tu_zxojs39/cluster_jobs2_latent/dmavae_sim"
# __TASK_OFFSET_PATCH__
TASK_OFFSET=${TASK_OFFSET:-0}
task_id=$(( SLURM_ARRAY_TASK_ID + TASK_OFFSET ))
echo "[chunk] offset=$TASK_OFFSET  array_id=$SLURM_ARRAY_TASK_ID  real_task_id=$task_id"
echo "[dml] task_id=$task_id  $(date)"
echo "[dml] gcc: $(gcc --version | head -1)"
cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/run_dml.R" "$task_id"
