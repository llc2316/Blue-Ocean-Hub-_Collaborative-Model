from __future__ import annotations

from dataclasses import dataclass
from typing import Any
import numpy as np
import pandas as pd
from scipy.optimize import linprog
from scipy.sparse import lil_matrix, csr_matrix

from .data_loader import InputBundle
from .pue import build_piecewise_curves, effective_temperature, facility_power


@dataclass
class ModelResult:
    hourly: pd.DataFrame
    summary: dict[str, Any]
    solver: dict[str, Any]
    audit: dict[str, Any]


class IndexMap:
    def __init__(self, T: int, B: int):
        self.T = T
        self.B = B
        cursor = 0
        self.xr = np.arange(cursor, cursor + T); cursor += T
        self.ur = np.arange(cursor, cursor + T); cursor += T
        self.xf = np.arange(cursor, cursor + T); cursor += T
        self.q = np.arange(cursor, cursor + T); cursor += T
        self.xs = np.arange(cursor, cursor + T); cursor += T
        self.y = np.arange(cursor, cursor + T * B).reshape(T, B); cursor += T * B
        self.n = cursor


def _task_row(df: pd.DataFrame, name: str) -> pd.Series:
    rows = df.loc[df["task_type"] == name]
    if rows.empty:
        raise ValueError(f"task_type_parameters.csv 缺少 {name}")
    return rows.iloc[0]


def _price_row(df: pd.DataFrame, name: str) -> float:
    rows = df.loc[df["task_type"] == name]
    if rows.empty:
        raise ValueError(f"compute_price.csv 缺少 {name}")
    return float(rows.iloc[0]["price_yuan_per_gpu_h"])


