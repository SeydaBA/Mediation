import os
import sys
import glob
import numpy as np
import pandas as pd

from scenarios import SCENARIOS, N_REPS_PER_SCENARIO


METHODS = ["lsem", "lsem_i", "dml", "dmavae", "cmavae"]
EFFECTS = ["ATE", "NDE_d1", "NDE_d0", "NIE_d1", "NIE_d0"]


def collect_method(perf_root: str, method: str) -> pd.DataFrame:
    rows = []
    for s in SCENARIOS:
        scen_name = s["name"]
        scen_dir  = os.path.join(perf_root, f"performance_{method}", scen_name)
        if not os.path.isdir(scen_dir):
            continue
        for fp in sorted(glob.glob(os.path.join(scen_dir, "rep*.csv"))):
            if "loss_" in os.path.basename(fp):
                continue
            try:
                rows.append(pd.read_csv(fp))
            except Exception as e:
                print(f"  WARN: failed to read {fp}: {e}", file=sys.stderr)
    if not rows:
        return pd.DataFrame()
    return pd.concat(rows, ignore_index=True)


def get_estimate_series(scen_df: pd.DataFrame, eff: str) -> pd.Series:
    """Return the raw estimated effect per rep, whichever column layout exists."""
    est_col  = f"{eff}_est"
    bias_col = f"{eff}_bias"
    true_col = f"{eff}_true"

    if est_col in scen_df.columns:
        return scen_df[est_col]
    if eff in scen_df.columns:
        return scen_df[eff]
    if bias_col in scen_df.columns and true_col in scen_df.columns:
        return scen_df[bias_col] + scen_df[true_col]
    if bias_col in scen_df.columns:
        # JOBS II semi-synthetic: truth is zero by construction.
        return scen_df[bias_col]
    return pd.Series(dtype=float)


# NEW ------------------------------------------------------------------------
def repair_lsem_i(df: pd.DataFrame) -> pd.DataFrame:
    """Fix run_lsem_i.R bug (NDE(d=1) evaluated at the control mediator level,
    contaminating NDE_d1 and ATE). Exact per-replication identities:
        ATE    = NDE_d0 + NIE_d1
        NDE_d1 = NDE_d0 + NIE_d1 - NIE_d0
    Applied to every column layout present; numerical no-op if the rep files
    were produced by the corrected runner."""
    df = df.copy()
    for suf in ("", "_est", "_bias"):
        nde0, nie1, nie0 = f"NDE_d0{suf}", f"NIE_d1{suf}", f"NIE_d0{suf}"
        if all(c in df.columns for c in (nde0, nie1, nie0)):
            if f"ATE{suf}" in df.columns:
                df[f"ATE{suf}"] = df[nde0] + df[nie1]
            if f"NDE_d1{suf}" in df.columns:
                df[f"NDE_d1{suf}"] = df[nde0] + df[nie1] - df[nie0]
    return df


# NEW ------------------------------------------------------------------------
def check_decomposition(df: pd.DataFrame, method: str) -> None:
    """Warn if tau != NDE(0) + NIE(1) per replication (any layout)."""
    for suf in ("", "_est", "_bias"):
        cols = (f"ATE{suf}", f"NDE_d0{suf}", f"NIE_d1{suf}")
        if all(c in df.columns for c in cols):
            gap = (df[cols[0]] - df[cols[1]] - df[cols[2]]).abs().max()
            if gap > 1e-8:
                print(f"  WARN {method}: tau != NDE(0)+NIE(1), "
                      f"max gap {gap:.3g}", file=sys.stderr)
            return


def summarize(df: pd.DataFrame, method: str) -> pd.DataFrame:
    """Per (method, scenario): estimate mean/sd, bias mean/sd, RMSE per effect."""
    if df.empty:
        return pd.DataFrame()

    summary_rows = []
    for sid, scen_df in df.groupby("scenario_id"):
        s = SCENARIOS[int(sid) - 1]
        row = {
            "method":      method,
            "scenario_id": int(sid),
            "scenario":    s["name"],
            "n":           s["n"],
            "eta":         s["eta"],
            "alpha_share": s["alpha_share"],
            "n_reps":      len(scen_df),
        }
        if "p_c" in s:
            row["p_c"] = s["p_c"]

        for eff in EFFECTS:
            est_vals = get_estimate_series(scen_df, eff).dropna()
            if len(est_vals):
                row[f"{eff}_est_mean"] = float(est_vals.mean())
                row[f"{eff}_est_sd"]   = float(est_vals.std(ddof=1)) if len(est_vals) > 1 else 0.0
            else:
                row[f"{eff}_est_mean"] = np.nan
                row[f"{eff}_est_sd"]   = np.nan

            bias_col = f"{eff}_bias"
            if bias_col in scen_df.columns:
                vals = scen_df[bias_col].dropna()
                if len(vals):
                    row[f"{eff}_bias_mean"] = float(vals.mean())
                    row[f"{eff}_bias_sd"]   = float(vals.std(ddof=1)) if len(vals) > 1 else 0.0
                    row[f"{eff}_rmse"]      = float(np.sqrt((vals ** 2).mean()))
                else:
                    row[f"{eff}_bias_mean"] = np.nan
                    row[f"{eff}_bias_sd"]   = np.nan
                    row[f"{eff}_rmse"]      = np.nan
        summary_rows.append(row)
    return pd.DataFrame(summary_rows)


def main():
    project_root = os.environ.get("PROJECT_ROOT")
    if not project_root:
        sys.exit("PROJECT_ROOT env var not set.")

    all_rows     = []
    all_summary  = []

    for method in METHODS:
        df = collect_method(project_root, method)
        if df.empty:
            print(f"[aggregate] {method}: no rep files found.", flush=True)
            continue
        if method == "lsem_i":              # NEW: repair existing rep files
            df = repair_lsem_i(df)
        check_decomposition(df, method)     # NEW: guardrail for all methods
        print(f"[aggregate] {method}: {len(df)} reps across "
              f"{df['scenario_id'].nunique()} scenarios", flush=True)
        all_rows.append(df)
        all_summary.append(summarize(df, method))

    if all_rows:
        out_all = pd.concat(all_rows, ignore_index=True)
        out_all.to_csv(os.path.join(project_root, "all_results.csv"),
                       index=False, float_format="%.6f")
        print(f"\n[aggregate] wrote all_results.csv  ({len(out_all)} rows)")

    if all_summary:
        out_sum = pd.concat(all_summary, ignore_index=True)
        out_sum.to_csv(os.path.join(project_root, "summary_all_methods.csv"),
                       index=False, float_format="%.6f")
        print(f"[aggregate] wrote summary_all_methods.csv  ({len(out_sum)} rows)")

    n_scen = len(SCENARIOS)
    print(f"\nExpected: 5 methods x {n_scen} scenarios = {5 * n_scen} summary rows")


if __name__ == "__main__":
    main()
