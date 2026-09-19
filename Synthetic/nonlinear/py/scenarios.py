"""
scenarios.py — Python counterpart to R/scenarios.R.

Keep these in lock-step: 8 scenarios, 100 reps each, total 800 array tasks.
"""

from itertools import product

# Order must match expand.grid in scenarios.R: N varies fastest, then n_X, then sigma2_x
_N_LIST       = [1000, 4000]
_NX_LIST      = [10, 200]
_SIGMA2X_LIST = [1, 3]

# expand.grid varies the FIRST column fastest, so the outer order is
# (sigma2_x outermost, then n_X, then N innermost)
SCENARIOS = []
sid = 1
for sx in _SIGMA2X_LIST:
    for nx in _NX_LIST:
        for n in _N_LIST:
            SCENARIOS.append({
                "scenario_id": sid,
                "N":           n,
                "n_X":         nx,
                "sigma2_x":    sx,
                "name":        f"N{n}_nX{nx}_sx{sx}",
            })
            sid += 1

N_REPS_PER_SCENARIO = 100


def task_id_to_indices(task_id: int):
    assert 1 <= task_id <= len(SCENARIOS) * N_REPS_PER_SCENARIO, \
        f"task_id {task_id} out of range"
    scenario_idx = (task_id - 1) // N_REPS_PER_SCENARIO        # 0-based
    rep          = (task_id - 1) %  N_REPS_PER_SCENARIO + 1    # 1-based
    s = SCENARIOS[scenario_idx]
    return {
        "task_id":     task_id,
        "scenario_id": s["scenario_id"],
        "rep":         rep,
        "N":           s["N"],
        "n_X":         s["n_X"],
        "sigma2_x":    s["sigma2_x"],
        "name":        s["name"],
    }
