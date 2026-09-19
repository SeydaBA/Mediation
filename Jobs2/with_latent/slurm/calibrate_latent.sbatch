#!/bin/bash
#SBATCH --cpus-per-task=1
#SBATCH --job-name=calib_j2
#SBATCH --output=logs/calib_%j.out
#SBATCH --error=logs/calib_%j.err
#SBATCH --time=00:30:00
#SBATCH --partition=cpu-single
#SBATCH --mem-per-cpu=4000

module purge
module load math/R/4.3.3
module load compiler/gnu/14.1

export PATH=/opt/bwhpc/common/compiler/gnu/14.1/bin:$PATH
export LD_LIBRARY_PATH=/opt/bwhpc/common/compiler/gnu/14.1/lib64:$LD_LIBRARY_PATH

export PROJECT_ROOT="/home/tu/tu_tu/tu_zxojs39/cluster_jobs2_latent/dmavae_sim"
cd "/home/tu/tu_tu/tu_zxojs39/cluster_jobs2_latent/dmavae_sim"
echo "[calib] PROJECT_ROOT=/home/tu/tu_tu/tu_zxojs39/cluster_jobs2_latent/dmavae_sim  $(date)"
Rscript R/calibrate_alpha.R
