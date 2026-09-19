#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=1
#SBATCH --job-name=gen_data_nl
#SBATCH --output=logs/gen_data_%A_%a.out
#SBATCH --error=logs/gen_data_%A_%a.err
#SBATCH --time=00:15:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=2000

# =============================================================================
# Nonlinear: 8 scenarios × 100 reps = 800 array tasks.
# =============================================================================

module purge
module load math/R/4.3.3

export PROJECT_ROOT="$HOME/cluster_nonlinear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[gen_data_nl] task_id=$task_id  host=$(hostname)  $(date)"

cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/generate_data.R" "$task_id"
