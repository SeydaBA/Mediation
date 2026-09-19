# =============================================================================
# calibrate_alpha.R — Run ONCE before the main pipeline.
#
# Cheng et al. (2022) say they "set alpha such that either 10% or 50% of the
# observations are mediated (I(M_i) = 1)" but don't publish the actual values.
# This script numerically searches for alpha per (n, eta) combination so that
# the SIMULATED mediator hits the target share, then writes
# R/alpha_lookup.rds for scenarios.R to read.
#
# Usage:
#   cd $PROJECT_ROOT
#   Rscript R/calibrate_alpha.R
# =============================================================================

# jobs dataset loaded from RDS below
PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") PROJECT_ROOT <- getwd()

# ---- Load and prep JOBS II ------------------------------------------------
jobs <- readRDS(file.path(PROJECT_ROOT, "R", "jobs_data.rds"))
df <- jobs

X_full <- df[, c("econ_hard", "sex", "age", "depress1")]
X_full$nonwhite_bin <- as.integer(df$nonwhite == "non.white1")
X_full <- X_full[, c("econ_hard", "sex", "age", "depress1", "nonwhite_bin")]
# Numeric coercion for categorical columns
X_full <- as.matrix(X_full)

T_orig <- df$treat
M_cont <- df$job_seek
M_bin  <- as.integer((M_cont - mean(M_cont)) / sd(M_cont) >= 0)  # normalized threshold (Cheng et al. normalized continuous covariates)
Y_orig <- df$depress2

# Probit fits on full data
fit_T <- glm(Tt ~ ., data = cbind(Tt = T_orig, as.data.frame(X_full)), family = binomial(link = "probit"), control = list(maxit = 1000))
beta_pop <- coef(fit_T)

fit_M <- glm(M ~ ., data = cbind(M = M_bin, Tt = T_orig, as.data.frame(X_full)), family = binomial(link = "probit"), control = list(maxit = 1000))
mu_pop      <- coef(fit_M)
gamma_pop   <- unname(mu_pop["Tt"])
omega_pop   <- mu_pop[!names(mu_pop) %in% c("(Intercept)", "Tt")]

# Non-treated, non-mediated pool
keep   <- T_orig == 0 & M_bin == 0
X_pool <- X_full[keep, , drop = FALSE]
cat(sprintf("JOBS II: %d total obs; %d non-treated & non-mediated.\n",
            nrow(df), nrow(X_pool)))

# ---- Calibration function -------------------------------------------------
# For a fixed (n, eta), find alpha so that ~target_share of simulated M_i pass
# the I(M >= 3) threshold. Uses uniroot with a reasonable bracket.

simulate_share <- function(alpha, n, eta, n_replications = 50) {
  shares <- numeric(n_replications)
  for (r in seq_len(n_replications)) {
    set.seed(10000 + r)
    samp_idx <- sample(seq_len(nrow(X_pool)), size = n, replace = TRUE)
    X_b <- X_pool[samp_idx, , drop = FALSE]
    linpred_T <- cbind(1, X_b) %*% beta_pop
    T_new <- as.integer(linpred_T + rnorm(n) > 0)
    linpred_M_raw <- T_new * gamma_pop + X_b %*% omega_pop
    M_new <- eta * linpred_M_raw + alpha + rnorm(n)
    shares[r] <- mean(M_new >= 3)
  }
  mean(shares)
}

calibrate_one <- function(n, eta, target_share) {
  # Search bracket: alpha large negative -> ~0 share; large positive -> ~1
  f <- function(a) simulate_share(a, n, eta) - target_share
  # Bracket depends heavily on eta. For eta=10 the linpred is large, so
  # alpha needs to be larger in magnitude.
  lo <- -50; hi <- 50
  # Quick scan to find a sign change
  grid <- seq(lo, hi, length.out = 41)
  vals <- sapply(grid, f)
  sign_change <- which(diff(sign(vals)) != 0)
  if (length(sign_change) == 0) {
    warning(sprintf("No sign change found for n=%d eta=%g share=%g",
                    n, eta, target_share))
    return(NA_real_)
  }
  bracket_idx <- sign_change[1]
  result <- uniroot(f,
                    lower = grid[bracket_idx],
                    upper = grid[bracket_idx + 1],
                    tol = 1e-3)
  result$root
}

# ---- Run calibration for all 8 scenarios ----------------------------------
ALPHA_LOOKUP <- list()
targets <- expand.grid(
  n     = c(500, 1000),
  eta   = c(1, 10),
  share = c(0.10, 0.50),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(targets))) {
  n     <- targets$n[i]
  eta   <- targets$eta[i]
  share <- targets$share[i]
  cat(sprintf("Calibrating n=%d eta=%g share=%g ...\n", n, eta, share))
  alpha <- calibrate_one(n, eta, share)
  achieved <- simulate_share(alpha, n, eta, n_replications = 100)
  cat(sprintf("  alpha = %+.4f   achieved share = %.3f (target %.2f)\n",
              alpha, achieved, share))
  key <- sprintf("n%d_eta%d_share%d", n, eta, share * 100)
  ALPHA_LOOKUP[[key]] <- alpha
}

# ---- Save ----------------------------------------------------------------
out_path <- file.path(PROJECT_ROOT, "R", "alpha_lookup.rds")
saveRDS(ALPHA_LOOKUP, out_path)
cat(sprintf("\nWrote %s\n", out_path))
print(ALPHA_LOOKUP)
