from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd

from .data_loader import InputBundle
from .pue import effective_temperature, facility_power


@dataclass
class ModelResult:
    hourly: pd.DataFrame
    summary: dict[str, Any]
    solver: dict[str, Any]
    audit: dict[str, Any]


def _price_row(df: pd.DataFrame, name: str) -> float:
    rows = df.loc[df["task_type"] == name]
    if rows.empty:
        raise ValueError(f"compute_price.csv 缺少 {name}")
    return float(rows.iloc[0]["price_yuan_per_gpu_h"])


def _resolve_timestamp(
    bundle: InputBundle,
    config: dict[str, Any],
    periods: int,
) -> pd.Series:
    """优先使用功率接口时间轴，其次使用原工作负载表时间轴。

    raw_model不读取任务到达量；workload仅在缺少功率时间戳时作为时间轴后备。
    """
    if "timestamp" in bundle.power.columns:
        ts = pd.to_datetime(bundle.power["timestamp"], errors="coerce")
        if len(ts) == periods and ts.notna().all():
            return pd.Series(ts)

    if hasattr(bundle, "workload") and "timestamp" in bundle.workload.columns:
        ts = pd.to_datetime(bundle.workload["timestamp"], errors="coerce")
        if len(ts) >= periods and ts.iloc[:periods].notna().all():
            return pd.Series(ts.iloc[:periods].to_numpy())

    start = pd.Timestamp(config.get("simulation_start", "2025-06-01 00:00:00"))
    return pd.Series(pd.date_range(start=start, periods=periods, freq="h"))


def _invert_facility_power(
    target_dc_power_mw: np.ndarray,
    max_service_rate_mw_it: np.ndarray,
    effective_sea_temperature_c: np.ndarray,
    it_params: dict[str, Any],
    cooling_params: dict[str, Any],
    iterations: int = 64,
) -> np.ndarray:
    """反求给定设施侧功率下可执行的最大IT服务率。

    facility_power关于service_rate单调增加，因此使用向量化二分法。
    """
    lo = np.zeros_like(target_dc_power_mw, dtype=float)
    hi = np.asarray(max_service_rate_mw_it, dtype=float).copy()

    for _ in range(iterations):
        mid = 0.5 * (lo + hi)
        _, _, p_dc_mid, _ = facility_power(
            mid,
            effective_sea_temperature_c,
            it_params,
            cooling_params,
        )
        feasible = p_dc_mid <= target_dc_power_mw
        lo = np.where(feasible, mid, lo)
        hi = np.where(feasible, hi, mid)

    return lo


