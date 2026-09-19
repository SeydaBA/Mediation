# =============================================================================
# run_lsem_i.R - LSEM-I (Imai et al., with T x M) on JOBS II semi-synthetic.
# Proxy X only.
# FIXED: NDE(d=1) now uses the treated mediator level m_d1 (was m_d0, which
# made NDE(d=1) = NDE(d=0) and biased the ATE by -0.5 * a_t * e_t).
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Usage: Rscript run_lsem_i.R <task_id>")
task_id <- as.integer(args[1])

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR <- file.path(PROJECT_ROOT, "input")
PERF_DIR  <- file.path(PROJECT_ROOT, "performance_lsem_i")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "rep_io.R"))

idx      <- task_id_to_indices(task_id)
rep_data <- read_rep(INPUT_DIR, idx$name, idx$rep)
sim      <- build_sim(rep_data)
truth    <- extract_truth(rep_data)

cat(sprintf("[run_lsem_i] task=%d  scenario=%s  rep=%d\n",
            task_id, idx$name, idx$rep))

# ---- LSEM-I (with T x M; Imai et al. 2010) ----------------------------------
# Mediator:  M = a0 + a*T + b*X + e
# Outcome :  Y = c0 + c1*T + d*M + e*T*M + g*X + err
# NDE(t) = c1 + e * E[M(t)],  E[M(t)] = a0 + a*t + b*mean(X)
# NIE(t) = a * (d_coef + e * t)
estimate_lsem_i <- function(y, d, m, X) {
  X_df <- as.data.frame(X)
  med_fit <- lm(m ~ d + ., data = cbind(m = m, d = d, X_df))
  a_t  <- unname(coef(med_fit)["d"])
  a_0  <- unname(coef(med_fit)["(Intercept)"])
  a_X  <- coef(med_fit)[setdiff(names(coef(med_fit)), c("(Intercept)", "d"))]

  out_fit <- lm(y ~ d * m + ., data = cbind(y = y, d = d, m = m, X_df))
  cof <- coef(out_fit)
  c1  <- unname(cof["d"])
  d_m <- unname(cof["m"])
  e_t <- unname(cof["d:m"])

  X_bar <- colMeans(X_df)
  m_d1 <- a_0 + a_t * 1 + sum(a_X * X_bar)
  m_d0 <- a_0 + a_t * 0 + sum(a_X * X_bar)
  nde_d1 <- c1 + e_t * m_d1   # FIXED: zeta(1), mediator at its treated level
  nde_d0 <- c1 + e_t * m_d0   #        zeta(0), mediator at its control level
  nie_d1 <- a_t * (d_m + e_t * 1)
  nie_d0 <- a_t * (d_m + e_t * 0)

  # tau = zeta(0)+delta(1) = zeta(1)+delta(0); the average equals either one.
  ate <- 0.5 * (nde_d1 + nde_d0) + 0.5 * (nie_d1 + nie_d0)
  stopifnot(abs(ate - (nde_d0 + nie_d1)) < 1e-8)   # NEW guardrail

  c(ATE         = unname(ate),
    "NDE(d=1)"  = unname(nde_d1),
    "NDE(d=0)"  = unname(nde_d0),
    "ACME(d=1)" = unname(nie_d1),
    "ACME(d=0)" = unname(nie_d0))
}

est <- tryCatch(
  estimate_lsem_i(sim$y, sim$d, sim$m, sim$X),
  error = function(e) {
    cat("[run_lsem_i] FAILED:", conditionMessage(e), "\n")
    c(ATE = NA, "NDE(d=1)" = NA, "NDE(d=0)" = NA, "ACME(d=1)" = NA, "ACME(d=0)" = NA)
  }
)

write_result(PERF_DIR, idx$name, idx$rep, "lsem_i_proxyX", idx, est, truth)

cat(sprintf("[run_lsem_i] done.  ATE=%+.3f  (truth=%+.3f)\n",
            est["ATE"], truth$ATE))
