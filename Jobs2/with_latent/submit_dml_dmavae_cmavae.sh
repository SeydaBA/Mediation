#!/bin/bash
# =============================================================================
# submit_dml_dmavae_cmavae.sh — Resubmit DML (with skip), then DMAVAE, CMAVAE,
# aggregate. Sequential chunks, retries on QOS limit AND slurmctld outages.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(pwd)"
echo "[submit] PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -f "slurm/run_dml.sbatch" ]; then
  echo "ERROR: Run from project root."
  exit 1
fi

mkdir -p logs

CONC_R=100
CONC_PY=500
OFFSETS=(0 1000 2000 3000)

# Retry sbatch on transient cluster errors.
robust_sbatch() {
  local out=""
  while true; do
    if out=$(sbatch "$@" 2>&1); then
      echo "$out"
      return 0
    fi
    if echo "$out" | grep -qE "QOSMaxSubmit|Unable to contact slurm controller|connect failure|Socket timed out|Resource temporarily unavailable"; then
      echo "  [wait] transient error, sleeping 5 min: $out" >&2
      sleep 300
    else
      echo "ERROR (non-retryable): $out" >&2
      return 1
    fi
  done
}

submit_chunk() {
  local sbatch_file="$1"
  local offset="$2"
  local conc="$3"
  local dep="${4:-}"
  local args=(--parsable)
  args+=("--export=TASK_OFFSET=${offset}")
  args+=("--array=1-1000%${conc}")
  args+=("--job-name=$(basename ${sbatch_file} .sbatch)_o${offset}")
  if [ -n "$dep" ]; then args+=("--dependency=${dep}"); fi
  args+=("$sbatch_file")
  robust_sbatch "${args[@]}"
}

submit_method() {
  local sbatch_file="$1"
  local label="$2"
  local conc="$3"
  local starting_dep="$4"
  echo "[submit] === ${label} (4 chunks, sequential, %${conc}) ===" >&2
  local prev_dep="$starting_dep"
  local last=""
  for off in "${OFFSETS[@]}"; do
    local jid
    jid=$(submit_chunk "$sbatch_file" "$off" "$conc" "$prev_dep")
    echo "  ${label} o=${off} -> ${jid} (dep=${prev_dep})" >&2
    prev_dep="afterany:${jid}"
    last="$jid"
  done
  echo "$last"
}

# (1) DML — skip-if-exists makes the 2000 done reps near-instant
PREV=""
PREV=afterany:$(submit_method slurm/run_dml.sbatch    "dml"    "$CONC_R"  "$PREV")

# (2) DMAVAE
PREV=afterany:$(submit_method slurm/run_dmavae.sbatch "dmavae" "$CONC_PY" "$PREV")

# (3) CMAVAE
PREV=afterany:$(submit_method slurm/run_cmavae.sbatch "cmavae" "$CONC_PY" "$PREV")

# (4) Aggregate
AGG=$(robust_sbatch --parsable --dependency="$PREV" slurm/aggregate.sbatch)
echo "[submit] === aggregate ==="
echo "  aggregate -> ${AGG}"

echo ""
echo "All pieces submitted. Pipeline runs hands-off."

{
  echo "Submitted: $(date)"
  echo "PROJECT_ROOT: $PROJECT_ROOT"
  echo "Aggregate jobid: $AGG"
} > .last_submission_part2.txt
