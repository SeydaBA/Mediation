# =============================================================================
# generate_data.R — Generate ONE replication of the nonlinear-in-Z DGP
#                   (see shared_dgp_nonlinear.R for the structural equations).
#
# Usage (called from sbatch):
#   Rscript generate_data.R <task_id>     # task_id in 1..800
#
# Writes to:
#   $INPUT_DIR/<scenario_name>/rep<rep>_x.csv
#   $INPUT_DIR/<scenario_name>/rep<rep>_m.csv
#   $INPUT_DIR/<scenario_name>/rep<rep>_t.csv
#   $INPUT_DIR/<scenario_name>/rep<rep>_y.csv
#   $INPUT_DIR/<scenario_name>/rep<rep>_z.csv
#   $INPUT_DIR/<scenario_name>/rep<rep>_truth.csv
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript generate_data.R <task_id>")
task_id <- as.integer(args[1])

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR    <- file.path(PROJECT_ROOT, "input")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "shared_dgp_nonlinear.R"))

idx <- task_id_to_indices(task_id)
cat(sprintf("[generate_data] task_id=%d  scenario_id=%d (%s)  rep=%d  N=%d  n_X=%d  sigma_x=%g  sigma_m=%g  sigma_y=%g\n",
            idx$task_id, idx$scenario_id, idx$name, idx$rep,
            idx$N, idx$n_X, idx$sigma_x, SIGMA_M, SIGMA_Y))

# Deterministic seed: same (scenario, rep) always gives the same dataset
seed <- make_seed(idx$scenario_id, idx$rep)
set.seed(seed)

sim <- simulate_mediation_system(
  N        = idx$N,
  n_X      = idx$n_X,
  sigma_x  = idx$sigma_x,   # SD of proxy noise (scenario-specific: 0.7 or 2)
  sigma_m  = SIGMA_M,       # = 1
  sigma_y  = SIGMA_Y        # = 1
)

out_dir <- file.path(INPUT_DIR, idx$name)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

rep_tag <- sprintf("rep%03d", idx$rep)

# --- Write data files -------------------------------------------------------
write.csv(sim$X,
          file = file.path(out_dir, paste0(rep_tag, "_x.csv")),
          row.names = FALSE)

write.csv(data.frame(m = sim$m),
          file = file.path(out_dir, paste0(rep_tag, "_m.csv")),
          row.names = FALSE)

write.csv(data.frame(t = sim$d),
          file = file.path(out_dir, paste0(rep_tag, "_t.csv")),
          row.names = FALSE)

write.csv(data.frame(y = sim$y),
          file = file.path(out_dir, paste0(rep_tag, "_y.csv")),
          row.names = FALSE)

write.csv(sim$Z,
          file = file.path(out_dir, paste0(rep_tag, "_z.csv")),
          row.names = FALSE)

# --- True effects for this replication (sample-level, NOT population) ------
# These are the truths conditional on the realised draws of Z, X, em, ey.
ATE_true       <- sim$y11 - sim$y00
NDE_d1_true    <- sim$y11 - sim$y01
NDE_d0_true    <- sim$y10 - sim$y00
NIE_d1_true    <- sim$y11 - sim$y10   # ACME(d=1)
NIE_d0_true    <- sim$y01 - sim$y00   # ACME(d=0)

truth <- data.frame(
  scenario_id = idx$scenario_id,
  scenario    = idx$name,
  rep         = idx$rep,
  N           = idx$N,
  n_X         = idx$n_X,
  sigma_x     = idx$sigma_x,
  sigma_m     = SIGMA_M,
  sigma_y     = SIGMA_Y,
  seed        = seed,
  ATE         = ATE_true,
  NDE_d1      = NDE_d1_true,
  NDE_d0      = NDE_d0_true,
  NIE_d1      = NIE_d1_true,
  NIE_d0      = NIE_d0_true
)

write.csv(truth,
          file = file.path(out_dir, paste0(rep_tag, "_truth.csv")),
          row.names = FALSE)

cat(sprintf("[generate_data] wrote files to %s\n", out_dir))
