# =============================================================================
# Shared DGP — NONLINEAR-IN-Z case (pairwise Z interactions in X, M and Y)
# =============================================================================
# Structural equations (i = unit, j = proxy index):
#
#   z1, z2, z3 ~ Bernoulli(0.5), independent
#
#   X_ij = z1 + z2 + z3 + gamma_x * z1*z2 + eps_ij,   eps_ij ~ N(0, sigma_x^2)
#   T_i  ~ Bernoulli( plogis(-1 + z1 + z2) )
#   M_i  = 0.25*(z2 + z3) + 0.5*T_i*f(Z_i) + gamma_m * z2*z3 + em_i
#   Y_i  = (z1 + z3) + T_i + M_i + 0.5*T_i*M_i + gamma_y * z1*z3 + ey_i
#
#   f(Z_i) = plogis(1 + 0.2*(z2 + z3))
#   em_i ~ N(0, sigma_m^2),  ey_i ~ N(0, sigma_y^2)
#
# Defaults: gamma_x = 0.5, gamma_m = 0.3, gamma_y = 0.5, sigma_m = sigma_y = 1.
# sigma_x is a STANDARD DEVIATION and takes the values {0.7, 2} in the
# scenario grid (see scenarios.R).
#
# Note: M and Y depend on Z only (no direct X terms any more). X is a noisy,
# nonlinear proxy for Z.
# =============================================================================

# ---- Structural equations ---------------------------------------------------
f_Z <- function(z2, z3) {
  plogis(1 + 0.2 * (z2 + z3))
}

m_structural <- function(t_val, z1, z2, z3, em, gamma_m = 0.3) {
  0.25 * (z2 + z3) + 0.5 * t_val * f_Z(z2, z3) + gamma_m * z2 * z3 + em
}

y_structural <- function(t_val, m_val, z1, z2, z3, ey, gamma_y = 0.5) {
  (z1 + z3) + t_val + m_val + 0.5 * t_val * m_val + gamma_y * z1 * z3 + ey
}


# ---- DGP --------------------------------------------------------------------
simulate_mediation_system <- function(N, n_X = 10,
                                      sigma_x = 0.7,   # SD of eps_ij
                                      sigma_m = 1,     # SD of em_i
                                      sigma_y = 1,     # SD of ey_i
                                      gamma_x = 0.5,   # coef on z1*z2 in X
                                      gamma_m = 0.3,   # coef on z2*z3 in M
                                      gamma_y = 0.5) { # coef on z1*z3 in Y

  z1 <- rbinom(N, 1, 0.5)
  z2 <- rbinom(N, 1, 0.5)
  z3 <- rbinom(N, 1, 0.5)

  # Common (nonlinear) signal shared by all proxies
  x_signal <- z1 + z2 + z3 + gamma_x * z1 * z2

  X <- matrix(NA_real_, N, n_X)
  for (j in seq_len(n_X)) X[, j] <- x_signal + rnorm(N, 0, sigma_x)
  colnames(X) <- paste0("X", seq_len(n_X))

  p_t <- plogis(-1 + z1 + z2)
  t   <- rbinom(N, 1, p_t)

  em <- rnorm(N, 0, sigma_m)
  ey <- rnorm(N, 0, sigma_y)

  m <- m_structural(t, z1, z2, z3, em, gamma_m)
  y <- y_structural(t, m, z1, z2, z3, ey, gamma_y)

  # Potential mediators / outcomes (same em, ey draws)
  m0 <- m_structural(0, z1, z2, z3, em, gamma_m)
  m1 <- m_structural(1, z1, z2, z3, em, gamma_m)

  y_00 <- y_structural(0, m0, z1, z2, z3, ey, gamma_y)
  y_01 <- y_structural(0, m1, z1, z2, z3, ey, gamma_y)
  y_10 <- y_structural(1, m0, z1, z2, z3, ey, gamma_y)
  y_11 <- y_structural(1, m1, z1, z2, z3, ey, gamma_y)

  list(
    y = y, d = t, m = m,
    X = as.data.frame(X),
    Z = data.frame(z1 = z1, z2 = z2, z3 = z3),
    y11 = mean(y_11), y10 = mean(y_10),
    y01 = mean(y_01), y00 = mean(y_00)
  )
}


# ---- Shared Monte Carlo driver ----------------------------------------------
run_mc <- function(estimator_fn, n, simulations, adjust,
                   n_X = 10, sigma_x = 0.7, sigma_m = 1, sigma_y = 1,
                   verbose_every = 20) {

  est      <- matrix(NA, simulations, 5)
  true.eff <- matrix(NA, simulations, 5)

  for (ii in 1:simulations) {
    set.seed(ii)
    if (ii %% verbose_every == 0) cat("  rep", ii, "/", simulations, "\n")

    sim <- simulate_mediation_system(N = n, n_X = n_X,
                                     sigma_x = sigma_x,
                                     sigma_m = sigma_m,
                                     sigma_y = sigma_y)

    true.eff[ii, ] <- c(sim$y11 - sim$y00,
                        sim$y11 - sim$y01,
                        sim$y10 - sim$y00,
                        sim$y11 - sim$y10,
                        sim$y01 - sim$y00)

    est[ii, ] <- estimator_fn(sim, adjust)
  }

  truth  <- colMeans(true.eff)
  means  <- colMeans(est)
  bias   <- means - truth
  sd_emp <- apply(est, 2, sd)
  rmse   <- sqrt(sd_emp^2 + bias^2)

  out <- rbind(true = truth, mean = means, bias = bias,
               sd = sd_emp, rmse = rmse)
  colnames(out) <- c("ATE", "NDE(d=1)", "NDE(d=0)",
                     "ACME(d=1)", "ACME(d=0)")
  out
}
