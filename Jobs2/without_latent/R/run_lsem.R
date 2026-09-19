# =============================================================================
# run_lsem.R — LSEM (Baron-Kenny, no T×M) on JOBS II semi-synthetic.
# Proxy X only (no oracle Z for real data).
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Usage: Rscript run_lsem.R <task_id>")
task_id <- as.integer(args[1])

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR <- file.path(PROJECT_ROOT, "input")
PERF_DIR  <- file.path(PROJECT_ROOT, "performance_lsem")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "rep_io.R"))

idx      <- task_id_to_indices(task_id)
rep_data <- read_rep(INPUT_DIR, idx$name, idx$rep)
sim      <- build_sim(rep_data)
truth    <- extract_truth(rep_data)

cat(sprintf("[run_lsem] task=%d  scenario=%s  rep=%d\n",
            task_id, idx$name, idx$rep))

# ---- LSEM (no T×M) ----------------------------------------------------------
# Mediator model:  M = a0 + a*T + b*X + e
# Outcome  model:  Y = c0 + c'*T + d*M + g*X + e
# NDE = c', NIE = a*d, ATE = c' + a*d
estimate_lsem <- function(y, d, m, X) {
  X_df <- as.data.frame(X)
  med_fit <- lm(m ~ d + ., data = cbind(m = m, d = d, X_df))
  a       <- unname(coef(med_fit)["d"])

  out_fit <- lm(y ~ d + m + ., data = cbind(y = y, d = d, m = m, X_df))
  c_prime <- unname(coef(out_fit)["d"])
  d_coef  <- unname(coef(out_fit)["m"])

  nde <- c_prime
  nie <- a * d_coef
  ate <- nde + nie
  c(ATE       = unname(ate),
    "NDE(d=1)" = unname(nde),
    "NDE(d=0)" = unname(nde),
    "ACME(d=1)" = unname(nie),
    "ACME(d=0)" = unname(nie))
}

est <- tryCatch(
  estimate_lsem(sim$y, sim$d, sim$m, sim$X),
  error = function(e) {
    cat("[run_lsem] FAILED:", conditionMessage(e), "\n")
    c(ATE = NA, "NDE(d=1)" = NA, "NDE(d=0)" = NA, "ACME(d=1)" = NA, "ACME(d=0)" = NA)
  }
)

write_result(PERF_DIR, idx$name, idx$rep, "lsem_proxyX", idx, est, truth)

cat(sprintf("[run_lsem] done.  ATE=%+.3f  (truth=%+.3f)\n",
            est["ATE"], truth$ATE))
