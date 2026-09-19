# =============================================================================
# generate_jobs2.R — Generate one semi-synthetic replication of JOBS II.
#
# Implements the procedure in Cheng et al. (2022), §5.2:
#   1. Fit probits T~X and M_bin~T+X on full JOBS II (M_bin = I(M>=3)).
#   2. Filter to T=0 AND M_bin=0 pool.
#   3. Bootstrap n observations from this pool (X', Y').
#   4. Simulate T_new ~ I(X' beta_pop + U > 0).
#   5. Simulate M_new = eta*(T_new gamma_pop + X' omega_pop) + alpha + V.
#   6. Keep Y' as outcome. True direct/indirect/total effects are all ZERO
#      by construction (all observations come from untreated, nonmediated pool).
#
# Output: writes rep<NNN>_{x,m,t,y,truth}.csv to input/<scenario>/.
# No Z column — JOBS II has no ground-truth latent confounder.
#
# Usage: Rscript generate_jobs2.R <task_id>
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("Usage: Rscript generate_jobs2.R <task_id>")
task_id <- as.integer(args[1])

suppressPackageStartupMessages({
  # (mediation not loaded; jobs from RDS)
})

PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT")
if (PROJECT_ROOT == "") stop("PROJECT_ROOT env var not set.")
source(file.path(PROJECT_ROOT, "R", "scenarios.R"))

idx <- task_id_to_indices(task_id)
set.seed(make_seed(idx$scenario_id, idx$rep))

# -------- Load and prep JOBS II ----------------------------------------------
jobs <- readRDS(file.path(PROJECT_ROOT, "R", "jobs_data.rds"))
df <- jobs

# Covariates — use only numeric/integer columns (factor levels cause probit instability)
X_full <- df[, c("econ_hard", "sex", "age", "depress1")]
X_full$nonwhite_bin <- as.integer(df$nonwhite == "non.white1")
X_full <- X_full[, c("econ_hard", "sex", "age", "depress1", "nonwhite_bin")]
X_full <- as.matrix(X_full)

T_orig <- df$treat                 # binary treatment
M_cont <- df$job_seek              # continuous mediator in [1, 5]
M_bin  <- as.integer((M_cont - mean(M_cont)) / sd(M_cont) >= 0)  # normalized threshold (Cheng et al. normalized continuous covariates)  # Cheng's binarization for the filter step
Y_orig <- df$depress2              # outcome

# -------- Step 1: probits on full data ---------------------------------------
fit_T <- glm(Tt ~ ., data = cbind(Tt = T_orig, as.data.frame(X_full)), family = binomial(link = "probit"), control = list(maxit = 1000))
beta_pop <- coef(fit_T)            # length = 1 + ncol(X_full)

fit_M <- glm(M ~ ., data = cbind(M = M_bin, Tt = T_orig, as.data.frame(X_full)), family = binomial(link = "probit"), control = list(maxit = 1000))
mu_pop      <- coef(fit_M)
gamma_pop   <- unname(mu_pop["Tt"])
omega_pop   <- mu_pop[!names(mu_pop) %in% c("(Intercept)", "Tt")]  # length = ncol(X_full)

# -------- Step 2: filter to non-treated AND non-mediated pool ----------------
keep   <- T_orig == 0 & M_bin == 0
X_pool <- X_full[keep, , drop = FALSE]
Y_pool <- Y_orig[keep]

# -------- Step 3: bootstrap n observations from the pool ---------------------
n <- idx$n
samp_idx <- sample(seq_len(nrow(X_pool)), size = n, replace = TRUE)
X_b      <- X_pool[samp_idx, , drop = FALSE]
Y_b      <- Y_pool[samp_idx]

# -------- Step 4: simulate pseudo-T ------------------------------------------
linpred_T <- cbind(1, X_b) %*% beta_pop
T_new     <- as.integer(linpred_T + rnorm(n) > 0)

# -------- Step 5: simulate pseudo-M ------------------------------------------
eta   <- idx$eta
alpha <- idx$alpha
linpred_M_raw <- T_new * gamma_pop + X_b %*% omega_pop
M_new         <- eta * linpred_M_raw + alpha + rnorm(n)

# -------- Step 6: truth is ZERO by construction ------------------------------
truth <- data.frame(
  scenario_id = idx$scenario_id,
  scenario    = idx$name,
  rep         = idx$rep,
  n           = idx$n,
  eta         = idx$eta,
  alpha       = idx$alpha,
  alpha_share = idx$alpha_share,
  ATE         = 0,
  NDE_d1      = 0,
  NDE_d0      = 0,
  NIE_d1      = 0,
  NIE_d0      = 0
)

# -------- Write output (same schema as synthetic pipelines) ------------------
out_dir <- file.path(PROJECT_ROOT, "input", idx$name)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
rep_tag <- sprintf("rep%03d", idx$rep)

write.csv(as.data.frame(X_b),
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
write.csv(truth,
          file = file.path(out_dir, paste0(rep_tag, "_truth.csv")),
          row.names = FALSE)

cat(sprintf("[gen_jobs2] task=%d  scenario=%s  rep=%d  n=%d  eta=%g  alpha=%.4f  share=%.0f%%  share_realized=%.2f\n",
            task_id, idx$name, idx$rep, idx$n, idx$eta, idx$alpha,
            idx$alpha_share * 100, mean(M_new >= 3)))
