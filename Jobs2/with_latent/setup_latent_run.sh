#!/bin/bash
# =============================================================================
# setup_latent_run.sh — One-shot setup for the latent-confounder JOBS II run.
#
# Patches sbatch files so the 4000-task pipeline runs as four 1000-task
# chunks via TASK_OFFSET ∈ {0, 1000, 2000, 3000}.
#
# Inside each sbatch:
#     REAL_TASK_ID = SLURM_ARRAY_TASK_ID + TASK_OFFSET
# and the entry script (Rscript / python) is called with REAL_TASK_ID.
# This lets us cover task IDs 1..4000 with four submissions of --array=1-1000.
#
# Safe to re-run; the patch is idempotent (marked by a sentinel comment).
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(pwd)"
echo "[setup] PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -d "$PROJECT_ROOT/R" ] || [ ! -d "$PROJECT_ROOT/slurm" ]; then
  echo "ERROR: Run from the project root (must contain R/ and slurm/)."
  exit 1
fi

# --- 1. Sanity checks --------------------------------------------------------
if ! grep -q "p_c" R/scenarios.R; then
  echo "ERROR: R/scenarios.R does not contain a p_c grid."
  exit 1
fi
if [ ! -f "R/generate_jobs2_latent.R" ]; then
  echo "ERROR: R/generate_jobs2_latent.R is missing."
  exit 1
fi
echo "[setup] Latent generator + 40-scenario grid present. OK."

# --- 2. Stash old no-latent results -----------------------------------------
TS=$(date +%Y%m%d_%H%M%S)
STASH="$PROJECT_ROOT/_old_nolatent_${TS}"
mkdir -p "$STASH"
moved_any=0
for dir in input performance_lsem performance_lsem_i performance_dml performance_dmavae performance_cmavae; do
  if [ -d "$PROJECT_ROOT/$dir" ]; then
    mv "$PROJECT_ROOT/$dir" "$STASH/"
    echo "[setup] Stashed $dir -> $STASH/$dir"
    moved_any=1
  fi
done
for f in summary_all_methods*.csv; do
  if [ -f "$PROJECT_ROOT/$f" ]; then
    mv "$PROJECT_ROOT/$f" "$STASH/"
    moved_any=1
  fi
done
if [ "$moved_any" -eq 0 ]; then
  rmdir "$STASH"
  echo "[setup] No leftover results to stash."
else
  echo "[setup] Old results in $STASH (delete later if not needed)."
fi
mkdir -p logs

# --- 3. Patch sbatch files ---------------------------------------------------
patch_sbatch() {
  local f="$1"
  if [ ! -f "$f" ]; then
    echo "  [skip] $f not found"
    return
  fi

  # Force array to 1-1000 per chunk
  sed -i -E 's|^#SBATCH --array=[0-9]+-[0-9]+\b|#SBATCH --array=1-1000|' "$f"

  # Patch PROJECT_ROOT to current pwd
  sed -i -E "s|^export PROJECT_ROOT=.*|export PROJECT_ROOT=\"$PROJECT_ROOT\"|" "$f"

  # Add TASK_OFFSET logic (idempotent via sentinel comment)
  if ! grep -q "# __TASK_OFFSET_PATCH__" "$f"; then
    # Replace "task_id=$SLURM_ARRAY_TASK_ID" with the offset-aware version
    python3 - "$f" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as fp:
    content = fp.read()
replacement = (
    "# __TASK_OFFSET_PATCH__\n"
    "TASK_OFFSET=${TASK_OFFSET:-0}\n"
    "task_id=$(( SLURM_ARRAY_TASK_ID + TASK_OFFSET ))\n"
    'echo "[chunk] offset=$TASK_OFFSET  array_id=$SLURM_ARRAY_TASK_ID  real_task_id=$task_id"'
)
new = re.sub(r'^task_id=\$SLURM_ARRAY_TASK_ID\s*$', replacement,
             content, count=1, flags=re.MULTILINE)
with open(path, 'w') as fp:
    fp.write(new)
PYEOF
  fi

  echo "  [patched] $f"
}

echo "[setup] Patching slurm/*.sbatch ..."
for f in slurm/gen_data.sbatch slurm/run_lsem.sbatch slurm/run_lsem_i.sbatch \
         slurm/run_dml.sbatch  slurm/run_dmavae.sbatch slurm/run_cmavae.sbatch; do
  patch_sbatch "$f"
done

# aggregate.sbatch has no array; just fix PROJECT_ROOT
if [ -f slurm/aggregate.sbatch ]; then
  sed -i -E "s|^export PROJECT_ROOT=.*|export PROJECT_ROOT=\"$PROJECT_ROOT\"|" slurm/aggregate.sbatch
  echo "  [patched] slurm/aggregate.sbatch"
fi

# gen_data must call generate_jobs2_latent.R
if grep -q "generate_jobs2.R" slurm/gen_data.sbatch; then
  sed -i -E 's|generate_jobs2\.R|generate_jobs2_latent.R|g' slurm/gen_data.sbatch
  echo "  [patched] slurm/gen_data.sbatch -> generate_jobs2_latent.R"
fi

echo ""
echo "============================================================"
echo "  Setup complete."
echo "============================================================"
echo ""
echo "Verify:"
echo "  grep -H 'array=' slurm/*.sbatch"
echo "  grep -H 'PROJECT_ROOT=' slurm/*.sbatch"
echo "  grep -H 'TASK_OFFSET' slurm/*.sbatch"
echo "  grep -H 'generate_jobs2' slurm/gen_data.sbatch"
echo ""
echo "Then submit:"
echo "  bash submit_all_latent.sh"
echo ""
