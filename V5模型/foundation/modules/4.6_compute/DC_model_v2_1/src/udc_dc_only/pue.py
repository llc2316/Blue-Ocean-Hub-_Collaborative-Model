from __future__ import annotations

import math
import numpy as np


def effective_temperature(sea_temperature_c: np.ndarray, dt_h: float, tau_h: float) -> np.ndarray:
    """一阶低通表示冷却回路对海温变化的热惯性。"""
    sea = np.asarray(sea_temperature_c, dtype=float)
    if tau_h <= 0:
        return sea.copy()
    alpha = math.exp(-dt_h / tau_h)
    out = np.empty_like(sea)
    out[0] = sea[0]
    for t in range(1, len(sea)):
        out[t] = alpha * out[t - 1] + (1.0 - alpha) * sea[t]
    return out


def facility_power(
    service_rate_mw_it: np.ndarray | float,
    sea_temperature_c: np.ndarray | float,
    it_params: dict,
    cooling_params: dict,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """返回 IT功率、冷却功率、设施总功率和PUE。"""
    service = np.asarray(service_rate_mw_it, dtype=float)
    temp = np.asarray(sea_temperature_c, dtype=float)
    capacity = float(it_params["it_capacity"])
    idle = float(it_params["idle_power_ratio"])
    exponent = float(it_params.get("power_curve_exponent", 1.0))
    efficiency = float(it_params["distribution_efficiency"])
    load_ratio = np.clip(service / capacity, 0.0, 1.0)
    p_it = capacity * (idle + (1.0 - idle) * np.power(load_ratio, exponent))

    ref_temp = float(cooling_params["reference_sea_temperature"])
    raw_cooling = (
        float(cooling_params["cooling_fixed_power"])
        + float(cooling_params["cooling_linear_coeff"]) * p_it
        + float(cooling_params["cooling_quadratic_coeff"]) * p_it**2
        + float(cooling_params["temperature_coefficient"]) * p_it * (temp - ref_temp)
    )
    p_cooling = np.maximum(float(cooling_params.get("cooling_power_min", 0.0)), raw_cooling)
    p_aux = float(cooling_params["fixed_auxiliary_power"])
    p_dc = (p_it + p_cooling + p_aux) / efficiency
    pue = p_dc / np.maximum(p_it, 1e-9)
    return p_it, p_cooling, p_dc, pue


def build_piecewise_curves(
    sea_temperature_c: np.ndarray,
    it_params: dict,
    cooling_params: dict,
    segments: int,
) -> dict[str, np.ndarray]:
    capacity = float(it_params["it_capacity"])
    service_breakpoints = np.linspace(0.0, capacity, segments + 1)
    width = np.diff(service_breakpoints)
    all_power = []
    all_slopes = []
    all_pit = []
    all_cooling = []
    all_pue = []
    for temp in np.asarray(sea_temperature_c, dtype=float):
        pit, cool, pdc, pue = facility_power(service_breakpoints, temp, it_params, cooling_params)
        slopes = np.diff(pdc) / width
        if np.any(np.diff(slopes) < -1e-8):
            raise ValueError("设施功率曲线不是凸函数，不能使用当前连续增量分段线性化。")
        all_power.append(pdc)
        all_slopes.append(slopes)
        all_pit.append(pit)
        all_cooling.append(cool)
        all_pue.append(pue)
    return {
        "breakpoints": service_breakpoints,
        "segment_widths": width,
        "facility_power_breakpoints": np.asarray(all_power),
        "slopes": np.asarray(all_slopes),
        "it_power_breakpoints": np.asarray(all_pit),
        "cooling_power_breakpoints": np.asarray(all_cooling),
        "pue_breakpoints": np.asarray(all_pue),
    }
