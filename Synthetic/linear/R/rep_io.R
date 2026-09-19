# =============================================================================
# rep_io.R — Helpers used by run_lsem.R, run_lsem_i.R, run_dml.R
# =============================================================================

read_rep <- function(input_dir, scenario_name, rep) {
  d <- file.path(input_dir, scenario_name)
  tag <- sprintf("rep%03d", rep)
  list(
    X     = read.csv(file.path(d, paste0(tag, "_x.csv"))),
    m     = read.csv(file.path(d, paste0(tag, "_m.csv")))$m,
    d     = read.csv(file.path(d, paste0(tag, "_t.csv")))$t,
    y     = read.csv(file.path(d, paste0(tag, "_y.csv")))$y,
    Z     = read.csv(file.path(d, paste0(tag, "_z.csv"))),
    truth = read.csv(file.path(d, paste0(tag, "_truth.csv")))
  )
}

# Build a "sim"-shaped object compatible with the original estimators.
build_sim <- function(rep_data) {
  list(
    y = rep_data$y,
    d = rep_data$d,
    m = rep_data$m,
    X = rep_data$X,
    Z = rep_data$Z
  )
}

write_result_row <- function(perf_dir, method, idx, est, truth_df) {
  # est: named numeric vector with c(ATE, NDE(d=1), NDE(d=0), ACME(d=1), ACME(d=0))
  scen_dir <- file.path(perf_dir, idx$name)
  dir.create(scen_dir, recursive = TRUE, showWarnings = FALSE)

  row <- data.frame(
    method      = method,
    scenario_id = idx$scenario_id,
    scenario    = idx$name,
    rep         = idx$rep,
    N           = idx$N,
    n_X         = idx$n_X,
    sigma2_x    = idx$sigma2_x,
    # estimates
    ATE_est       = unname(est["ATE"]),
    NDE_d1_est    = unname(est["NDE(d=1)"]),
    NDE_d0_est    = unname(est["NDE(d=0)"]),
    NIE_d1_est    = unname(est["ACME(d=1)"]),
    NIE_d0_est    = unname(est["ACME(d=0)"]),
    # truths
    ATE_true      = truth_df$ATE,
    NDE_d1_true   = truth_df$NDE_d1,
    NDE_d0_true   = truth_df$NDE_d0,
    NIE_d1_true   = truth_df$NIE_d1,
    NIE_d0_true   = truth_df$NIE_d0,
    # biases
    ATE_bias      = unname(est["ATE"])       - truth_df$ATE,
    NDE_d1_bias   = unname(est["NDE(d=1)"])  - truth_df$NDE_d1,
    NDE_d0_bias   = unname(est["NDE(d=0)"])  - truth_df$NDE_d0,
    NIE_d1_bias   = unname(est["ACME(d=1)"]) - truth_df$NIE_d1,
    NIE_d0_bias   = unname(est["ACME(d=0)"]) - truth_df$NIE_d0
  )

  fname <- sprintf("rep%03d.csv", idx$rep)
  write.csv(row, file = file.path(scen_dir, fname), row.names = FALSE)
}
