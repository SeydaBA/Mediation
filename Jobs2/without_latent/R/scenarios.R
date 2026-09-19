# =============================================================================
# scenarios.R — JOBS II semi-synthetic, 8 scenarios per Cheng et al. (2022).
# =============================================================================
#
# Scenario grid (from §5.2 of Cheng et al.):
#   n          ∈ {500, 1000}      (sample size to bootstrap)
#   eta        ∈ {1, 10}          (selection-into-mediator strength)
#   alpha_share ∈ {0.10, 0.50}    (target share of "mediated" observations)
# => 2 * 2 * 2 = 8 scenarios, 100 reps each = 800 array tasks per method.
#
# alpha is chosen numerically to hit the target share for each (n, eta).
# The lookup below is filled in by R/calibrate_alpha.R (run once before the
# main pipeline). Default placeholders are reasonable starting guesses; the
# calibrator will overwrite them.
# =============================================================================

SCENARIOS <- expand.grid(
  n           = c(500, 1000),
  eta         = c(1, 10),
  alpha_share = c(0.10, 0.50),
  KEEP.OUT.ATTRS   = FALSE,
  stringsAsFactors = FALSE
)

# These alpha values are PLACEHOLDERS. Run calibrate_alpha.R first to replace
# them with calibrated values. The calibration step writes
# R/alpha_lookup.rds; this file loads it if present.
.alpha_lookup_path <- file.path(
  Sys.getenv("PROJECT_ROOT", unset = "."),
  "R", "alpha_lookup.rds"
)
if (file.exists(.alpha_lookup_path)) {
  ALPHA_LOOKUP <- readRDS(.alpha_lookup_path)
} else {
  # Placeholders (used until calibration runs)
  ALPHA_LOOKUP <- list(
    "n500_eta1_share10"   = -2.3,
    "n500_eta1_share50"   = -0.05,
    "n500_eta10_share10"  = -23.0,
    "n500_eta10_share50"  = -0.5,
    "n1000_eta1_share10"  = -2.3,
    "n1000_eta1_share50"  = -0.05,
    "n1000_eta10_share10" = -23.0,
    "n1000_eta10_share50" = -0.5
  )
}

SCENARIOS$alpha <- mapply(function(n, eta, share) {
  key <- sprintf("n%d_eta%d_share%d", n, eta, share * 100)
  if (!is.null(ALPHA_LOOKUP[[key]])) ALPHA_LOOKUP[[key]] else NA_real_
}, SCENARIOS$n, SCENARIOS$eta, SCENARIOS$alpha_share)

SCENARIOS$scenario_id <- seq_len(nrow(SCENARIOS))
SCENARIOS$name <- with(SCENARIOS,
                      sprintf("n%d_eta%d_share%d",
                              n, eta, alpha_share * 100))

N_REPS_PER_SCENARIO <- 100L   # Cheng et al. used 10; 100 gives tighter CIs

task_id_to_indices <- function(task_id) {
  stopifnot(task_id >= 1,
            task_id <= nrow(SCENARIOS) * N_REPS_PER_SCENARIO)
  scenario_id <- ((task_id - 1L) %/% N_REPS_PER_SCENARIO) + 1L
  rep         <- ((task_id - 1L) %%  N_REPS_PER_SCENARIO) + 1L
  list(
    task_id     = task_id,
    scenario_id = scenario_id,
    rep         = rep,
    n           = SCENARIOS$n[scenario_id],
    eta         = SCENARIOS$eta[scenario_id],
    alpha_share = SCENARIOS$alpha_share[scenario_id],
    alpha       = SCENARIOS$alpha[scenario_id],
    name        = SCENARIOS$name[scenario_id]
  )
}

make_seed <- function(scenario_id, rep) {
  as.integer(1000L * scenario_id + rep)
}
