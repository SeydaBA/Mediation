# =============================================================================
# aggregate_results.py — self-contained aggregator.
# Scans performance_<method>/<scenario>/rep*.csv, pulls scenario metadata from
# the rep files themselves (no dependency on scenarios.py), and writes:
#   all_results.csv          every rep row, all methods
#   summary_all_methods.csv  per (method, scenario): est mean/sd, truth,
#                            bias mean/sd, rmse for each effect
# Works for both the synthetic projects (oracle variants, truth != 0) and the
# JOBS II projects (truth = 0).
# =============================================================================
import os
import sys
import glob
import numpy as np
import pandas as pd

METHODS = ["lsem", "lsem_i", "dml", "dmavae", "cmavae",
           "lsem_oracle", "lsem_i_oracle", "dml_oracle"]
EFFECTS = ["ATE", "NDE_d1", "NDE_d0", "NIE_d1", "NIE_d0"]

# Scenario metadata carried into the summary if present in the rep files.
META_COLS = ["scenario", "N", "n_X", "sigma2_x",
             "n", "eta", "alpha_share", "p_c"]


def collect_method(perf_root: str, method: str) -> pd.DataFrame:
    base = os.path.join(perf_root, f"performance_{method}")
    if not os.path.isdir(base):
        return pd.DataFrame()
    rows = []
    for scen_dir in sorted(glob.glob(os.path.join(base, "*"))):
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


def get_estimate_series(df: pd.DataFrame, eff: str) -> pd.Series:
    """Raw estimated effect per rep, whichever column layout exists."""
    if f"{eff}_est" in df.columns:
        return df[f"{eff}_est"]
    if eff in df.columns:
        return df[eff]
    if f"{eff}_bias" in df.columns and f"{eff}_true" in df.columns:
        return df[f"{eff}_bias"] + df[f"{eff}_true"]
    if f"{eff}_bias" in df.columns:        # JOBS II: truth = 0
        return df[f"{eff}_bias"]
    return pd.Series(dtype=float)


def summarize(df: pd.DataFrame, method: str) -> pd.DataFrame:
    if df.empty:
        return pd.DataFrame()
    out = []
    for sid, g in df.groupby("scenario_id"):
        row = {"method": method, "scenario_id": int(sid), "n_reps": len(g)}
        for c in META_COLS:
            if c in g.columns:
                row[c] = g[c].iloc[0]

        for eff in EFFECTS:
            est = get_estimate_series(g, eff).dropna()
            if len(est):
                row[f"{eff}_est_mean"] = float(est.mean())
                row[f"{eff}_est_sd"]   = float(est.std(ddof=1)) if len(est) > 1 else 0.0
            else:
                row[f"{eff}_est_mean"] = np.nan
                row[f"{eff}_est_sd"]   = np.nan

            tcol = f"{eff}_true"
            if tcol in g.columns and g[tcol].notna().any():
                row[f"{eff}_true"] = float(g[tcol].dropna().iloc[0])

            bcol = f"{eff}_bias"
            if bcol in g.columns:
                v = g[bcol].dropna()
                if len(v):
                    row[f"{eff}_bias_mean"] = float(v.mean())
                    row[f"{eff}_bias_sd"]   = float(v.std(ddof=1)) if len(v) > 1 else 0.0
                    row[f"{eff}_rmse"]      = float(np.sqrt((v ** 2).mean()))
                else:
                    row[f"{eff}_bias_mean"] = np.nan
                    row[f"{eff}_bias_sd"]   = np.nan
                    row[f"{eff}_rmse"]      = np.nan
        out.append(row)
    return pd.DataFrame(out)


def main():
    project_root = os.environ.get("PROJECT_ROOT")
    if not project_root:
        sys.exit("PROJECT_ROOT env var not set.")

    all_rows, all_summary = [], []
    for method in METHODS:
        df = collect_method(project_root, method)
        if df.empty:
            print(f"[aggregate] {method}: no rep files found.", flush=True)
            continue
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
        out_sum = out_sum.sort_values(["method", "scenario_id"]).reset_index(drop=True)
        out_sum.to_csv(os.path.join(project_root, "summary_all_methods.csv"),
                       index=False, float_format="%.6f")
        print(f"[aggregate] wrote summary_all_methods.csv  ({len(out_sum)} rows)")
        print(f"[aggregate] methods found: {sorted(out_sum['method'].unique())}")


if __name__ == "__main__":
    main()
