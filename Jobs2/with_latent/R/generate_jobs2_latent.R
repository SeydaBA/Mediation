# =============================================================================
# generate_jobs2_latent.R — Latent-confounder variant of the JOBS II DGP.
#
# Mirrors Cheng et al. (2022) §5.2 "Varying Proxy Noise" experiment:
#   - Promote depress1 (pre-treatment depression) to the unobserved Z.
#   - Amplify Z's effect on both T and M (Cheng's Eq. 30: w_z ~ N(5, 0.1)).
#   - Replace Z in the observed X with 9 noisy binary proxies (3 bins × 3 reps),
#     each bit flipped independently with probability p_c.
#   - Y is still bootstrapped from the never-treated/never-mediated pool, so
#     ATE = NDE = NIE = 0 by construction. Only the difficulty changes.
#
# Output: writes rep<NNN>_{x,m,t,y,truth}.csv to input/<scenario>/.
# The truth CSV records p_c so downstream summaries can group by it.
#
# Usage: Rscript generate_jobs2_latent.R <task_id>
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Usage: Rscript generate_jobs2_latent.R <task_id>")
task_id <- as.integer(args[1])


PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
source(file.path(PROJECT_ROOT, "R", "scenarios.R"))

idx <- task_id_to_indices(task_id)
set.seed(make_seed(idx$scenario_id, idx$rep))

# -------- Load and prep JOBS II ----------------------------------------------
df <- readRDS(file.path(PROJECT_ROOT, "R", "jobs_data.rds"))

# Z = the latent confounder we will HIDE from estimators
Z_full <- df$depress1

# Observed covariates: same numeric-only set as the no-latent run, MINUS depress1
# (depress1 becomes Z and is hidden from the estimators).
X_full <- df[, c("econ_hard", "sex", "age")]
X_full$nonwhite_bin <- as.integer(df$nonwhite == "non.white1")
X_full <- as.matrix(X_full[, c("econ_hard", "sex", "age", "nonwhite_bin")])

T_orig <- df$treat                 # binary treatment
M_cont <- df$job_seek              # continuous mediator in [1, 5]
M_bin  <- as.integer(M_cont >= 3)  # Cheng's binarization for the filter step
Y_orig <- df$depress2              # outcome

# -------- Step 1: probits on full data (now WITH Z as a regressor) -----------
# Standardize Z for numerical comparability with the X-columns when we
# inject it back with a fixed weight w_z later.
Z_std <- as.numeric(scale(Z_full))

fit_T <- glm(T_orig ~ X_full + Z_std,
             family = binomial(link = "probit"))
beta_pop  <- coef(fit_T)[c("(Intercept)", paste0("X_full", colnames(X_full)))]
beta_z    <- unname(coef(fit_T)["Z_std"])

fit_M <- glm(M_bin ~ T_orig + X_full + Z_std,
             family = binomial(link = "probit"))
mu_pop     <- coef(fit_M)
gamma_pop  <- unname(mu_pop["T_orig"])
omega_pop  <- mu_pop[paste0("X_full", colnames(X_full))]
omega_z    <- unname(mu_pop["Z_std"])

# -------- Step 2: filter to non-treated AND non-mediated pool ----------------
keep    <- T_orig == 0 & M_bin == 0
X_pool  <- X_full[keep, , drop = FALSE]
Z_pool  <- Z_std[keep]
Y_pool  <- Y_orig[keep]

# -------- Step 3: bootstrap n observations from the pool ---------------------
n <- idx$n
samp_idx <- sample(seq_len(nrow(X_pool)), size = n, replace = TRUE)
X_b      <- X_pool[samp_idx, , drop = FALSE]
Z_b      <- Z_pool[samp_idx]
Y_b      <- Y_pool[samp_idx]

# -------- Step 4: simulate pseudo-T with amplified Z effect ------------------
# Cheng et al. Eq. (30): w_z ~ N(5, 0.1). Drawn once per replication so the
# Z-effect is fixed within a sample but varies across reps.
w_z <- rnorm(1, mean = 5, sd = 0.1)

linpred_T <- cbind(1, X_b) %*% beta_pop + w_z * Z_b
T_new     <- as.integer(linpred_T + rnorm(n) > 0)

