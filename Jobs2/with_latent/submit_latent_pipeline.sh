#!/bin/bash
# =============================================================================
# submit_latent_pipeline.sh — Fresh end-to-end latent pipeline submission.
#
# Submits everything sequentially (gen → lsem → lsem_i → dml → dmavae →
# cmavae → aggregate), one 1000-task chunk at a time, with automatic retry
# on QOSMaxSubmitJobPerUserLimit. Designed to run inside tmux.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(pwd)"
echo "[submit] PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -f "slurm/gen_data.sbatch" ]; then
  echo "ERROR: Run from project root."
  exit 1
fi

mkdir -p logs

CONC_GEN=200
CONC_R=100
CONC_PY=500
OFFSETS=(0 1000 2000 3000)

# Retry sbatch every 5 min on QOS limit; bail on any other error.
robust_sbatch() {
  local out=""
  while true; do
    if out=$(sbatch "$@" 2>&1); then
      echo "$out"
      return 0
    fi
    if echo "$out" | grep -q "QOSMaxSubmit"; then
      local n=$(squeue -u $USER -r -h | wc -l)
      echo "  [wait] queue at ${n} tasks, sleeping 5 min..." >&2
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

# (1) gen_data: 4 chunks sequential
echo "[submit] === gen_data (4 chunks, sequential, %${CONC_GEN}) ==="
PREV=""
GEN_LAST=""
for off in "${OFFSETS[@]}"; do
  JID=$(submit_chunk slurm/gen_data.sbatch "$off" "$CONC_GEN" "$PREV")
  echo "  gen_data o=${off} -> ${JID} (dep=${PREV:-none})"
  PREV="afterany:${JID}"
  GEN_LAST="$JID"
done

# (2) Estimators chained
PREV="afterany:${GEN_LAST}"
PREV=afterany:$(submit_method slurm/run_lsem.sbatch    "lsem"    "$CONC_R"  "$PREV")
PREV=afterany:$(submit_method slurm/run_lsem_i.sbatch  "lsem_i"  "$CONC_R"  "$PREV")
PREV=afterany:$(submit_method slurm/run_dml.sbatch     "dml"     "$CONC_R"  "$PREV")
PREV=afterany:$(submit_method slurm/run_dmavae.sbatch  "dmavae"  "$CONC_PY" "$PREV")
PREV=afterany:$(submit_method slurm/run_cmavae.sbatch  "cmavae"  "$CONC_PY" "$PREV")

# (3) Aggregate
AGG=$(robust_sbatch --parsable --dependency="$PREV" slurm/aggregate.sbatch)
echo "[submit] === aggregate ==="
echo "  aggregate -> ${AGG}"

echo ""
echo "All pieces submitted. Pipeline runs hands-off."
echo "Job IDs saved to .last_submission.txt"

{
  echo "Submitted: $(date)"
  echo "PROJECT_ROOT: $PROJECT_ROOT"
  echo "Last chunk of each method (the one downstream jobs depend on):"
  echo "  gen_data:   $GEN_LAST"
  echo "  aggregate:  $AGG"
} > .last_submission.txt
