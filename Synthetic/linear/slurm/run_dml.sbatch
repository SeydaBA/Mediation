#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=1
#SBATCH --job-name=run_dml
#SBATCH --output=logs/dml_%A_%a.out
#SBATCH --error=logs/dml_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

# DML (medDML) uses cross-fitting with ML learners; needs more time/memory
# than LSEM, especially for n_X=200 and N=4000.

module purge
module load math/R/4.3.3

export PROJECT_ROOT="$HOME/cluster_linear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[dml] task_id=$task_id  $(date)"

cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/run_dml.R" "$task_id"
