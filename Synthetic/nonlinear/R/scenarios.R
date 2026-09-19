# =============================================================================
# scenarios.R — Single source of truth for the 8 scenarios.
# Sourced by every R and Python script via the same indexing.
# =============================================================================
#
# Scenario grid:
#   N        ∈ {1000, 4000}
#   n_X      ∈ {10, 200}
#   sigma_x  ∈ {0.7, 2}        # SD of the proxy noise eps_ij ~ N(0, sigma_x^2)
# => 2 * 2 * 2 = 8 scenarios
#
# (sigma_m = sigma_y = 1 are fixed and not part of the grid.)
#
# Reps per scenario: 100
# Total array tasks per method: 8 * 100 = 800
#
# Mapping from SLURM array task id (1..800) to (scenario, rep):
#   scenario_id = ((task_id - 1) %/% 100) + 1   # 1..8
#   rep         = ((task_id - 1) %%  100) + 1   # 1..100
#
# Scenario directory names: N<N>_nX<n_X>_sx<sigma_x>, e.g.
#   N1000_nX10_sx0.7   N4000_nX200_sx2
# =============================================================================

SCENARIOS <- expand.grid(
  N        = c(1000, 4000),
  n_X      = c(10, 200),
  sigma_x  = c(0.7, 2),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
SCENARIOS$scenario_id <- seq_len(nrow(SCENARIOS))
# %g (not %d) so that non-integer sigma_x values such as 0.7 format correctly
SCENARIOS$name <- with(SCENARIOS,
                      sprintf("N%d_nX%d_sx%g", N, n_X, sigma_x))

# Fixed noise levels for the mediator and outcome equations (SDs)
SIGMA_M <- 1
SIGMA_Y <- 1

N_REPS_PER_SCENARIO <- 100L

task_id_to_indices <- function(task_id) {
  stopifnot(task_id >= 1, task_id <= nrow(SCENARIOS) * N_REPS_PER_SCENARIO)
  scenario_id <- ((task_id - 1L) %/% N_REPS_PER_SCENARIO) + 1L
  rep         <- ((task_id - 1L) %%  N_REPS_PER_SCENARIO) + 1L
  list(
    task_id     = task_id,
    scenario_id = scenario_id,
    rep         = rep,
    N           = SCENARIOS$N[scenario_id],
    n_X         = SCENARIOS$n_X[scenario_id],
    sigma_x     = SCENARIOS$sigma_x[scenario_id],
    name        = SCENARIOS$name[scenario_id]
  )
}

# Deterministic seed for each (scenario, rep) combo so EVERY method uses the
# same dataset for the same (scenario, rep).
make_seed <- function(scenario_id, rep) {
  as.integer(1000L * scenario_id + rep)
}
