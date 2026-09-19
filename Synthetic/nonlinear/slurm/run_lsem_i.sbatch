#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=1
#SBATCH --job-name=run_lsem_i_nl
#SBATCH --output=logs/lsem_i_%A_%a.out
#SBATCH --error=logs/lsem_i_%A_%a.err
#SBATCH --time=00:10:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=2000

module purge
module load math/R/4.3.3

export PROJECT_ROOT="$HOME/cluster_nonlinear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[lsem_i_nl] task_id=$task_id  $(date)"

cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/run_lsem_i.R" "$task_id"
