#!/bin/bash
#SBATCH --cpus-per-task=1
#SBATCH --job-name=agg_j2
#SBATCH --output=logs/aggregate_%j.out
#SBATCH --error=logs/aggregate_%j.err
#SBATCH --time=00:10:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1

export PROJECT_ROOT="$HOME/cluster_jobs2/dmavae_sim"
cd "$PROJECT_ROOT/py"
$HOME/.conda/envs/dmavae/bin/python aggregate_results.py