# -------- Step 5: simulate pseudo-M with amplified Z effect ------------------
eta   <- idx$eta
alpha <- idx$alpha
linpred_M_raw <- T_new * gamma_pop + X_b %*% omega_pop + w_z * Z_b
M_new         <- eta * linpred_M_raw + alpha + rnorm(n)

# -------- Step 6: build noisy proxies of Z (3 bins x 3 replicates, flipped) --
# Three equal-frequency bins on Z_b -> 3 one-hot columns; replicate 3 times;
# flip each of the resulting 9 bits independently with probability p_c.
p_c <- idx$p_c

# tertile cutpoints from Z_b itself (per-rep)
qs       <- quantile(Z_b, probs = c(1/3, 2/3))
Z_bin    <- findInterval(Z_b, qs) + 1L           # values in {1, 2, 3}
onehot   <- model.matrix(~ factor(Z_bin, levels = 1:3) - 1)
colnames(onehot) <- paste0("Zbin", 1:3)

# Replicate 3x to get 9 columns total
proxies  <- cbind(onehot, onehot, onehot)
colnames(proxies) <- paste0("Zproxy_", seq_len(ncol(proxies)))

# Independent Bernoulli(p_c) flips
flips    <- matrix(rbinom(length(proxies), 1, p_c), nrow = nrow(proxies))
proxies  <- (proxies + flips) %% 2   # XOR
storage.mode(proxies) <- "integer"

# Observed X handed to all estimators: original covariates + noisy proxies.
# depress1 itself is NOT included.
X_obs <- cbind(X_b, proxies)

# -------- Step 7: truth is ZERO by construction ------------------------------
truth <- data.frame(
  scenario_id = idx$scenario_id,
  scenario    = idx$name,
  rep         = idx$rep,
  n           = idx$n,
  eta         = idx$eta,
  alpha       = idx$alpha,
  alpha_share = idx$alpha_share,
  p_c         = idx$p_c,
  w_z         = w_z,
  ATE         = 0,
  NDE_d1      = 0,
  NDE_d0      = 0,
  NIE_d1      = 0,
  NIE_d0      = 0
)

# -------- Write output (same schema; X_obs replaces the bare X_b) ------------
out_dir <- file.path(PROJECT_ROOT, "input", idx$name)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
rep_tag <- sprintf("rep%03d", idx$rep)

# __SKIP_IF_DONE__: if all 6 output files already exist, skip this task.
expected_files <- file.path(out_dir, paste0(rep_tag,
  c("_x.csv", "_m.csv", "_t.csv", "_y.csv", "_z.csv", "_truth.csv")))
if (all(file.exists(expected_files))) {
  cat(sprintf("[gen_jobs2_latent] task=%d  scenario=%s  rep=%d  SKIP (all 6 files already exist)\n",
              task_id, idx$name, idx$rep))
  quit(save = "no", status = 0)
}

write.csv(as.data.frame(X_obs),
          file = file.path(out_dir, paste0(rep_tag, "_x.csv")),
          row.names = FALSE)
write.csv(data.frame(m = M_new),
          file = file.path(out_dir, paste0(rep_tag, "_m.csv")),
          row.names = FALSE)
write.csv(data.frame(t = T_new),
          file = file.path(out_dir, paste0(rep_tag, "_t.csv")),
          row.names = FALSE)
write.csv(data.frame(y = Y_b),
          file = file.path(out_dir, paste0(rep_tag, "_y.csv")),
          row.names = FALSE)
# Also save the true Z (for diagnostics / oracle baselines only — estimators
# should never read this).
write.csv(data.frame(z = Z_b),
          file = file.path(out_dir, paste0(rep_tag, "_z.csv")),
          row.names = FALSE)
write.csv(truth,
          file = file.path(out_dir, paste0(rep_tag, "_truth.csv")),
          row.names = FALSE)

cat(sprintf("[gen_jobs2_latent] task=%d  scenario=%s  rep=%d  n=%d  eta=%g  alpha=%.4f  p_c=%.2f  w_z=%.2f  share_realized=%.2f\n",
            task_id, idx$name, idx$rep, idx$n, idx$eta, idx$alpha,
            idx$p_c, w_z, mean(M_new >= 3)))
