#!/bin/bash
# Submit methods one at a time, waiting for each to drain.
# Stays under QOSMaxSubmitJobPerUserLimit.

set -e
cd "$HOME/cluster_linear/dmavae_sim"

wait_for_drain() {
    local jobid=$1
    echo "$(date '+%H:%M:%S')  waiting for job $jobid to drain..."
    while squeue -u "$USER" -j "$jobid" -h 2>/dev/null | grep -q .; do
        sleep 60
    done
    echo "$(date '+%H:%M:%S')  job $jobid done."
}

# If 'skip_gen' is passed, assume gen_data is already done or in progress.
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

# Methods, one at a time
for m in lsem lsem_i dml dmavae cmavae; do
    JID=$(sbatch --parsable slurm/run_${m}.sbatch)
    echo "Submitted run_${m}: $JID"
    wait_for_drain "$JID"
done

# Aggregate
AGG=$(sbatch --parsable slurm/aggregate.sbatch)
echo "Submitted aggregate: $AGG"
echo "Done. Final job: $AGG"
