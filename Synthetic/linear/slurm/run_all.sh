#!/bin/bash
# =============================================================================
# run_all.sh — submit the full pipeline with SLURM job dependencies.
#
# Usage:
#   cd $HOME/cluster_linear/dmavae_sim
#   bash slurm/run_all.sh                # everything (gen + all methods + aggr)
#   bash slurm/run_all.sh skip_gen       # methods only, reuse existing input/
#   bash slurm/run_all.sh only lsem dml  # only those methods (after gen)
#
# Dependencies:
#   gen_data  -> [lsem, lsem_i, dml, dmavae, cmavae]  -> aggregate
# =============================================================================

set -e
cd "$HOME/cluster_linear/dmavae_sim"
mkdir -p logs

SKIP_GEN=0
ONLY_METHODS=""

if [ "$1" = "skip_gen" ]; then
    SKIP_GEN=1
    shift
fi
if [ "$1" = "only" ]; then
    shift
    ONLY_METHODS="$*"
fi

method_in_list() {
    local m="$1"
    [ -z "$ONLY_METHODS" ] && return 0          # no filter => include all
    for x in $ONLY_METHODS; do [ "$x" = "$m" ] && return 0; done
    return 1
}

# --- 1. Data generation -----------------------------------------------------
if [ "$SKIP_GEN" -eq 0 ]; then
    GEN=$(sbatch --parsable slurm/gen_data.sbatch)
    echo "Submitted gen_data:   job array $GEN"
    DEP="--dependency=afterok:$GEN"
else
    DEP=""
    echo "Skipping data generation (using existing input/)."
fi

# --- 2. Methods (all depend on gen_data finishing) --------------------------
JOBS=()
for m in lsem lsem_i dml dmavae cmavae; do
    if method_in_list "$m"; then
        JID=$(sbatch --parsable $DEP slurm/run_${m}.sbatch)
        echo "Submitted run_${m}:  job array $JID"
        JOBS+=("$JID")
    fi
done

# --- 3. Aggregation (depends on all method jobs) ----------------------------
if [ ${#JOBS[@]} -gt 0 ]; then
    DEP_ALL="--dependency=afterany:$(IFS=:; echo "${JOBS[*]}")"
    AGG=$(sbatch --parsable $DEP_ALL slurm/aggregate.sbatch)
    echo "Submitted aggregate:  job $AGG"
fi

echo
echo "Submitted. Monitor with: squeue -u \$USER"
