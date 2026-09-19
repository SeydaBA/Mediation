# =============================================================================
# run_lsem_i.R — LSEM-I (Imai et al. 2010, with T*M interaction) — ONE rep.
# Usage:
#   Rscript run_lsem_i.R <task_id>
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_lsem_i.R <task_id>")
task_id <- as.integer(args[1])

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR    <- file.path(PROJECT_ROOT, "input")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "rep_io.R"))

idx <- task_id_to_indices(task_id)
cat(sprintf("[run_lsem_i] task=%d  scenario=%s  rep=%d\n",
            idx$task_id, idx$name, idx$rep))

rep_data <- read_rep(INPUT_DIR, idx$name, idx$rep)
sim      <- build_sim(rep_data)

lsem_i_estimator <- function(sim, adjust = c("X", "Z")) {
  adjust    <- match.arg(adjust)
  covars    <- if (adjust == "X") sim$X else sim$Z
  cov_names <- names(covars)

  dat <- data.frame(y = sim$y, d = sim$d, m = sim$m, covars)
  cov_formula <- paste(cov_names, collapse = " + ")

  fit_m <- lm(as.formula(paste("m ~ d +", cov_formula)), data = dat)
  a     <- coef(fit_m)["d"]

  fit_y <- lm(as.formula(paste("y ~ d * m +", cov_formula)), data = dat)
  c_prime <- coef(fit_y)["d"]
  b       <- coef(fit_y)["m"]
  h       <- coef(fit_y)["d:m"]

  dat_t0 <- dat; dat_t0$d <- 0
  dat_t1 <- dat; dat_t1$d <- 1
  EM0 <- mean(predict(fit_m, newdata = dat_t0))
  EM1 <- mean(predict(fit_m, newdata = dat_t1))

  acme1 <- a * (b + h)
  acme0 <- a * b
  nde1  <- c_prime + h * EM1
  nde0  <- c_prime + h * EM0
  ate   <- nde0 + acme1

  c(ATE = unname(ate), "NDE(d=1)" = unname(nde1), "NDE(d=0)" = unname(nde0),
    "ACME(d=1)" = unname(acme1), "ACME(d=0)" = unname(acme0))
}

est_proxy  <- lsem_i_estimator(sim, "X")
write_result_row(
  perf_dir = file.path(PROJECT_ROOT, "performance_lsem_i"),
  method   = "lsem_i_proxyX",
  idx      = idx,
  est      = est_proxy,
  truth_df = rep_data$truth
)

est_oracle <- lsem_i_estimator(sim, "Z")
write_result_row(
  perf_dir = file.path(PROJECT_ROOT, "performance_lsem_i_oracle"),
  method   = "lsem_i_oracleZ",
  idx      = idx,
  est      = est_oracle,
  truth_df = rep_data$truth
)

cat(sprintf("[run_lsem_i] done. proxy ATE=%+.3f  oracle ATE=%+.3f  (truth=%+.3f)\n",
            est_proxy["ATE"], est_oracle["ATE"], rep_data$truth$ATE))