def solve_dc_only(bundle: InputBundle, config: dict[str, Any]) -> ModelResult:
    w = bundle.workload.reset_index(drop=True)
    power = bundle.power.reset_index(drop=True)
    T = len(w)
    dt = 1.0
    B = int(config["piecewise_segments"])
    idx = IndexMap(T, B)

    capacity = float(bundle.it_params["it_capacity"])
    equivalent_gpu_it_power_kw = float(bundle.it_params["equivalent_gpu_it_power_kw"])
    if equivalent_gpu_it_power_kw <= 0:
        raise ValueError("equivalent_gpu_it_power_kw 必须大于0")
    gpu_hours_per_mwh_it = 1000.0 / equivalent_gpu_it_power_kw

    scale = float(config["workload_scale"])
    spot_scale = float(config["spot_workload_scale"])
    rigid_arrival = w["rigid_compute_arrival"].to_numpy(float) * scale
    flex_arrival = w["flex_compute_arrival"].to_numpy(float) * scale
    spot_demand = w["spot_compute_demand"].to_numpy(float) * spot_scale
    fiber = w["fiber_availability"].to_numpy(float)

    rigid_price_gpu_h = _price_row(bundle.price_table, "rigid_inference")
    flex_price_gpu_h = _price_row(bundle.price_table, "flexible_batch")
    spot_price_gpu_h = _price_row(bundle.price_table, "optional_job")
    rigid_price = rigid_price_gpu_h * gpu_hours_per_mwh_it
    flex_price = flex_price_gpu_h * gpu_hours_per_mwh_it
    default_spot_price = spot_price_gpu_h * gpu_hours_per_mwh_it
    if bool(config.get("use_workload_spot_price", True)) and "spot_compute_price" in w:
        spot_price = w["spot_compute_price"].fillna(default_spot_price).to_numpy(float)
        spot_price_source = "workload_spot_compute_price (CNY/MWh-IT, teacher scenario)"
    else:
        spot_price = np.full(T, default_spot_price)
        spot_price_source = "compute_price optional_job (CNY/GPU·h) converted by equivalent_gpu_it_power_kw"

    rigid_task_row = _task_row(bundle.task_params, "rigid_inference")
    penalty_col = "penalty_yuan_per_gpu_h" if "penalty_yuan_per_gpu_h" in bundle.task_params.columns else "penalty_yuan_per_resource_h"
    rigid_penalty_gpu_h = float(rigid_task_row[penalty_col])
    rigid_penalty = rigid_penalty_gpu_h * gpu_hours_per_mwh_it
    flex_delay_h = int(_task_row(bundle.task_params, "flexible_batch")["max_delay_h"])

    sea = bundle.sea_temperature.to_numpy(float)
    tau = float(bundle.cooling_params.get("thermal_time_constant", 0.0))
    temp_eff = effective_temperature(sea, dt, tau)
    curves = build_piecewise_curves(temp_eff, bundle.it_params, bundle.cooling_params, B)
    widths = curves["segment_widths"]
    slopes = curves["slopes"]
    base_pdc = curves["facility_power_breakpoints"][:, 0]

    elec_price = power["electricity_price_yuan_per_mwh"].to_numpy(float)
    cap = power["dc_power_cap_mw"].to_numpy(float)
    if (elec_price < 0).any():
        raise ValueError("当前连续增量分段线性化要求电价非负；检测到负电价。")

    c = np.zeros(idx.n)
    c[idx.xr] = -rigid_price + float(config.get("variable_om_yuan_per_mwh_it", 0.0))
    c[idx.ur] = rigid_penalty
    c[idx.xf] = -flex_price + float(config.get("variable_om_yuan_per_mwh_it", 0.0))
    c[idx.xs] = -spot_price + float(config.get("variable_om_yuan_per_mwh_it", 0.0))
    for t in range(T):
        c[idx.y[t, :]] = elec_price[t] * dt * slopes[t, :]
    if not bool(config.get("enforce_terminal_flex_queue", True)):
        c[idx.q[-1]] += float(config.get("flex_terminal_penalty_yuan_per_mwh_it", 10000.0))

    bounds: list[tuple[float | None, float | None]] = [(0.0, None)] * idx.n
    for t in range(T):
        bounds[idx.xr[t]] = (0.0, rigid_arrival[t] * dt)
        bounds[idx.ur[t]] = (0.0, rigid_arrival[t] * dt)
        bounds[idx.xf[t]] = (0.0, None)
        bounds[idx.q[t]] = (0.0, None)
        bounds[idx.xs[t]] = (0.0, spot_demand[t] * dt)
        for b in range(B):
            bounds[idx.y[t, b]] = (0.0, widths[b])

    # Equalities: rigid balance, flex queue balance, service-to-segment mapping, terminal queue.
    eq_rows = 3 * T + (1 if bool(config.get("enforce_terminal_flex_queue", True)) else 0)
    Aeq = lil_matrix((eq_rows, idx.n), dtype=float)
    beq = np.zeros(eq_rows)
    r = 0
    for t in range(T):
        Aeq[r, idx.xr[t]] = 1.0
        Aeq[r, idx.ur[t]] = 1.0
        beq[r] = rigid_arrival[t] * dt
        r += 1
    for t in range(T):
        Aeq[r, idx.q[t]] = 1.0
        if t > 0:
            Aeq[r, idx.q[t - 1]] = -1.0
        Aeq[r, idx.xf[t]] = 1.0
        beq[r] = flex_arrival[t] * dt
        r += 1
    for t in range(T):
        Aeq[r, idx.xr[t]] = 1.0
        Aeq[r, idx.xf[t]] = 1.0
        Aeq[r, idx.xs[t]] = 1.0
        for b in range(B):
            Aeq[r, idx.y[t, b]] = -dt
        beq[r] = 0.0
        r += 1
    if bool(config.get("enforce_terminal_flex_queue", True)):
        Aeq[r, idx.q[-1]] = 1.0
        beq[r] = 0.0

    # Inequalities: fiber capacity, facility power cap, flex deadline cumulative constraints.
    deadline_rows = max(0, T - flex_delay_h)
    Aub = lil_matrix((2 * T + deadline_rows, idx.n), dtype=float)
    bub = np.zeros(2 * T + deadline_rows)
    r = 0
    for t in range(T):
        for b in range(B):
            Aub[r, idx.y[t, b]] = 1.0
        bub[r] = capacity * fiber[t]
        r += 1
    for t in range(T):
        for b in range(B):
            Aub[r, idx.y[t, b]] = slopes[t, b]
        bub[r] = cap[t] - base_pdc[t]
        r += 1
    # By hour t, all flexible arrivals up to t-L must have been served.
    for t in range(flex_delay_h, T):
        for j in range(t + 1):
            Aub[r, idx.xf[j]] = -1.0
        required = float(np.sum(flex_arrival[: t - flex_delay_h + 1]) * dt)
        bub[r] = -required
        r += 1

    options = {
        "presolve": True,
        "primal_feasibility_tolerance": float(config.get("solver_primal_tolerance", 1e-8)),
        "dual_feasibility_tolerance": float(config.get("solver_dual_tolerance", 1e-8)),
    }
    result = linprog(
        c,
        A_ub=csr_matrix(Aub),
        b_ub=bub,
        A_eq=csr_matrix(Aeq),
        b_eq=beq,
        bounds=bounds,
        method="highs",
        options=options,
    )
    if not result.success:
        raise RuntimeError(f"优化失败: status={result.status}, message={result.message}")

    z = result.x
    xr, ur, xf, q, xs = z[idx.xr], z[idx.ur], z[idx.xf], z[idx.q], z[idx.xs]
    y = z[idx.y]
    service_rate = y.sum(axis=1)
    p_it, p_cool, p_dc_exact, pue_exact = facility_power(service_rate, temp_eff, bundle.it_params, bundle.cooling_params)
    p_dc_pwl = base_pdc + np.sum(slopes * y, axis=1)
    electricity_cost = p_dc_exact * dt * elec_price
    rigid_revenue = xr * rigid_price
    flex_revenue = xf * flex_price
    spot_revenue = xs * spot_price
    unmet_penalty = ur * rigid_penalty
    variable_om = (xr + xf + xs) * float(config.get("variable_om_yuan_per_mwh_it", 0.0))
    margin = rigid_revenue + flex_revenue + spot_revenue - electricity_cost - unmet_penalty - variable_om

    hourly = pd.DataFrame(
        {
            "timestamp": w["timestamp"],
            "rigid_arrival_mwh_it": rigid_arrival * dt,
            "flex_arrival_mwh_it": flex_arrival * dt,
            "spot_demand_mwh_it": spot_demand * dt,
            "rigid_served_mwh_it": xr,
            "rigid_unserved_mwh_it": ur,
            "flex_served_mwh_it": xf,
            "flex_queue_mwh_it": q,
            "spot_served_mwh_it": xs,
            "rigid_gpu_hours": xr * gpu_hours_per_mwh_it,
            "flex_gpu_hours": xf * gpu_hours_per_mwh_it,
            "spot_gpu_hours": xs * gpu_hours_per_mwh_it,
            "total_gpu_hours": (xr + xf + xs) * gpu_hours_per_mwh_it,
            "service_rate_mw_it": service_rate,
            "it_load_ratio": service_rate / capacity,
            "it_power_mw": p_it,
            "cooling_power_mw": p_cool,
            "dc_power_mw": p_dc_exact,
            "dc_power_pwl_mw": p_dc_pwl,
            "pue": pue_exact,
            "sea_temperature_c": sea,
            "effective_sea_temperature_c": temp_eff,
            "dc_power_cap_mw": cap,
            "electricity_price_yuan_per_mwh": elec_price,
            "rigid_revenue_yuan": rigid_revenue,
            "flex_revenue_yuan": flex_revenue,
            "spot_revenue_yuan": spot_revenue,
            "electricity_cost_yuan": electricity_cost,
            "unmet_penalty_yuan": unmet_penalty,
            "variable_om_yuan": variable_om,
            "electricity_contribution_margin_yuan": margin,
        }
    )

    tol = float(config.get("audit_tolerance", 1e-6))
    rigid_resid = xr + ur - rigid_arrival * dt
    queue_resid = np.empty(T)
    for t in range(T):
        prev = q[t - 1] if t > 0 else 0.0
        queue_resid[t] = q[t] - prev - flex_arrival[t] * dt + xf[t]
    service_resid = xr + xf + xs - service_rate * dt
    audit = {
        "max_rigid_balance_residual": float(np.max(np.abs(rigid_resid))),
        "max_flex_queue_residual": float(np.max(np.abs(queue_resid))),
        "max_service_mapping_residual": float(np.max(np.abs(service_resid))),
        "max_piecewise_power_error_mw": float(np.max(np.abs(p_dc_pwl - p_dc_exact))),
        "max_power_cap_violation_mw": float(np.max(np.maximum(p_dc_exact - cap, 0.0))),
        "max_fiber_capacity_violation_mw_it": float(np.max(np.maximum(service_rate - capacity * fiber, 0.0))),
        "terminal_flex_queue_mwh_it": float(q[-1]),
    }
    audit["passed"] = bool(
        audit["max_rigid_balance_residual"] <= tol
        and audit["max_flex_queue_residual"] <= tol
        and audit["max_service_mapping_residual"] <= tol
        and audit["max_power_cap_violation_mw"] <= max(tol, audit["max_piecewise_power_error_mw"] + tol)
        and audit["max_fiber_capacity_violation_mw_it"] <= tol
        and (not bool(config.get("enforce_terminal_flex_queue", True)) or audit["terminal_flex_queue_mwh_it"] <= tol)
    )

    summary = {
        "hours": T,
        "it_capacity_mw": capacity,
        "workload_scale": scale,
        "spot_workload_scale": spot_scale,
        "equivalent_gpu_it_power_kw": equivalent_gpu_it_power_kw,
        "gpu_hours_per_mwh_it": gpu_hours_per_mwh_it,
        "rigid_price_yuan_per_gpu_h": rigid_price_gpu_h,
        "flex_price_yuan_per_gpu_h": flex_price_gpu_h,
        "spot_price_yuan_per_gpu_h": spot_price_gpu_h,
        "rigid_price_yuan_per_mwh_it_equivalent": rigid_price,
        "flex_price_yuan_per_mwh_it_equivalent": flex_price,
        "spot_price_source": spot_price_source,
        "total_rigid_arrival_mwh_it": float(np.sum(rigid_arrival) * dt),
        "total_rigid_served_mwh_it": float(np.sum(xr)),
        "total_rigid_unserved_mwh_it": float(np.sum(ur)),
        "total_flex_arrival_mwh_it": float(np.sum(flex_arrival) * dt),
        "total_flex_served_mwh_it": float(np.sum(xf)),
        "total_spot_served_mwh_it": float(np.sum(xs)),
        "total_rigid_gpu_hours": float(np.sum(xr) * gpu_hours_per_mwh_it),
        "total_flex_gpu_hours": float(np.sum(xf) * gpu_hours_per_mwh_it),
        "total_spot_gpu_hours": float(np.sum(xs) * gpu_hours_per_mwh_it),
        "total_gpu_hours": float(np.sum(xr + xf + xs) * gpu_hours_per_mwh_it),
        "contract_service_rate": float((np.sum(xr) + np.sum(xf)) / max(np.sum(rigid_arrival + flex_arrival) * dt, 1e-12)),
        "average_it_load_ratio": float(np.mean(service_rate / capacity)),
        "peak_it_service_rate_mw_it": float(np.max(service_rate)),
        "total_it_energy_mwh": float(np.sum(p_it) * dt),
        "total_cooling_energy_mwh": float(np.sum(p_cool) * dt),
        "total_dc_energy_mwh": float(np.sum(p_dc_exact) * dt),
        "average_pue": float(np.sum(p_dc_exact) / np.sum(p_it)),
        "min_pue": float(np.min(pue_exact)),
        "max_pue": float(np.max(pue_exact)),
        "total_compute_revenue_yuan": float(np.sum(rigid_revenue + flex_revenue + spot_revenue)),
        "total_electricity_cost_yuan": float(np.sum(electricity_cost)),
        "total_unmet_penalty_yuan": float(np.sum(unmet_penalty)),
        "electricity_contribution_margin_yuan": float(np.sum(margin)),
        "note": "该利润为算力收入扣除电费、任务惩罚和可变运维后的电力边际贡献，不含CAPEX、折旧及完整运维。",
    }
    solver = {
        "success": bool(result.success),
        "status": int(result.status),
        "message": str(result.message),
        "objective_minimized_yuan_excluding_constant_idle_cost": float(result.fun),
        "iterations": int(getattr(result, "nit", 0)),
    }
    return ModelResult(hourly=hourly, summary=summary, solver=solver, audit=audit)
