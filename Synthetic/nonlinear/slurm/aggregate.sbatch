#!/bin/bash
#SBATCH --cpus-per-task=1
#SBATCH --job-name=aggregate_nl
#SBATCH --output=logs/aggregate_%j.out
#SBATCH --error=logs/aggregate_%j.err
#SBATCH --time=00:20:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

module purge
export PATH=/opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/bin:$PATH
source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1

export PROJECT_ROOT="$HOME/cluster_nonlinear/dmavae_sim"

cd "$PROJECT_ROOT/py"
/home/tu/tu_tu/tu_zxojs39/.conda/envs/dmavae/bin/python aggregate_results.py
