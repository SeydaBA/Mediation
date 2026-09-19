#!/bin/bash
#SBATCH --array=1-800
#SBATCH --cpus-per-task=2
#SBATCH --job-name=run_cmavae_nl
#SBATCH --output=logs/cmavae_%A_%a.out
#SBATCH --error=logs/cmavae_%A_%a.err
#SBATCH --time=02:30:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

module purge
export PATH=/opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/bin:$PATH
source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK

export PROJECT_ROOT="$HOME/cluster_nonlinear/dmavae_sim"

task_id=$SLURM_ARRAY_TASK_ID
echo "[cmavae_nl] task_id=$task_id  cpus=$SLURM_CPUS_PER_TASK  $(date)"

cd "$PROJECT_ROOT/py"
/home/tu/tu_tu/tu_zxojs39/.conda/envs/dmavae/bin/python run_cmavae.py "$task_id"
