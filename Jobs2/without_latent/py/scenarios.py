# =============================================================================
# scenarios.py — JOBS II semi-synthetic, 8 scenarios per Cheng et al. (2022).
# Mirror of R/scenarios.R — order must match exactly.
# =============================================================================

import os
import itertools

# expand.grid in R varies first column FASTEST, so we replicate that order:
#   n varies fastest, then eta, then alpha_share
_N_LIST           = [500, 1000]
_ETA_LIST         = [1, 10]
_ALPHA_SHARE_LIST = [0.10, 0.50]

SCENARIOS = []
for share in _ALPHA_SHARE_LIST:
    for eta in _ETA_LIST:
        for n in _N_LIST:
            SCENARIOS.append({
                "n":           n,
                "eta":         eta,
                "alpha_share": share,
                "name":        f"n{n}_eta{eta}_share{int(share * 100)}",
            })

for i, s in enumerate(SCENARIOS):
    s["scenario_id"] = i + 1

N_REPS_PER_SCENARIO = 100
N_SCENARIOS         = len(SCENARIOS)
N_TASKS             = N_SCENARIOS * N_REPS_PER_SCENARIO


def task_id_to_indices(task_id: int) -> dict:
    if task_id < 1 or task_id > N_TASKS:
        raise ValueError(f"task_id out of range: {task_id} (max {N_TASKS})")
    scenario_id = (task_id - 1) // N_REPS_PER_SCENARIO + 1
    rep         = (task_id - 1) %  N_REPS_PER_SCENARIO + 1
    s           = SCENARIOS[scenario_id - 1]
    return {
        "task_id":     task_id,
        "scenario_id": scenario_id,
        "rep":         rep,
        "n":           s["n"],
        "eta":         s["eta"],
        "alpha_share": s["alpha_share"],
        "name":        s["name"],
    }


def make_seed(scenario_id: int, rep: int) -> int:
    return 1000 * scenario_id + rep


if __name__ == "__main__":
    for s in SCENARIOS:
        print(s)
    print(f"\nTotal scenarios: {N_SCENARIOS}")
    print(f"Total tasks:     {N_TASKS}")
