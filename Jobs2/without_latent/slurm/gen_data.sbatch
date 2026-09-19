#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=1
#SBATCH --job-name=gen_j2
#SBATCH --output=logs/gen_%A_%a.out
#SBATCH --error=logs/gen_%A_%a.err
#SBATCH --time=00:10:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=2000

module purge
module load math/R/4.3.3
module load compiler/gnu/14.1

export PATH=/opt/bwhpc/common/compiler/gnu/14.1/bin:$PATH
export LD_LIBRARY_PATH=/opt/bwhpc/common/compiler/gnu/14.1/lib64:$LD_LIBRARY_PATH

export PROJECT_ROOT="$HOME/cluster_jobs2/dmavae_sim"
task_id=$SLURM_ARRAY_TASK_ID

echo "[gen] task_id=$task_id  $(date)"
cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/generate_jobs2.R" "$task_id"
