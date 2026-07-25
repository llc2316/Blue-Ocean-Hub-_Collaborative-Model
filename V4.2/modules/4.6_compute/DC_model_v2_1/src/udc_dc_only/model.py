from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd
from scipy.optimize import linprog
from scipy.sparse import csr_matrix, lil_matrix, vstack

from .data_loader import InputBundle
from .pue import build_piecewise_curves, effective_temperature, facility_power


@dataclass
class ModelResult:
    hourly: pd.DataFrame
    summary: dict[str, Any]
    solver: dict[str, Any]
    audit: dict[str, Any]


class IndexMap:
    """LP变量索引。

    xr: 刚性任务服务量
    ur: 刚性任务未服务量（允许，但优先级最高且承担高额SLA惩罚）
    xf: 柔性任务服务量
    q:  柔性任务队列
    vf: 已超过最大延期时间的柔性任务量（逐时SLA违约暴露）
    xs: 可选/弹性任务服务量（未执行部分直接丢弃，无惩罚）
    y:  分段线性化后的总IT服务率
    """

    def __init__(self, T: int, B: int):
        self.T = T
        self.B = B
        cursor = 0
        self.xr = np.arange(cursor, cursor + T)
        cursor += T
        self.ur = np.arange(cursor, cursor + T)
        cursor += T
        self.xf = np.arange(cursor, cursor + T)
        cursor += T
        self.q = np.arange(cursor, cursor + T)
        cursor += T
        self.vf = np.arange(cursor, cursor + T)
        cursor += T
        self.xs = np.arange(cursor, cursor + T)
        cursor += T
        self.y = np.arange(cursor, cursor + T * B).reshape(T, B)
        cursor += T * B
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


def _penalty_column(task_params: pd.DataFrame) -> str:
    if "penalty_yuan_per_gpu_h" in task_params.columns:
        return "penalty_yuan_per_gpu_h"
    if "penalty_yuan_per_resource_h" in task_params.columns:
        return "penalty_yuan_per_resource_h"
    raise ValueError(
        "task_type_parameters.csv缺少penalty_yuan_per_gpu_h或"
        "penalty_yuan_per_resource_h"
    )


def _resolve_terminal_penalty(
    config: dict[str, Any], flex_penalty_yuan_per_mwh_it: float
) -> float:
    """168小时边界之后不再继续模拟，期末队列按未完成合同任务计违约。

    配置为"auto"或None时，使用柔性任务自身的SLA惩罚单价。
    """

    raw = config.get("flex_terminal_penalty_yuan_per_mwh_it", "auto")
    if raw is None or (isinstance(raw, str) and raw.strip().lower() == "auto"):
        return flex_penalty_yuan_per_mwh_it
    value = float(raw)
    if value < 0:
        raise ValueError("flex_terminal_penalty_yuan_per_mwh_it不能为负")
    return value


def _solve_lp(
    objective: np.ndarray,
    Aub: csr_matrix,
    bub: np.ndarray,
    Aeq: csr_matrix,
    beq: np.ndarray,
    bounds: list[tuple[float | None, float | None]],
    options: dict[str, Any],
    stage_name: str,
):
    result = linprog(
        objective,
        A_ub=Aub,
        b_ub=bub,
        A_eq=Aeq,
        b_eq=beq,
        bounds=bounds,
        method="highs",
        options=options,
    )
    if not result.success:
        raise RuntimeError(
            f"{stage_name}优化失败: status={result.status}, message={result.message}"
        )
    return result


