#!/bin/bash
# =============================================================================
# run_sequential.sh — Submit methods one at a time, waiting for each to drain.
# Stays under bwForCluster Helix's QOSMaxSubmitJobPerUserLimit.
#
# Usage:
#   bash slurm/run_sequential.sh                  # full pipeline (gen + all methods + aggr)
#   bash slurm/run_sequential.sh skip_gen         # methods only, assuming gen_data is done
#   bash slurm/run_sequential.sh skip_gen <jobid> # wait for gen_data <jobid> first, then methods
#
# Tip: run with nohup to survive disconnects:
#   nohup bash slurm/run_sequential.sh > sequential_run.log 2>&1 &
#   disown
#   tail -f sequential_run.log
# =============================================================================

set -e
cd "$HOME/cluster_nonlinear/dmavae_sim"

wait_for_drain() {
    local jobid=$1
    echo "$(date '+%H:%M:%S')  waiting for job $jobid to drain..."
    while squeue -u "$USER" -j "$jobid" -h 2>/dev/null | grep -q .; do
        sleep 60
    done
    echo "$(date '+%H:%M:%S')  job $jobid done."
}

# --- 1. Data generation ----------------------------------------------------
if [ "$1" = "skip_gen" ]; then
    echo "Skipping gen_data submission."
    if [ -n "$2" ]; then
        echo "Waiting for existing gen_data job $2 to finish first..."
        wait_for_drain "$2"
    fi
else
    GEN=$(sbatch --parsable slurm/gen_data.sbatch)
    echo "Submitted gen_data: $GEN"
    wait_for_drain "$GEN"
fi

# --- 2. Methods, one at a time --------------------------------------------
for m in lsem lsem_i dml dmavae cmavae; do
    JID=$(sbatch --parsable slurm/run_${m}.sbatch)
    echo "Submitted run_${m}: $JID"
    wait_for_drain "$JID"
done

# --- 3. Aggregate ----------------------------------------------------------
AGG=$(sbatch --parsable slurm/aggregate.sbatch)
echo "Submitted aggregate: $AGG"
wait_for_drain "$AGG"
echo "DONE. All results in $HOME/cluster_nonlinear/dmavae_sim/performance_*/"
