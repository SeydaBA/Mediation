#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=1
#SBATCH --job-name=gen_data
#SBATCH --output=logs/gen_data_%A_%a.out
#SBATCH --error=logs/gen_data_%A_%a.err
#SBATCH --time=00:15:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=2000

# =============================================================================
# gen_data.sbatch — Generate ONE replication per array task.
#
# Total: 8 scenarios x 100 reps = 800 array tasks.
#
# Submit with:
#   cd $HOME/cluster_linear/dmavae_sim
#   mkdir -p logs
#   sbatch slurm/gen_data.sbatch
# =============================================================================

module purge
module load math/R/4.3.3

# Project root must be the directory that contains R/, py/, slurm/, input/, ...
export PROJECT_ROOT="$HOME/cluster_linear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[gen_data] task_id=$task_id  host=$(hostname)  $(date)"

cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/generate_data.R" "$task_id"
