# =============================================================================
# Shared DGP — LINEAR case (no X-nonlinearity in M or Y)
# =============================================================================
# This is the ORIGINAL DGP from the start of the conversation.
# No 0.3*sin(2*X1) in M, no 0.5*X1^2 in Y.
#
# True effects (analytical):
#   ATE       ≈ 1.701
#   NDE(d=1)  ≈ 1.317
#   NDE(d=0)  ≈ 1.125
#   ACME(d=1) ≈ 0.576
#   ACME(d=0) ≈ 0.384
# =============================================================================

# ---- Structural equations: LINEAR (no X-nonlinearity) -----------------------
m_structural <- function(t_val, z1, z2, z3, X, em) {
  f_z <- plogis(1 + 0.2 * (z2 + z3))
  0.25 * (z2 + z3) + 0.5 * t_val * f_z + em
}

y_structural <- function(t_val, m_val, z1, z2, z3, X, ey) {
  (z1 + z3) + t_val + m_val + 0.5 * t_val * m_val + ey
}


# ---- DGP --------------------------------------------------------------------
simulate_mediation_system <- function(N, n_X = 10, sigma2_x = 1,
                                      sigma2_m = 1, sigma2_y = 1) {

  z1 <- rbinom(N, 1, 0.5)
  z2 <- rbinom(N, 1, 0.5)
  z3 <- rbinom(N, 1, 0.5)
  z_sum <- z1 + z2 + z3

  X <- matrix(NA, N, n_X)
  for (j in 1:n_X) X[, j] <- z_sum + rnorm(N, 0, sqrt(sigma2_x))
  colnames(X) <- paste0("X", 1:n_X)

  p_t <- plogis(-1 + z1 + z2)
  t   <- rbinom(N, 1, p_t)

  em <- rnorm(N, 0, sqrt(sigma2_m))
  ey <- rnorm(N, 0, sqrt(sigma2_y))

  m <- m_structural(t, z1, z2, z3, X, em)
  y <- y_structural(t, m, z1, z2, z3, X, ey)

  m0 <- m_structural(0, z1, z2, z3, X, em)
  m1 <- m_structural(1, z1, z2, z3, X, em)

  y_00 <- y_structural(0, m0, z1, z2, z3, X, ey)
  y_01 <- y_structural(0, m1, z1, z2, z3, X, ey)
  y_10 <- y_structural(1, m0, z1, z2, z3, X, ey)
  y_11 <- y_structural(1, m1, z1, z2, z3, X, ey)

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
                   n_X = 10, sigma2_x = 1, verbose_every = 20) {

  est      <- matrix(NA, simulations, 5)
  true.eff <- matrix(NA, simulations, 5)

  for (ii in 1:simulations) {
    set.seed(ii)
    if (ii %% verbose_every == 0) cat("  rep", ii, "/", simulations, "\n")

    sim <- simulate_mediation_system(N = n, n_X = n_X, sigma2_x = sigma2_x)

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
