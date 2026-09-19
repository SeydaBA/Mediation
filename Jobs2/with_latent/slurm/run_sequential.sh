#!/bin/bash
# run_sequential.sh — submit JOBS II pipeline stages in order.
# Each stage waits for the previous to drain before submitting.
#
# Usage (disconnect-safe):
#   cd $HOME/cluster_jobs2/dmavae_sim
#   nohup bash slurm/run_sequential.sh > sequential_run.log 2>&1 &
#   disown
#
# Reconnect later and check:
#   tail -f sequential_run.log

set -u
PROJECT_ROOT="$HOME/cluster_jobs2/dmavae_sim"
cd "$PROJECT_ROOT"
mkdir -p logs

echo "======================================================================"
echo "[seq] JOBS II pipeline started: $(date)"
echo "======================================================================"

wait_for_job() {
  local jobid=$1
  local stage=$2
  local waited=0
  while squeue -u "$USER" -h -j "$jobid" 2>/dev/null | grep -q .; do
    if (( waited % 30 == 0 )); then
      local remaining
      remaining=$(squeue -u "$USER" -h -j "$jobid" 2>/dev/null | wc -l)
      echo "[seq] $(date '+%H:%M:%S') $stage  $remaining tasks remaining (waited ${waited} min)"
    fi
    sleep 60
    waited=$((waited + 1))
  done
  echo "[seq] $(date '+%H:%M:%S') $stage  COMPLETE (waited ${waited} min)"
}

submit_stage() {
  local sbatch_file=$1
  local stage_name=$2
  echo
  echo "[seq] Submitting $stage_name ..."
  local output
  output=$(sbatch "$sbatch_file")
  echo "  $output"
  local jobid
  jobid=$(echo "$output" | grep -oE '[0-9]+$')
  wait_for_job "$jobid" "$stage_name"
}

# ---- 1. Generate data ----
# submit_stage slurm/gen_data.sbatch  "gen_data"

# ---- 2-6. Run methods ----
submit_stage slurm/run_lsem.sbatch   "lsem"
submit_stage slurm/run_lsem_i.sbatch "lsem_i"
submit_stage slurm/run_dml.sbatch    "dml"
submit_stage slurm/run_dmavae.sbatch "dmavae"
submit_stage slurm/run_cmavae.sbatch "cmavae"

# ---- 7. Aggregate ----
submit_stage slurm/aggregate.sbatch  "aggregate"

# ---- Final report ----
echo
echo "======================================================================"
echo "[seq] All stages complete: $(date)"
echo "======================================================================"
if [ -f "$PROJECT_ROOT/summary_all_methods.csv" ]; then
  echo
  echo "[seq] Final summary preview:"
  head -1 "$PROJECT_ROOT/summary_all_methods.csv"
  awk -F, 'NR > 1 {print "  " $1 "  " $3 "  ATE_rmse=" $11}' "$PROJECT_ROOT/summary_all_methods.csv"
fi
