# =============================================================================
# run_dml.R — DML mediation analysis (Farbmacher et al. 2022, medDML).
# Proxy X only. Uses order=2 polynomial expansion via patched LARF::Generate.Powers
# (the original has integer overflow for large p).
#
# JOBS II has 8 covariates, so order=2 -> 8 + 8 + 28 = 44 features. No overflow risk,
# but we still source patch_LARF.R for consistency with the synthetic pipelines.
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Usage: Rscript run_dml.R <task_id>")
task_id <- as.integer(args[1])

suppressPackageStartupMessages({
  library(causalweight)
})

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
INPUT_DIR <- file.path(PROJECT_ROOT, "input")
PERF_DIR  <- file.path(PROJECT_ROOT, "performance_dml")

source(file.path(PROJECT_ROOT, "R", "scenarios.R"))
source(file.path(PROJECT_ROOT, "R", "rep_io.R"))
# Apply LARF patch (no-op for small n_X but harmless)
if (file.exists(file.path(PROJECT_ROOT, "R", "patch_LARF.R"))) {
  source(file.path(PROJECT_ROOT, "R", "patch_LARF.R"))
}

idx      <- task_id_to_indices(task_id)

# __SKIP_IF_DONE__: if the output file already exists, skip this task.
out_csv <- file.path(PERF_DIR, idx$name, sprintf("rep%03d.csv", idx$rep))
if (file.exists(out_csv)) {
  cat(sprintf("[run_dml] task=%d  scenario=%s  rep=%d  SKIP (output exists)\n",
              task_id, idx$name, idx$rep))
  quit(save = "no", status = 0)
}
rep_data <- read_rep(INPUT_DIR, idx$name, idx$rep)
sim      <- build_sim(rep_data)
truth    <- extract_truth(rep_data)

cat(sprintf("[run_dml] task=%d  scenario=%s  rep=%d\n",
            task_id, idx$name, idx$rep))

ORDER <- 2L    # polynomial expansion order

estimate_dml <- function(y, d, m, X) {
  fit <- medDML(y = y, d = d, m = m, x = as.matrix(X),
                k = 4, trim = 0.05,
                order = ORDER, multmed = TRUE, fewsplits = FALSE)
  setNames(as.numeric(fit$results[1, 1:5]),
           c("ATE", "NDE(d=1)", "NDE(d=0)", "ACME(d=1)", "ACME(d=0)"))
}

est <- tryCatch(
  estimate_dml(sim$y, sim$d, sim$m, sim$X),
  error = function(e) {
    cat("[run_dml] FAILED:", conditionMessage(e), "\n")
    c(ATE = NA, "NDE(d=1)" = NA, "NDE(d=0)" = NA, "ACME(d=1)" = NA, "ACME(d=0)" = NA)
  }
)

write_result(PERF_DIR, idx$name, idx$rep, "dml_proxyX", idx, est, truth)

cat(sprintf("[run_dml] done.  ATE=%+.3f  (truth=%+.3f)\n",
            est["ATE"], truth$ATE))
