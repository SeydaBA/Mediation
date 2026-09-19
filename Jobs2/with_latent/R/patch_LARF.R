# =============================================================================
# patch_LARF.R — Replace LARF::Generate.Powers with overflow-safe version,
# also patches causalweight's imports env (where hdmedalt resolves unqualified
# Generate.Powers calls). No-op for small p, but kept for consistency.
# =============================================================================

.patched_Generate.Powers <- function(X, lambda) {
  X <- as.matrix(X)
  p <- ncol(X)
  n <- nrow(X)
  if (is.null(colnames(X))) colnames(X) <- paste0("X", seq_len(p))

  enumerate_exponents <- function(p, lambda) {
    comp <- function(d, p) {
      if (p == 1L) return(matrix(d, ncol = 1L))
      res <- vector("list", d + 1L)
      for (k in 0:d) {
        sub <- comp(d - k, p - 1L)
        res[[k + 1L]] <- cbind(k, sub)
      }
      do.call(rbind, res)
    }
    out <- vector("list", lambda)
    for (d in 1:lambda) out[[d]] <- comp(d, p)
    do.call(rbind, out)
  }

  E <- enumerate_exponents(p, lambda)
  m <- nrow(E)

  Full.Data <- matrix(0, nrow = n, ncol = m)
  for (j in seq_len(m)) {
    e <- E[j, ]
    col <- rep(1, n)
    for (k in seq_len(p)) {
      if (e[k] > 0) col <- col * X[, k] ^ e[k]
    }
    Full.Data[, j] <- col
  }
  colnames(Full.Data) <- apply(E, 1, paste, collapse = ".")
  Full.Data <- as.data.frame(Full.Data)

  tab <- cor(Full.Data) == 1
  tab[upper.tri(tab, diag = TRUE)] <- NA
  ind <- which(tab == 1, arr.ind = TRUE)
  if (NROW(ind) > 0) {
    Full.Data <- Full.Data[, -ind[, 1], drop = FALSE]
  }

  K.list <- vapply(colnames(Full.Data), function(nm) {
    sum(as.numeric(strsplit(nm, "[.]")[[1]]))
  }, numeric(1))
  ranks <- rank(K.list, ties.method = "first")
  data.frame(Full.Data[, order(ranks), drop = FALSE])
}

# Install in LARF namespace
suppressWarnings({
  if (requireNamespace("LARF", quietly = TRUE)) {
    assignInNamespace("Generate.Powers", .patched_Generate.Powers, ns = "LARF")
    cat("LARF::Generate.Powers patched.\n")
  }
})

# Also patch causalweight's imports env (where hdmedalt resolves unqualified
# Generate.Powers calls).
.patch_causalweight_imports <- function() {
  if (!requireNamespace("causalweight", quietly = TRUE)) return(invisible(NULL))
  ns_cw <- asNamespace("causalweight")
  imp_env <- parent.env(ns_cw)
  if ("Generate.Powers" %in% ls(envir = imp_env, all.names = TRUE)) {
    unlockBinding("Generate.Powers", imp_env)
    assign("Generate.Powers", .patched_Generate.Powers, envir = imp_env)
    cat("  patched: causalweight imports env (parent.env)\n")
  }
}
.patch_causalweight_imports()
