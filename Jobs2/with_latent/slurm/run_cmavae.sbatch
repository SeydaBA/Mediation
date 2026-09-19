#!/bin/bash
#SBATCH --array=1-1000
#SBATCH --cpus-per-task=2
#SBATCH --job-name=cmavae_j2
#SBATCH --output=logs/cmavae_%A_%a.out
#SBATCH --error=logs/cmavae_%A_%a.err
#SBATCH --time=02:30:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1

export PROJECT_ROOT="/home/tu/tu_tu/tu_zxojs39/cluster_jobs2_latent/dmavae_sim"
# __TASK_OFFSET_PATCH__
TASK_OFFSET=${TASK_OFFSET:-0}
task_id=$(( SLURM_ARRAY_TASK_ID + TASK_OFFSET ))
echo "[chunk] offset=$TASK_OFFSET  array_id=$SLURM_ARRAY_TASK_ID  real_task_id=$task_id"
echo "[cmavae] task_id=$task_id  $(date)"
cd "$PROJECT_ROOT/py"
$HOME/.conda/envs/dmavae/bin/python run_cmavae.py "$task_id"