def solve_dc_only(bundle: InputBundle, config: dict[str, Any]) -> ModelResult:
    """求解DC-only任务调度。

    调度优先级采用三级词典序优化：
    1. 最小化刚性任务未服务量；
    2. 在不恶化刚性任务的前提下，最小化柔性任务超期与队列；
    3. 在不恶化前两级的前提下，最大化电力边际收益。

    唯一硬供电边界是DC零任务状态下的基础设施功率。若外部可用功率低于
    该功率，DC无法维持基本运行，模型明确报出基础供电不可行。高于基础功率
    后，电力不足不会令模型“死机”：刚性任务可缺供并受高额惩罚，柔性任务
    可延期/超期并受SLA惩罚，可选任务直接丢弃。
    """

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
        spot_price = (
            w["spot_compute_price"].fillna(default_spot_price).to_numpy(float)
        )
        spot_price_source = "workload_spot_compute_price (CNY/MWh-IT)"
    else:
        spot_price = np.full(T, default_spot_price)
        spot_price_source = (
            "compute_price optional_job (CNY/GPU·h) converted by "
            "equivalent_gpu_it_power_kw"
        )

    penalty_col = _penalty_column(bundle.task_params)
    rigid_task_row = _task_row(bundle.task_params, "rigid_inference")
    flex_task_row = _task_row(bundle.task_params, "flexible_batch")
    rigid_penalty_gpu_h = float(rigid_task_row[penalty_col])
    flex_penalty_gpu_h = float(flex_task_row[penalty_col])
    rigid_penalty = rigid_penalty_gpu_h * gpu_hours_per_mwh_it
    flex_penalty = flex_penalty_gpu_h * gpu_hours_per_mwh_it
    flex_delay_h = int(flex_task_row["max_delay_h"])
    terminal_flex_penalty = _resolve_terminal_penalty(config, flex_penalty)

    sea = bundle.sea_temperature.to_numpy(float)
    tau = float(bundle.cooling_params.get("thermal_time_constant", 0.0))
    temp_eff = effective_temperature(sea, dt, tau)
    curves = build_piecewise_curves(
        temp_eff, bundle.it_params, bundle.cooling_params, B
    )
    widths = curves["segment_widths"]
    slopes = curves["slopes"]
    base_pdc = curves["facility_power_breakpoints"][:, 0]

    elec_price = power["electricity_price_yuan_per_mwh"].to_numpy(float)
    cap = power["dc_power_cap_mw"].to_numpy(float)
    if (elec_price < 0).any():
        raise ValueError("当前连续增量分段线性化要求电价非负；检测到负电价。")

    # 基础设施功率是唯一不可削减的硬边界。
    base_tol = float(config.get("base_power_hard_tolerance_mw", 1e-6))
    base_short = base_pdc - cap
    bad = np.flatnonzero(base_short > base_tol)
    if bad.size:
        examples = ", ".join(
            f"t={int(t)}: 可用{cap[t]:.4f}MW < 基础{base_pdc[t]:.4f}MW"
            for t in bad[:8]
        )
        raise RuntimeError(
            "DC基础设施供电硬约束不满足，机房无法维持基本运行。"
            f"异常时段{bad.size}个；示例：{examples}。"
            "应由外部能源/储能模块保证至少提供dc_base_power_mw。"
        )

    variable_om_rate = float(config.get("variable_om_yuan_per_mwh_it", 0.0))

    # 第三级经济目标：最大化收入-电费-各类违约-可变运维。
    economic_c = np.zeros(idx.n)
    economic_c[idx.xr] = -rigid_price + variable_om_rate
    economic_c[idx.ur] = rigid_penalty
    economic_c[idx.xf] = -flex_price + variable_om_rate
    economic_c[idx.vf] = flex_penalty
    economic_c[idx.xs] = -spot_price + variable_om_rate
    economic_c[idx.q[-1]] += terminal_flex_penalty
    for t in range(T):
        economic_c[idx.y[t, :]] = elec_price[t] * dt * slopes[t, :]

    bounds: list[tuple[float | None, float | None]] = [(0.0, None)] * idx.n
    for t in range(T):
        bounds[idx.xr[t]] = (0.0, rigid_arrival[t] * dt)
        bounds[idx.ur[t]] = (0.0, rigid_arrival[t] * dt)
        bounds[idx.xf[t]] = (0.0, None)
        bounds[idx.q[t]] = (0.0, None)
        bounds[idx.vf[t]] = (0.0, None)
        bounds[idx.xs[t]] = (0.0, spot_demand[t] * dt)
        for b in range(B):
            bounds[idx.y[t, b]] = (0.0, widths[b])

    # 等式：刚性任务守恒、柔性队列守恒、服务量与分段变量映射。
    # 默认不再强制168小时期末队列为0；期末剩余任务按违约处罚。
    hard_terminal = bool(config.get("enforce_terminal_flex_queue", False))
    eq_rows = 3 * T + (1 if hard_terminal else 0)
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
        r += 1

    if hard_terminal:
        Aeq[r, idx.q[-1]] = 1.0
        beq[r] = 0.0

    # 不等式：光纤容量、DC可用功率上限、柔性任务软SLA期限。
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

    # 到时段t，已经到期的柔性任务应完成；未完成量进入vf[t]并承担SLA惩罚。
    # sum(xf[0:t]) + vf[t] >= sum(arrival[0:t-L])
    for t in range(flex_delay_h, T):
        for j in range(t + 1):
            Aub[r, idx.xf[j]] = -1.0
        Aub[r, idx.vf[t]] = -1.0
        required = float(np.sum(flex_arrival[: t - flex_delay_h + 1]) * dt)
        bub[r] = -required
        r += 1

    Aeq_csr = csr_matrix(Aeq)
    Aub_csr = csr_matrix(Aub)

    options = {
        "presolve": True,
        "primal_feasibility_tolerance": float(
            config.get("solver_primal_tolerance", 1e-8)
        ),
        "dual_feasibility_tolerance": float(
            config.get("solver_dual_tolerance", 1e-8)
        ),
    }
    lex_abs_tol = float(config.get("lexicographic_tolerance", 1e-8))
    lex_rel_tol = float(config.get("lexicographic_relative_tolerance", 1e-9))

    def lex_limit(value: float) -> float:
        # 大规模SLA目标可能达到1e8~1e9元，纯绝对容差会造成HiGHS数值不可行。
        return value + max(lex_abs_tol, abs(value) * lex_rel_tol)

    # 一级：刚性任务绝对优先，先求最小刚性缺供。
    rigid_priority_c = np.zeros(idx.n)
    rigid_priority_c[idx.ur] = 1.0
    stage1 = _solve_lp(
        rigid_priority_c,
        Aub_csr,
        bub,
        Aeq_csr,
        beq,
        bounds,
        options,
        "一级（刚性任务）",
    )
    Aub_stage2 = vstack([Aub_csr, csr_matrix(rigid_priority_c.reshape(1, -1))])
    bub_stage2 = np.append(bub, lex_limit(float(stage1.fun)))

    # 二级：不恶化刚性服务的前提下，优先消除柔性超期并尽快清队列。
    flex_priority_c = np.zeros(idx.n)
    flex_priority_c[idx.vf] = flex_penalty
    queue_carry_cost = float(config.get("flex_queue_priority_weight", 1.0))
    flex_priority_c[idx.q] = queue_carry_cost
    flex_priority_c[idx.q[-1]] += terminal_flex_penalty
    stage2 = _solve_lp(
        flex_priority_c,
        csr_matrix(Aub_stage2),
        bub_stage2,
        Aeq_csr,
        beq,
        bounds,
        options,
        "二级（柔性任务）",
    )
    Aub_stage3 = vstack(
        [Aub_stage2, csr_matrix(flex_priority_c.reshape(1, -1))]
    )
    bub_stage3 = np.append(bub_stage2, lex_limit(float(stage2.fun)))

    # 三级：刚性和柔性最优值固定后，才允许可选任务利用剩余电力并优化收益。
    result = _solve_lp(
        economic_c,
        csr_matrix(Aub_stage3),
        bub_stage3,
        Aeq_csr,
        beq,
        bounds,
        options,
        "三级（经济性与弹性任务）",
    )

    z = result.x
    xr = z[idx.xr]
    ur = z[idx.ur]
    xf = z[idx.xf]
    q = z[idx.q]
    vf = z[idx.vf]
    xs = z[idx.xs]
    y = z[idx.y]

    service_rate = y.sum(axis=1)
    p_it, p_cool, p_dc_exact, pue_exact = facility_power(
        service_rate, temp_eff, bundle.it_params, bundle.cooling_params
    )
    p_dc_pwl = base_pdc + np.sum(slopes * y, axis=1)

    electricity_cost = p_dc_exact * dt * elec_price
    rigid_revenue = xr * rigid_price
    flex_revenue = xf * flex_price
    spot_revenue = xs * spot_price
    rigid_sla_penalty = ur * rigid_penalty
    flex_sla_penalty = vf * flex_penalty
    flex_terminal_penalty = np.zeros(T)
    flex_terminal_penalty[-1] = q[-1] * terminal_flex_penalty
    total_sla_penalty = (
        rigid_sla_penalty + flex_sla_penalty + flex_terminal_penalty
    )
    variable_om = (xr + xf + xs) * variable_om_rate
    margin = (
        rigid_revenue
        + flex_revenue
        + spot_revenue
        - electricity_cost
        - total_sla_penalty
        - variable_om
    )
    spot_dropped = spot_demand * dt - xs

    hourly = pd.DataFrame(
        {
            "timestamp": w["timestamp"],
            "dc_operational": np.ones(T, dtype=int),
            "dc_base_power_mw": base_pdc,
            "dc_available_power_mw": cap,
            "dc_power_headroom_mw": cap - p_dc_exact,
            "rigid_arrival_mwh_it": rigid_arrival * dt,
            "flex_arrival_mwh_it": flex_arrival * dt,
            "spot_demand_mwh_it": spot_demand * dt,
            "rigid_served_mwh_it": xr,
            "rigid_unserved_mwh_it": ur,
            "flex_served_mwh_it": xf,
            "flex_queue_mwh_it": q,
            "flex_sla_overdue_mwh_it": vf,
            "spot_served_mwh_it": xs,
            "spot_dropped_mwh_it": spot_dropped,
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
            # 保留旧列名，兼容现有报告和桥接代码。
            "dc_power_cap_mw": cap,
            "electricity_price_yuan_per_mwh": elec_price,
            "rigid_revenue_yuan": rigid_revenue,
            "flex_revenue_yuan": flex_revenue,
            "spot_revenue_yuan": spot_revenue,
            "electricity_cost_yuan": electricity_cost,
            "rigid_sla_penalty_yuan": rigid_sla_penalty,
            "flex_sla_penalty_yuan": flex_sla_penalty,
            "flex_terminal_penalty_yuan": flex_terminal_penalty,
            "total_sla_penalty_yuan": total_sla_penalty,
            # 旧列名改为总SLA惩罚，避免下游漏算柔性违约。
            "unmet_penalty_yuan": total_sla_penalty,
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

    deadline_violation = np.zeros(T)
    for t in range(flex_delay_h, T):
        required = float(np.sum(flex_arrival[: t - flex_delay_h + 1]) * dt)
        deadline_violation[t] = max(0.0, required - np.sum(xf[: t + 1]) - vf[t])

    audit = {
        "max_rigid_balance_residual": float(np.max(np.abs(rigid_resid))),
        "max_flex_queue_residual": float(np.max(np.abs(queue_resid))),
        "max_service_mapping_residual": float(np.max(np.abs(service_resid))),
        "max_flex_soft_deadline_violation_mwh_it": float(
            np.max(deadline_violation)
        ),
        "max_piecewise_power_error_mw": float(
            np.max(np.abs(p_dc_pwl - p_dc_exact))
        ),
        "max_power_cap_violation_mw": float(
            np.max(np.maximum(p_dc_exact - cap, 0.0))
        ),
        "max_base_power_shortfall_mw": float(np.max(np.maximum(base_pdc - cap, 0.0))),
        "max_fiber_capacity_violation_mw_it": float(
            np.max(np.maximum(service_rate - capacity * fiber, 0.0))
        ),
        "terminal_flex_queue_mwh_it": float(q[-1]),
        "terminal_queue_is_soft_violation": not hard_terminal,
        "stage1_min_rigid_unserved_mwh_it": float(stage1.fun),
        "stage2_flex_priority_objective": float(stage2.fun),
    }
    audit["passed"] = bool(
        audit["max_rigid_balance_residual"] <= tol
        and audit["max_flex_queue_residual"] <= tol
        and audit["max_service_mapping_residual"] <= tol
        and audit["max_flex_soft_deadline_violation_mwh_it"] <= tol
        and audit["max_power_cap_violation_mw"]
        <= max(tol, audit["max_piecewise_power_error_mw"] + tol)
        and audit["max_base_power_shortfall_mw"] <= base_tol
        and audit["max_fiber_capacity_violation_mw_it"] <= tol
        and (not hard_terminal or audit["terminal_flex_queue_mwh_it"] <= tol)
    )

    total_contract_arrival = np.sum(rigid_arrival + flex_arrival) * dt
    summary = {
        "hours": T,
        "it_capacity_mw": capacity,
        "workload_scale": scale,
        "spot_workload_scale": spot_scale,
        "dispatch_priority": (
            "lexicographic: rigid service -> flexible SLA/queue -> economics/optional"
        ),
        "base_power_is_hard_constraint": True,
        "equivalent_gpu_it_power_kw": equivalent_gpu_it_power_kw,
        "gpu_hours_per_mwh_it": gpu_hours_per_mwh_it,
        "rigid_price_yuan_per_gpu_h": rigid_price_gpu_h,
        "flex_price_yuan_per_gpu_h": flex_price_gpu_h,
        "spot_price_yuan_per_gpu_h": spot_price_gpu_h,
        "rigid_penalty_yuan_per_gpu_h": rigid_penalty_gpu_h,
        "flex_penalty_yuan_per_gpu_h": flex_penalty_gpu_h,
        "terminal_flex_penalty_yuan_per_mwh_it": terminal_flex_penalty,
        "rigid_price_yuan_per_mwh_it_equivalent": rigid_price,
        "flex_price_yuan_per_mwh_it_equivalent": flex_price,
        "spot_price_source": spot_price_source,
        "total_rigid_arrival_mwh_it": float(np.sum(rigid_arrival) * dt),
        "total_rigid_served_mwh_it": float(np.sum(xr)),
        "total_rigid_unserved_mwh_it": float(np.sum(ur)),
        "total_flex_arrival_mwh_it": float(np.sum(flex_arrival) * dt),
        "total_flex_served_mwh_it": float(np.sum(xf)),
        "terminal_flex_unfinished_mwh_it": float(q[-1]),
        "total_flex_overdue_exposure_mwh_it_h": float(np.sum(vf) * dt),
        "total_spot_demand_mwh_it": float(np.sum(spot_demand) * dt),
        "total_spot_served_mwh_it": float(np.sum(xs)),
        "total_spot_dropped_mwh_it": float(np.sum(spot_dropped)),
        "total_rigid_gpu_hours": float(np.sum(xr) * gpu_hours_per_mwh_it),
        "total_flex_gpu_hours": float(np.sum(xf) * gpu_hours_per_mwh_it),
        "total_spot_gpu_hours": float(np.sum(xs) * gpu_hours_per_mwh_it),
        "total_gpu_hours": float(np.sum(xr + xf + xs) * gpu_hours_per_mwh_it),
        "contract_service_rate": float(
            (np.sum(xr) + np.sum(xf)) / max(total_contract_arrival, 1e-12)
        ),
        "average_it_load_ratio": float(np.mean(service_rate / capacity)),
        "peak_it_service_rate_mw_it": float(np.max(service_rate)),
        "minimum_dc_base_power_mw": float(np.min(base_pdc)),
        "maximum_dc_base_power_mw": float(np.max(base_pdc)),
        "total_it_energy_mwh": float(np.sum(p_it) * dt),
        "total_cooling_energy_mwh": float(np.sum(p_cool) * dt),
        "total_dc_energy_mwh": float(np.sum(p_dc_exact) * dt),
        "average_pue": float(np.sum(p_dc_exact) / np.sum(p_it)),
        "min_pue": float(np.min(pue_exact)),
        "max_pue": float(np.max(pue_exact)),
        "total_compute_revenue_yuan": float(
            np.sum(rigid_revenue + flex_revenue + spot_revenue)
        ),
        "total_electricity_cost_yuan": float(np.sum(electricity_cost)),
        "total_rigid_sla_penalty_yuan": float(np.sum(rigid_sla_penalty)),
        "total_flex_sla_penalty_yuan": float(np.sum(flex_sla_penalty)),
        "total_flex_terminal_penalty_yuan": float(
            np.sum(flex_terminal_penalty)
        ),
        "total_unmet_penalty_yuan": float(np.sum(total_sla_penalty)),
        "electricity_contribution_margin_yuan": float(np.sum(margin)),
        "note": (
            "该利润为算力收入扣除电费、刚性/柔性SLA惩罚、168小时期末"
            "未完成惩罚和可变运维后的电力边际贡献，不含CAPEX、折旧及完整运维。"
        ),
    }

    solver = {
        "success": bool(result.success),
        "status": int(result.status),
        "message": str(result.message),
        "solver_method": "HiGHS LP, three-stage lexicographic optimization",
        "stage1_min_rigid_unserved_mwh_it": float(stage1.fun),
        "stage2_flex_priority_objective": float(stage2.fun),
        "stage3_economic_objective_minimized_yuan": float(result.fun),
        "iterations_stage1": int(getattr(stage1, "nit", 0)),
        "iterations_stage2": int(getattr(stage2, "nit", 0)),
        "iterations_stage3": int(getattr(result, "nit", 0)),
    }

    return ModelResult(hourly=hourly, summary=summary, solver=solver, audit=audit)
