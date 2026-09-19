# =============================================================================
# scenarios_latent.R — JOBS II semi-synthetic with a latent confounder.
#
# Extends the original 8-scenario grid (n, eta, alpha_share) with a noise
# level p_c on the binary proxies of Z (= depress1).
#
# Scenario grid:
#   n           ∈ {500, 1000}
#   eta         ∈ {1, 10}
#   alpha_share ∈ {0.10, 0.50}
#   p_c         ∈ {0.1, 0.2, 0.3, 0.4, 0.5}
# => 2 * 2 * 2 * 5 = 40 scenarios, 100 reps each = 4000 array tasks per method.
#
# If you want to keep array sizes manageable, start with a reduced grid
# (e.g. fix n=500, eta=1, alpha_share=0.5 and only vary p_c — see below).
# =============================================================================

# -- Full grid (4000 tasks per method)
SCENARIOS <- expand.grid(
  n           = c(500, 1000),
  eta         = c(1, 10),
  alpha_share = c(0.10, 0.50),
  p_c         = c(0.1, 0.2, 0.3, 0.4, 0.5),
  KEEP.OUT.ATTRS   = FALSE,
  stringsAsFactors = FALSE
)

# -- Optional: reduced grid for a first pass (uncomment to use; 500 tasks/method)
# SCENARIOS <- expand.grid(
#   n           = c(500),
#   eta         = c(1),
#   alpha_share = c(0.50),
#   p_c         = c(0.1, 0.2, 0.3, 0.4, 0.5),
#   KEEP.OUT.ATTRS   = FALSE,
#   stringsAsFactors = FALSE
# )

# alpha lookup — same as before, indexed only by (n, eta, alpha_share); p_c
# does not affect the mediator's intercept calibration.
.alpha_lookup_path <- file.path(
  Sys.getenv("PROJECT_ROOT", unset = "."),
  "R", "alpha_lookup.rds"
)
if (file.exists(.alpha_lookup_path)) {
  ALPHA_LOOKUP <- readRDS(.alpha_lookup_path)
} else {
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
                      sprintf("n%d_eta%d_share%d_pc%02d",
                              n, eta, alpha_share * 100,
                              as.integer(round(p_c * 100))))

N_REPS_PER_SCENARIO <- 100L

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
    p_c         = SCENARIOS$p_c[scenario_id],
    name        = SCENARIOS$name[scenario_id]
  )
}

make_seed <- function(scenario_id, rep) {
  as.integer(1000L * scenario_id + rep)
}
