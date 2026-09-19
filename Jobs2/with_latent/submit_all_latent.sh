#!/bin/bash
# =============================================================================
# submit_all_latent.sh — Latent JOBS II pipeline, throttled for MaxSubmitPU=1500.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(pwd)"
echo "[submit] PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -f "slurm/gen_data.sbatch" ]; then
  echo "ERROR: Run from the project root (must contain slurm/)."
  exit 1
fi

for must in "array=1-1000" "TASK_OFFSET" "generate_jobs2_latent.R"; do
  if ! grep -q "$must" slurm/gen_data.sbatch; then
    echo "ERROR: slurm/gen_data.sbatch missing '$must'. Run setup_latent_run.sh first."
    exit 1
  fi
done

mkdir -p logs

# Concurrent task limits
CONC_GEN=200
CONC_R=100
CONC_PY=500

OFFSETS=(0 1000 2000 3000)

submit_chunk() {
  local sbatch_file="$1"
  local offset="$2"
  local conc="$3"
  local dep="${4:-}"

  local args=(--parsable)
  args+=("--export=ALL,TASK_OFFSET=${offset}")
  args+=("--array=1-1000%${conc}")
  args+=("--job-name=$(basename ${sbatch_file} .sbatch)_o${offset}")
  if [ -n "$dep" ]; then
    args+=("--dependency=${dep}")
  fi
  args+=("$sbatch_file")
  sbatch "${args[@]}"
}

submit_method_sequential() {
  local sbatch_file="$1"
  local label="$2"
  local conc="$3"
  local starting_dep="$4"

  echo "[submit] === ${label} (4 chunks, sequential, %${conc}) ===" >&2
  local prev_dep="$starting_dep"
  local last_jid=""
  for off in "${OFFSETS[@]}"; do
    local jid
    jid=$(submit_chunk "$sbatch_file" "$off" "$conc" "$prev_dep")
    echo "  ${label}  offset=${off}  -> jobid ${jid}  (dep=${prev_dep})" >&2
    prev_dep="afterany:${jid}"
    last_jid="$jid"
  done
  echo "$last_jid"
}

# (1) gen_data: 4 chunks, sequential
echo "[submit] === gen_data (4 chunks, sequential, %${CONC_GEN}) ==="
GEN_PREV=""
GEN_LAST_JID=""
for off in "${OFFSETS[@]}"; do
  JID=$(submit_chunk slurm/gen_data.sbatch "$off" "$CONC_GEN" "$GEN_PREV")
  echo "  gen_data  offset=${off}  -> jobid ${JID}  (dep=${GEN_PREV:-none})"
  GEN_PREV="afterany:${JID}"
  GEN_LAST_JID="$JID"
done

# (2) Estimators, chained sequentially
PREV_DEP="afterany:${GEN_LAST_JID}"

LSEM_LAST=$(submit_method_sequential slurm/run_lsem.sbatch    "lsem"    "$CONC_R"  "$PREV_DEP")
PREV_DEP="afterany:${LSEM_LAST}"

LSEMI_LAST=$(submit_method_sequential slurm/run_lsem_i.sbatch "lsem_i"  "$CONC_R"  "$PREV_DEP")
PREV_DEP="afterany:${LSEMI_LAST}"

DML_LAST=$(submit_method_sequential slurm/run_dml.sbatch      "dml"     "$CONC_R"  "$PREV_DEP")
PREV_DEP="afterany:${DML_LAST}"

DMAVAE_LAST=$(submit_method_sequential slurm/run_dmavae.sbatch "dmavae" "$CONC_PY" "$PREV_DEP")
PREV_DEP="afterany:${DMAVAE_LAST}"

CMAVAE_LAST=$(submit_method_sequential slurm/run_cmavae.sbatch "cmavae" "$CONC_PY" "$PREV_DEP")
PREV_DEP="afterany:${CMAVAE_LAST}"

# (3) Aggregate
AGG_JOB=$(sbatch --parsable --dependency="$PREV_DEP" slurm/aggregate.sbatch)
echo "[submit] === aggregate ==="
echo "  aggregate -> jobid ${AGG_JOB}  (after ${PREV_DEP})"

echo ""
echo "============================================================"
echo "  All jobs submitted. Pipeline runs hands-off; safe to disconnect."
echo "============================================================"
echo ""
echo "Concurrent task budget per chunk:"
echo "  gen_data:        ${CONC_GEN}"
echo "  lsem/lsem_i/dml: ${CONC_R}"
echo "  dmavae/cmavae:   ${CONC_PY}"
echo ""

{
  echo "Submitted: $(date)"
  echo "PROJECT_ROOT: $PROJECT_ROOT"
  echo ""
  echo "Last job IDs:"
  echo "  gen_data (last chunk):  $GEN_LAST_JID"
  echo "  lsem     (last chunk):  $LSEM_LAST"
  echo "  lsem_i   (last chunk):  $LSEMI_LAST"
  echo "  dml      (last chunk):  $DML_LAST"
  echo "  dmavae   (last chunk):  $DMAVAE_LAST"
  echo "  cmavae   (last chunk):  $CMAVAE_LAST"
  echo "  aggregate:              $AGG_JOB"
} | tee .last_submission.txt
