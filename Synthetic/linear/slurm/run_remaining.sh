#!/bin/bash
set -e
cd "$HOME/cluster_linear/dmavae_sim"

wait_for_drain() {
    local jobid=$1
    echo "$(date '+%H:%M:%S')  waiting for job $jobid..."
    while squeue -u "$USER" -j "$jobid" -h 2>/dev/null | grep -q .; do
        sleep 60
    done
    echo "$(date '+%H:%M:%S')  job $jobid done."
}

for m in dmavae cmavae; do
    JID=$(sbatch --parsable slurm/run_${m}.sbatch)
    echo "Submitted run_${m}: $JID"
    wait_for_drain "$JID"
done

AGG=$(sbatch --parsable slurm/aggregate.sbatch)
echo "Submitted aggregate: $AGG"
wait_for_drain "$AGG"
echo "ALL DONE."
