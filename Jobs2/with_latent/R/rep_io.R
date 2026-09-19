# =============================================================================
# rep_io.R — Read replication files from input/<scenario>/ for JOBS II.
# No Z column (no oracle for semi-synthetic real data).
# =============================================================================

read_rep <- function(input_root, scenario_name, rep) {
  rep_tag <- sprintf("rep%03d", rep)
  rep_dir <- file.path(input_root, scenario_name)

  list(
    X     = as.matrix(read.csv(file.path(rep_dir, paste0(rep_tag, "_x.csv")))),
    m     = read.csv(file.path(rep_dir, paste0(rep_tag, "_m.csv")))$m,
    t     = read.csv(file.path(rep_dir, paste0(rep_tag, "_t.csv")))$t,
    y     = read.csv(file.path(rep_dir, paste0(rep_tag, "_y.csv")))$y,
    truth = read.csv(file.path(rep_dir, paste0(rep_tag, "_truth.csv")))
  )
}

build_sim <- function(rep_data) {
  list(
    X = rep_data$X,
    m = rep_data$m,
    d = rep_data$t,
    y = rep_data$y
  )
}

extract_truth <- function(rep_data) {
  tr <- rep_data$truth
  list(
    ATE    = tr$ATE,
    NDE_d1 = tr$NDE_d1,
    NDE_d0 = tr$NDE_d0,
    NIE_d1 = tr$NIE_d1,
    NIE_d0 = tr$NIE_d0
  )
}

write_result <- function(perf_root, scenario_name, rep, method, idx, est, truth, extra = NULL) {
  out_dir <- file.path(perf_root, scenario_name)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  rep_tag <- sprintf("rep%03d", rep)

  row <- data.frame(
    method      = method,
    scenario_id = idx$scenario_id,
    scenario    = idx$name,
    rep         = idx$rep,
    n           = idx$n,
    eta         = idx$eta,
    alpha_share = idx$alpha_share,
    ATE_est     = est["ATE"],
    NDE_d1_est  = est[["NDE(d=1)"]],
    NDE_d0_est  = est[["NDE(d=0)"]],
    NIE_d1_est  = est[["ACME(d=1)"]],
    NIE_d0_est  = est[["ACME(d=0)"]],
    ATE_true    = truth$ATE,
    NDE_d1_true = truth$NDE_d1,
    NDE_d0_true = truth$NDE_d0,
    NIE_d1_true = truth$NIE_d1,
    NIE_d0_true = truth$NIE_d0,
    ATE_bias    = est["ATE"] - truth$ATE,
    NDE_d1_bias = est[["NDE(d=1)"]] - truth$NDE_d1,
    NDE_d0_bias = est[["NDE(d=0)"]] - truth$NDE_d0,
    NIE_d1_bias = est[["ACME(d=1)"]] - truth$NIE_d1,
    NIE_d0_bias = est[["ACME(d=0)"]] - truth$NIE_d0,
    stringsAsFactors = FALSE
  )
  if (!is.null(extra)) row <- cbind(row, extra)

  write.csv(row, file = file.path(out_dir, paste0(rep_tag, ".csv")),
            row.names = FALSE)
}
