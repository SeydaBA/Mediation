#!/bin/bash
set -euo pipefail

GEN_CHUNK0=13291338
CONC_GEN=200
CONC_R=100
CONC_PY=500
OFFSETS=(0 1000 2000 3000)

robust_sbatch() {
  local out=""
  while true; do
    if out=$(sbatch "$@" 2>&1); then
      echo "$out"
      return 0
    fi
    if echo "$out" | grep -q "QOSMaxSubmit"; then
      echo "  [wait] queue full ($(squeue -u $USER -r -h | wc -l) tasks), sleeping 5 min..." >&2
      sleep 300
    else
      echo "ERROR: $out" >&2
      return 1
    fi
  done
}

submit_chunk() {
  local sbatch_file="$1"
  local offset="$2"
  local conc="$3"
  local dep="$4"
  robust_sbatch --parsable \
    --export=ALL,TASK_OFFSET=${offset} \
    --array=1-1000%${conc} \
    --job-name=$(basename ${sbatch_file} .sbatch)_o${offset} \
    --dependency=${dep} \
    "$sbatch_file"
}

submit_method_seq() {
  local sbatch_file="$1"
  local conc="$2"
  local starting_dep="$3"
  local prev_dep="$starting_dep"
  local last=""
  for off in "${OFFSETS[@]}"; do
    jid=$(submit_chunk "$sbatch_file" "$off" "$conc" "$prev_dep")
    echo "  $(basename $sbatch_file) o=$off -> $jid (dep=$prev_dep)" >&2
    prev_dep="afterany:${jid}"
    last="$jid"
  done
  echo "$last"
}

echo "=== Finishing gen_data (chunks 1, 2, 3 chained after $GEN_CHUNK0) ==="
PREV="afterany:${GEN_CHUNK0}"
GEN_LAST=""
for off in 1000 2000 3000; do
  jid=$(submit_chunk slurm/gen_data.sbatch "$off" "$CONC_GEN" "$PREV")
  echo "  gen_data o=$off -> $jid (dep=$PREV)"
  PREV="afterany:${jid}"
  GEN_LAST="$jid"
done

echo ""
echo "=== Estimators ==="
PREV="afterany:${GEN_LAST}"
PREV=afterany:$(submit_method_seq slurm/run_lsem.sbatch    "$CONC_R"  "$PREV")
PREV=afterany:$(submit_method_seq slurm/run_lsem_i.sbatch  "$CONC_R"  "$PREV")
PREV=afterany:$(submit_method_seq slurm/run_dml.sbatch     "$CONC_R"  "$PREV")
PREV=afterany:$(submit_method_seq slurm/run_dmavae.sbatch  "$CONC_PY" "$PREV")
PREV=afterany:$(submit_method_seq slurm/run_cmavae.sbatch  "$CONC_PY" "$PREV")

echo ""
echo "=== Aggregate ==="
AGG=$(robust_sbatch --parsable --dependency="$PREV" slurm/aggregate.sbatch)
echo "  aggregate -> $AGG"
echo ""
echo "All remaining pieces submitted."
