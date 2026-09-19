#!/bin/bash
# Resubmits the full DML run for ALL 8 scenarios (800 tasks).
# Use after the smoke test has verified the patch engages.
#
# Usage:
#   nohup bash run_dml_full.sh > dml_full_run.log 2>&1 &
#   disown

set -u
PROJECT_ROOT="$HOME/cluster_nonlinear/dmavae_sim"
cd "$PROJECT_ROOT"

echo "==================================================================="
echo "[dml_full] Started: $(date)"
echo "[dml_full] Host: $(hostname)"
echo "[dml_full] PROJECT_ROOT=$PROJECT_ROOT"
echo "==================================================================="

# --- Pre-flight checks -------------------------------------------------
echo
echo "[dml_full] Pre-flight checks..."
echo "  - patch_LARF.R exists: $([ -f R/patch_LARF.R ] && echo YES || echo NO)"
echo "  - patch sourced in run_dml.R: $(grep -c patch_LARF R/run_dml.R) line(s)"
echo "  - ORDER setting:"; grep '^ORDER' R/run_dml.R | sed 's/^/      /'
echo "  - sbatch env (grep gnu/14.1):"; grep "gnu/14.1" slurm/run_dml.sbatch | sed 's/^/      /'
echo "  - sbatch walltime:"; grep "time=" slurm/run_dml.sbatch | sed 's/^/      /'
echo "  - sbatch memory:"; grep "mem-per-cpu" slurm/run_dml.sbatch | sed 's/^/      /'
echo

# --- Clean any partial output ------------------------------------------
echo "[dml_full] Cleaning all DML output directories..."
rm -rf performance_dml performance_dml_oracle
mkdir -p logs
echo

# --- Submit all 800 tasks ----------------------------------------------
echo "[dml_full] Submitting array=1-800 (800 tasks total)..."
SUBMIT_OUTPUT=$(sbatch --array=1-800 slurm/run_dml.sbatch)
echo "  $SUBMIT_OUTPUT"
JOBID=$(echo "$SUBMIT_OUTPUT" | grep -oE '[0-9]+$')
echo "[dml_full] Job ID: $JOBID"
echo

# --- Wait loop ---------------------------------------------------------
echo "[dml_full] Waiting for job $JOBID to drain..."
echo "  Polling every 5 min. Safe to disconnect SSH at this point."

WAITED=0
while true; do
  PENDING_OR_RUNNING=$(squeue -u "$USER" -h -j "$JOBID" 2>/dev/null | wc -l)
  if [ "$PENDING_OR_RUNNING" -eq 0 ]; then
    echo "[dml_full] Job $JOBID drained at $(date) (waited ${WAITED} min)"
    break
  fi
  if (( WAITED % 30 == 0 )); then
    echo "[dml_full] $(date '+%H:%M:%S')  still running ($PENDING_OR_RUNNING tasks left after ${WAITED} min)"
  fi
  sleep 300
  WAITED=$((WAITED + 5))
done

# --- Count results -----------------------------------------------------
echo
echo "[dml_full] Counting completed rep files per scenario..."
for sc in N1000_nX10_sx1 N4000_nX10_sx1 N1000_nX200_sx1 N4000_nX200_sx1 \
          N1000_nX10_sx3 N4000_nX10_sx3 N1000_nX200_sx3 N4000_nX200_sx3; do
  n_proxy=$(ls performance_dml/$sc/*.csv 2>/dev/null | wc -l)
  n_oracle=$(ls performance_dml_oracle/$sc/*.csv 2>/dev/null | wc -l)
  echo "  $sc:  proxy=$n_proxy/100   oracle=$n_oracle/100"
done

# --- Run aggregator ----------------------------------------------------
echo
echo "[dml_full] Running aggregator..."
source /opt/bwhpc/common/devel/miniconda/3-py39-23.10.0/etc/profile.d/conda.sh
conda activate dmavae
export PYTHONNOUSERSITE=1
cd "$PROJECT_ROOT/py"
python aggregate_results.py 2>&1 | tail -20

echo
echo "[dml_full] DML rows in final summary:"
grep "^dml," "$PROJECT_ROOT/summary_all_methods.csv"
echo
echo "==================================================================="
echo "[dml_full] DONE: $(date)"
echo "==================================================================="
