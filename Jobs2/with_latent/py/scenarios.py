# =============================================================================
# scenarios.py — JOBS II semi-synthetic with latent confounder (40 scenarios).
# Mirror of R/scenarios.R — order must match exactly.
#
# Grid order (R's expand.grid varies first column fastest):
#   n varies fastest, then eta, then alpha_share, then p_c
# Total: 2 * 2 * 2 * 5 = 40 scenarios, 100 reps each = 4000 tasks
# =============================================================================

import os
import itertools

_N_LIST           = [500, 1000]
_ETA_LIST         = [1, 10]
_ALPHA_SHARE_LIST = [0.10, 0.50]
_P_C_LIST         = [0.1, 0.2, 0.3, 0.4, 0.5]

SCENARIOS = []
for p_c in _P_C_LIST:
    for share in _ALPHA_SHARE_LIST:
        for eta in _ETA_LIST:
            for n in _N_LIST:
                SCENARIOS.append({
                    "n":           n,
                    "eta":         eta,
                    "alpha_share": share,
                    "p_c":         p_c,
                    "name":        f"n{n}_eta{eta}_share{int(share*100)}_pc{int(round(p_c*100)):02d}",
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
        "p_c":         s["p_c"],
        "name":        s["name"],
    }


def make_seed(scenario_id: int, rep: int) -> int:
    return 1000 * scenario_id + rep


if __name__ == "__main__":
    for s in SCENARIOS:
        print(s)
    print(f"\nTotal scenarios: {N_SCENARIOS}")
    print(f"Total tasks:     {N_TASKS}")