def solve_dc_only(bundle: InputBundle, config: dict[str, Any]) -> ModelResult:
    """功率跟随型DC原始模型。

    模型不读取刚性/柔性/弹性任务到达表，也不建立任务队列和SLA约束。
    假设算力任务池始终充足，DC在以下边界内尽可能利用已分配电力：

    1. 外部可用功率低于DC基础设备功率时，DC无法维持运行；
    2. 外部可用功率高于基础功率时，剩余功率全部用于IT任务；
    3. 实际功率受外部功率上限、IT容量和设施最大功率共同限制；
    4. 当IT容量达到上限后，多余电力不再由DC消耗。
    """

    power = bundle.power.reset_index(drop=True)
    periods = len(power)
    if periods <= 0:
        raise ValueError("功率接口数据为空")

    dt = float(config.get("time_step_h", 1.0))
    if dt <= 0:
        raise ValueError("time_step_h必须大于0")

    task_input_mode = str(
        config.get("task_input_mode", "power_following")
    ).strip().lower()
    if task_input_mode != "power_following":
        raise ValueError(
            "raw_model仅支持task_input_mode='power_following'"
        )

    capacity = float(bundle.it_params["it_capacity"])
    if capacity <= 0:
        raise ValueError("it_capacity必须大于0")

    equivalent_gpu_it_power_kw = float(
        bundle.it_params["equivalent_gpu_it_power_kw"]
    )
    if equivalent_gpu_it_power_kw <= 0:
        raise ValueError("equivalent_gpu_it_power_kw必须大于0")
    gpu_hours_per_mwh_it = 1000.0 / equivalent_gpu_it_power_kw

    fiber = float(config.get("raw_fiber_availability", 1.0))
    if not 0.0 <= fiber <= 1.0:
        raise ValueError("raw_fiber_availability必须在[0,1]内")
    max_service_rate = np.full(periods, capacity * fiber, dtype=float)

    if "dc_power_cap_mw" not in power.columns:
        raise ValueError("功率接口缺少dc_power_cap_mw")
    if "electricity_price_yuan_per_mwh" not in power.columns:
        raise ValueError("功率接口缺少electricity_price_yuan_per_mwh")

    available_power = power["dc_power_cap_mw"].to_numpy(float)
    electricity_price = power[
        "electricity_price_yuan_per_mwh"
    ].to_numpy(float)

    if np.isnan(available_power).any() or np.isinf(available_power).any():
        raise ValueError("dc_power_cap_mw包含无效值")
    if (available_power < 0).any():
        raise ValueError("dc_power_cap_mw不能为负")
    if np.isnan(electricity_price).any() or np.isinf(electricity_price).any():
        raise ValueError("electricity_price_yuan_per_mwh包含无效值")
    if (electricity_price < 0).any():
        raise ValueError("当前raw_model要求电价非负")

    sea = np.asarray(bundle.sea_temperature, dtype=float)
    if len(sea) < periods:
        raise ValueError(
            f"海温数据长度不足：需要{periods}，实际{len(sea)}"
        )
    sea = sea[:periods]

    tau = float(bundle.cooling_params.get("thermal_time_constant", 0.0))
    temp_eff = effective_temperature(sea, dt, tau)

    zero_service = np.zeros(periods, dtype=float)
    (
        base_it_power,
        base_cooling_power,
        base_dc_power,
        base_pue,
    ) = facility_power(
        zero_service,
        temp_eff,
        bundle.it_params,
        bundle.cooling_params,
    )

    (
        max_it_power,
        max_cooling_power,
        max_dc_power,
        max_pue,
    ) = facility_power(
        max_service_rate,
        temp_eff,
        bundle.it_params,
        bundle.cooling_params,
    )

    base_tol = float(config.get("base_power_hard_tolerance_mw", 1e-6))
    base_shortfall = base_dc_power - available_power
    bad = np.flatnonzero(base_shortfall > base_tol)
    if bad.size:
        examples = ", ".join(
            f"t={int(t)}: 可用{available_power[t]:.4f}MW"
            f" < 基础{base_dc_power[t]:.4f}MW"
            for t in bad[:8]
        )
        raise RuntimeError(
            "DC基础设备供电不足，数据中心无法维持运行。"
            f"异常时段{bad.size}个；示例：{examples}"
        )

    # 目标设施功率：不能超过外部可供功率，也不能超过IT满载时的设施功率。
    target_dc_power = np.minimum(available_power, max_dc_power)

    service_rate = _invert_facility_power(
        target_dc_power_mw=target_dc_power,
        max_service_rate_mw_it=max_service_rate,
        effective_sea_temperature_c=temp_eff,
        it_params=bundle.it_params,
        cooling_params=bundle.cooling_params,
        iterations=int(config.get("raw_power_inverse_iterations", 64)),
    )

    it_power, cooling_power, dc_power, pue = facility_power(
        service_rate,
        temp_eff,
        bundle.it_params,
        bundle.cooling_params,
    )

    timestamp = _resolve_timestamp(bundle, config, periods)
    served_mwh_it = service_rate * dt

    raw_price_gpu_h = float(
        config.get(
            "raw_compute_price_yuan_per_gpu_h",
            _price_row(bundle.price_table, "rigid_inference"),
        )
    )
    raw_price_yuan_per_mwh_it = (
        raw_price_gpu_h * gpu_hours_per_mwh_it
    )

    compute_revenue = served_mwh_it * raw_price_yuan_per_mwh_it
    electricity_cost = dc_power * dt * electricity_price
    variable_om_rate = float(
        config.get("variable_om_yuan_per_mwh_it", 0.0)
    )
    variable_om = served_mwh_it * variable_om_rate
    margin = compute_revenue - electricity_cost - variable_om

    # raw_model没有外生任务到达量，也不计算未完成任务或SLA惩罚。
    zeros = np.zeros(periods, dtype=float)
    dc_headroom = available_power - dc_power
    capacity_headroom = max_service_rate - service_rate

    hourly = pd.DataFrame(
        {
            "timestamp": timestamp,
            "dc_operational": np.ones(periods, dtype=int),
            "task_input_mode": np.full(
                periods, "power_following", dtype=object
            ),
            "dc_base_power_mw": base_dc_power,
            "dc_available_power_mw": available_power,
            "dc_power_cap_mw": available_power,
            "dc_facility_max_power_mw": max_dc_power,
            "dc_power_headroom_mw": dc_headroom,
            "service_rate_mw_it": service_rate,
            "service_capacity_mw_it": max_service_rate,
            "service_capacity_headroom_mw_it": capacity_headroom,
            "raw_compute_served_mwh_it": served_mwh_it,
            # 以下兼容旧绘图和桥接代码。
            # 在raw模式中，“到达量”定义为当期实际接纳并执行的任务量，
            # 因此不存在外生未完成任务。
            "rigid_arrival_mwh_it": served_mwh_it,
            "rigid_served_mwh_it": served_mwh_it,
            "rigid_unserved_mwh_it": zeros,
            "flex_arrival_mwh_it": zeros,
            "flex_served_mwh_it": zeros,
            "flex_queue_mwh_it": zeros,
            "flex_sla_overdue_mwh_it": zeros,
            "spot_demand_mwh_it": zeros,
            "spot_served_mwh_it": zeros,
            "spot_dropped_mwh_it": zeros,
            "rigid_gpu_hours": served_mwh_it * gpu_hours_per_mwh_it,
            "flex_gpu_hours": zeros,
            "spot_gpu_hours": zeros,
            "total_gpu_hours": served_mwh_it * gpu_hours_per_mwh_it,
            "it_load_ratio": service_rate / capacity,
            "it_power_mw": it_power,
            "cooling_power_mw": cooling_power,
            "dc_power_mw": dc_power,
            "pue": pue,
            "sea_temperature_c": sea,
            "effective_sea_temperature_c": temp_eff,
            "electricity_price_yuan_per_mwh": electricity_price,
            "rigid_revenue_yuan": compute_revenue,
            "flex_revenue_yuan": zeros,
            "spot_revenue_yuan": zeros,
            "electricity_cost_yuan": electricity_cost,
            "rigid_sla_penalty_yuan": zeros,
            "flex_sla_penalty_yuan": zeros,
            "flex_terminal_penalty_yuan": zeros,
            "total_sla_penalty_yuan": zeros,
            "unmet_penalty_yuan": zeros,
            "variable_om_yuan": variable_om,
            "electricity_contribution_margin_yuan": margin,
        }
    )

    tol = float(config.get("audit_tolerance", 1e-6))
    max_cap_violation = float(
        np.max(np.maximum(dc_power - available_power, 0.0))
    )
    max_base_shortfall = float(
        np.max(np.maximum(base_dc_power - available_power, 0.0))
    )
    max_capacity_violation = float(
        np.max(np.maximum(service_rate - max_service_rate, 0.0))
    )
    max_target_error = float(
        np.max(np.abs(dc_power - target_dc_power))
    )

    audit = {
        "max_power_cap_violation_mw": max_cap_violation,
        "max_base_power_shortfall_mw": max_base_shortfall,
        "max_it_capacity_violation_mw_it": max_capacity_violation,
        "max_power_following_error_mw": max_target_error,
        "minimum_dc_power_headroom_mw": float(np.min(dc_headroom)),
        "passed": bool(
            max_cap_violation <= tol
            and max_base_shortfall <= max(base_tol, tol)
            and max_capacity_violation <= tol
        ),
    }

    total_dc_energy = float(np.sum(dc_power) * dt)
    total_it_energy = float(np.sum(it_power) * dt)
    average_pue = (
        total_dc_energy / total_it_energy
        if total_it_energy > 0
        else float("nan")
    )

    summary = {
        "hours": periods,
        "task_input_mode": "power_following",
        "task_arrival_table_used": False,
        "task_queue_used": False,
        "sla_penalty_used": False,
        "dispatch_rule": (
            "available power -> maintain DC base power -> "
            "use remaining power for compute until IT capacity"
        ),
        "base_power_is_hard_constraint": True,
        "it_capacity_mw": capacity,
        "raw_fiber_availability": fiber,
        "equivalent_gpu_it_power_kw": equivalent_gpu_it_power_kw,
        "gpu_hours_per_mwh_it": gpu_hours_per_mwh_it,
        "raw_compute_price_yuan_per_gpu_h": raw_price_gpu_h,
        "raw_compute_price_yuan_per_mwh_it_equivalent": (
            raw_price_yuan_per_mwh_it
        ),
        "total_compute_served_mwh_it": float(
            np.sum(served_mwh_it)
        ),
        "total_compute_gpu_hours": float(
            np.sum(served_mwh_it) * gpu_hours_per_mwh_it
        ),
        "average_it_load_ratio": float(
            np.mean(service_rate / capacity)
        ),
        "peak_it_service_rate_mw_it": float(
            np.max(service_rate)
        ),
        "minimum_dc_base_power_mw": float(
            np.min(base_dc_power)
        ),
        "maximum_dc_base_power_mw": float(
            np.max(base_dc_power)
        ),
        "minimum_dc_facility_max_power_mw": float(
            np.min(max_dc_power)
        ),
        "maximum_dc_facility_max_power_mw": float(
            np.max(max_dc_power)
        ),
        "total_it_energy_mwh": total_it_energy,
        "total_cooling_energy_mwh": float(
            np.sum(cooling_power) * dt
        ),
        "total_dc_energy_mwh": total_dc_energy,
        "average_pue": average_pue,
        "min_pue": float(np.min(pue)),
        "max_pue": float(np.max(pue)),
        "total_compute_revenue_yuan": float(
            np.sum(compute_revenue)
        ),
        "total_electricity_cost_yuan": float(
            np.sum(electricity_cost)
        ),
        "total_variable_om_yuan": float(
            np.sum(variable_om)
        ),
        "total_sla_penalty_yuan": 0.0,
        "electricity_contribution_margin_yuan": float(
            np.sum(margin)
        ),
        "note": (
            "raw_model不使用任务到达曲线、柔性队列和SLA惩罚。"
            "任务池假设始终充足，实际算力由外部可用功率、"
            "动态基础功率和IT容量共同决定。"
        ),
    }

    solver = {
        "success": True,
        "status": 0,
        "message": "Power-following solution completed.",
        "solver_method": (
            "Vectorized bisection inversion of facility power curve"
        ),
        "iterations": int(
            config.get("raw_power_inverse_iterations", 64)
        ),
    }

    return ModelResult(
        hourly=hourly,
        summary=summary,
        solver=solver,
        audit=audit,
    )
