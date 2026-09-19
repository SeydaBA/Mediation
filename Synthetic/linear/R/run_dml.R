# =============================================================================
# run_dml.R — DML (Farbmacher et al. 2022, medDML) — ONE replication.
# Usage:
#   Rscript run_dml.R <task_id>
# =============================================================================

suppressPackageStartupMessages({
  library(causalweight)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_dml.R <task_id>")
task_id <- as.integer(args[1])

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR    <- file.path(PROJECT_ROOT, "input")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "rep_io.R"))

idx <- task_id_to_indices(task_id)
cat(sprintf("[run_dml] task=%d  scenario=%s  rep=%d\n",
            idx$task_id, idx$name, idx$rep))

rep_data <- read_rep(INPUT_DIR, idx$name, idx$rep)
sim      <- build_sim(rep_data)

K          <- 4
TRIM_LEVEL <- 0.05

dml_estimator <- function(sim, adjust = c("X", "Z")) {
  adjust <- match.arg(adjust)
  x_mat  <- if (adjust == "X") as.matrix(sim$X) else as.matrix(sim$Z)

  fit <- medDML(
    y = sim$y, d = sim$d, m = sim$m, x = x_mat,
    k = K, trim = TRIM_LEVEL,
    order = 1,             # linear DGP -> no expansion
    multmed = TRUE,
    fewsplits = FALSE
  )
  setNames(as.numeric(fit$results[1, 1:5]), c("ATE", "NDE(d=1)", "NDE(d=0)", "ACME(d=1)", "ACME(d=0)"))
}

# --- proxy X ----------------------------------------------------------------
est_proxy <- tryCatch(
  dml_estimator(sim, "X"),
  error = function(e) {
    cat(sprintf("[run_dml] DML failed (proxy X): %s\n", conditionMessage(e)))
    setNames(rep(NA_real_, 5),
             c("ATE","NDE(d=1)","NDE(d=0)","ACME(d=1)","ACME(d=0)"))
  }
)
write_result_row(
  perf_dir = file.path(PROJECT_ROOT, "performance_dml"),
  method   = "dml_proxyX",
  idx      = idx,
  est      = est_proxy,
  truth_df = rep_data$truth
)

# --- oracle Z ---------------------------------------------------------------
est_oracle <- tryCatch(
  dml_estimator(sim, "Z"),
  error = function(e) {
    cat(sprintf("[run_dml] DML failed (oracle Z): %s\n", conditionMessage(e)))
    setNames(rep(NA_real_, 5),
             c("ATE","NDE(d=1)","NDE(d=0)","ACME(d=1)","ACME(d=0)"))
  }
)
write_result_row(
  perf_dir = file.path(PROJECT_ROOT, "performance_dml_oracle"),
  method   = "dml_oracleZ",
  idx      = idx,
  est      = est_oracle,
  truth_df = rep_data$truth
)

cat(sprintf("[run_dml] done. proxy ATE=%+.3f  oracle ATE=%+.3f  (truth=%+.3f)\n",
            est_proxy["ATE"], est_oracle["ATE"], rep_data$truth$ATE))
