# =============================================================================
# calibrate_alpha_latent.R — Run ONCE before the latent JOBS II pipeline.
# Mirrors generate_jobs2_latent.R: depress1 promoted to Z, both T and M get
# an extra w_z * Z_std term (w_z ~ N(5, 0.1)).
# Writes R/alpha_lookup.rds.
# =============================================================================

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") PROJECT_ROOT <- getwd()

# ---- Load and prep JOBS II ------------------------------------------------
jobs <- readRDS(file.path(PROJECT_ROOT, "R", "jobs_data.rds"))
df <- jobs

Z_full <- df$depress1
Z_std  <- as.numeric(scale(Z_full))

X_full <- df[, c("econ_hard", "sex", "age")]
X_full$nonwhite_bin <- as.integer(df$nonwhite == "non.white1")
X_full <- as.matrix(X_full[, c("econ_hard", "sex", "age", "nonwhite_bin")])

T_orig <- df$treat
M_cont <- df$job_seek
M_bin  <- as.integer(M_cont >= 3)
Y_orig <- df$depress2

# ---- Probit fits on full data WITH Z as a regressor -----------------------
fit_T <- glm(T_orig ~ X_full + Z_std,
             family = binomial(link = "probit"))
beta_pop <- coef(fit_T)[c("(Intercept)", paste0("X_full", colnames(X_full)))]

fit_M <- glm(M_bin ~ T_orig + X_full + Z_std,
             family = binomial(link = "probit"))
mu_pop    <- coef(fit_M)
gamma_pop <- unname(mu_pop["T_orig"])
omega_pop <- mu_pop[paste0("X_full", colnames(X_full))]

# ---- Filter to non-treated, non-mediated pool -----------------------------
keep   <- T_orig == 0 & M_bin == 0
X_pool <- X_full[keep, , drop = FALSE]
Z_pool <- Z_std[keep]
cat(sprintf("JOBS II: %d total obs; %d non-treated & non-mediated.\n",
            nrow(df), nrow(X_pool)))

# ---- Simulation: latent DGP -----------------------------------------------
simulate_share <- function(alpha, n, eta, n_replications = 50) {
  shares <- numeric(n_replications)
  for (r in seq_len(n_replications)) {
    set.seed(10000 + r)
    samp_idx <- sample(seq_len(nrow(X_pool)), size = n, replace = TRUE)
    X_b <- X_pool[samp_idx, , drop = FALSE]
    Z_b <- Z_pool[samp_idx]
    w_z <- rnorm(1, mean = 5, sd = 0.1)

    linpred_T <- cbind(1, X_b) %*% beta_pop + w_z * Z_b
    T_new     <- as.integer(linpred_T + rnorm(n) > 0)

    linpred_M_raw <- T_new * gamma_pop + X_b %*% omega_pop + w_z * Z_b
    M_new         <- eta * linpred_M_raw + alpha + rnorm(n)

    shares[r] <- mean(M_new >= 3)
  }
  mean(shares)
}

# ---- Calibration via uniroot ----------------------------------------------
calibrate_one <- function(n, eta, target_share) {
  f <- function(a) simulate_share(a, n, eta) - target_share

  lo <- -200; hi <- 200
  grid <- seq(lo, hi, length.out = 81)
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

# ---- Run calibration for all 8 scenarios ---------------------------------
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
  if (is.na(alpha)) {
    cat("  -> NA (no sign change)\n")
    key <- sprintf("n%d_eta%d_share%d", n, eta, share * 100)
    ALPHA_LOOKUP[[key]] <- NA_real_
    next
  }
  achieved <- simulate_share(alpha, n, eta, n_replications = 100)
  cat(sprintf("  alpha = %+.4f   achieved share = %.3f (target %.2f)\n",
              alpha, achieved, share))
  key <- sprintf("n%d_eta%d_share%d", n, eta, share * 100)
  ALPHA_LOOKUP[[key]] <- alpha
}

# ---- Save ----------------------------------------------------------------
out_path <- file.path(PROJECT_ROOT, "R", "alpha_lookup.rds")

if (file.exists(out_path)) {
  bak <- sub("\\.rds$", "_nolatent_backup.rds", out_path)
  file.copy(out_path, bak, overwrite = TRUE)
  cat(sprintf("\nBacked up existing lookup to %s\n", bak))
}

saveRDS(ALPHA_LOOKUP, out_path)
cat(sprintf("\nWrote %s\n", out_path))
print(ALPHA_LOOKUP)
