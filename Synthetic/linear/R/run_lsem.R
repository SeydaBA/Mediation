# =============================================================================
# run_lsem.R — LSEM (Baron-Kenny, no T*M interaction) — ONE replication.
#
# Usage:
#   Rscript run_lsem.R <task_id>      # task_id in 1..800
#
# For each task_id, runs the estimator with BOTH adjustments (oracle Z, proxy X)
# and writes ONE row per adjustment to:
#   $PROJECT_ROOT/performance_lsem/<scenario>/rep<rep>.csv   (proxy X)
#   $PROJECT_ROOT/performance_lsem_oracle/<scenario>/rep<rep>.csv   (oracle Z)
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_lsem.R <task_id>")
task_id <- as.integer(args[1])

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR    <- file.path(PROJECT_ROOT, "input")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "rep_io.R"))

idx <- task_id_to_indices(task_id)
cat(sprintf("[run_lsem] task=%d  scenario=%s  rep=%d\n",
            idx$task_id, idx$name, idx$rep))

rep_data <- read_rep(INPUT_DIR, idx$name, idx$rep)
sim      <- build_sim(rep_data)

lsem_estimator <- function(sim, adjust = c("X", "Z")) {
  adjust    <- match.arg(adjust)
  covars    <- if (adjust == "X") sim$X else sim$Z
  cov_names <- names(covars)

  dat <- data.frame(y = sim$y, d = sim$d, m = sim$m, covars)
  cov_formula <- paste(cov_names, collapse = " + ")

  fit_m <- lm(as.formula(paste("m ~ d +", cov_formula)), data = dat)
  a     <- coef(fit_m)["d"]

  # No T*M interaction in outcome model
  fit_y <- lm(as.formula(paste("y ~ d + m +", cov_formula)), data = dat)
  c_prime <- coef(fit_y)["d"]
  b       <- coef(fit_y)["m"]

  acme <- a * b
  nde  <- c_prime
  ate  <- acme + nde

  c(ATE = unname(ate), "NDE(d=1)" = unname(nde), "NDE(d=0)" = unname(nde),
    "ACME(d=1)" = unname(acme), "ACME(d=0)" = unname(acme))
}

# ---- proxy X adjustment (the realistic setting) ----------------------------
est_proxy  <- lsem_estimator(sim, "X")
write_result_row(
  perf_dir = file.path(PROJECT_ROOT, "performance_lsem"),
  method   = "lsem_proxyX",
  idx      = idx,
  est      = est_proxy,
  truth_df = rep_data$truth
)

# ---- oracle Z adjustment (the unobserved-confounder benchmark) -------------
est_oracle <- lsem_estimator(sim, "Z")
write_result_row(
  perf_dir = file.path(PROJECT_ROOT, "performance_lsem_oracle"),
  method   = "lsem_oracleZ",
  idx      = idx,
  est      = est_oracle,
  truth_df = rep_data$truth
)

cat(sprintf("[run_lsem] done. proxy ATE=%+.3f  oracle ATE=%+.3f  (truth=%+.3f)\n",
            est_proxy["ATE"], est_oracle["ATE"], rep_data$truth$ATE))
