#!/bin/bash
#SBATCH --array=1-1000
#SBATCH --cpus-per-task=1
#SBATCH --job-name=lsemi_j2
#SBATCH --output=logs/lsem_i_%A_%a.out
#SBATCH --error=logs/lsem_i_%A_%a.err
#SBATCH --time=00:10:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=2000

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
echo "[lsem_i] task_id=$task_id  $(date)"
cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/run_lsem_i.R" "$task_id"
