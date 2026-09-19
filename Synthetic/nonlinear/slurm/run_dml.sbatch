#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=1
#SBATCH --job-name=run_dml_nl
#SBATCH --output=logs/dml_%A_%a.out
#SBATCH --error=logs/dml_%A_%a.err
#SBATCH --time=5-00:00:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=32000

module purge
module load math/R/4.3.3
module load compiler/gnu/14.1

# Belt-and-suspenders: also explicitly prepend 14.1 paths
export PATH=/opt/bwhpc/common/compiler/gnu/14.1/bin:$PATH
export LD_LIBRARY_PATH=/opt/bwhpc/common/compiler/gnu/14.1/lib64:$LD_LIBRARY_PATH

export PROJECT_ROOT="$HOME/cluster_nonlinear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[dml_nl] task_id=$task_id  $(date)"
echo "[dml_nl] gcc: $(gcc --version | head -1)"
echo "[dml_nl] which gcc: $(which gcc)"
echo "[dml_nl] LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

cd "$PROJECT_ROOT"
Rscript "$PROJECT_ROOT/R/run_dml.R" "$task_id"
