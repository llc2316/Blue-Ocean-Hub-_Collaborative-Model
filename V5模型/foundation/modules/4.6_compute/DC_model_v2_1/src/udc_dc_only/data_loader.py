from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
import math

import h5py
import numpy as np
import pandas as pd


@dataclass
class InputBundle:
    workload: pd.DataFrame
    power: pd.DataFrame
    sea_temperature: pd.Series
    it_params: dict[str, Any]
    cooling_params: dict[str, float]
    task_params: pd.DataFrame
    price_table: pd.DataFrame
    warnings: list[str] = field(default_factory=list)
    diagnostics: dict[str, Any] = field(default_factory=dict)


def _normalise_timestamps(values: pd.Series | pd.Index) -> pd.DatetimeIndex:
    parsed = pd.to_datetime(values, errors="raise")
    if isinstance(parsed, pd.Series):
        if isinstance(parsed.dtype, pd.DatetimeTZDtype):
            return pd.DatetimeIndex(parsed.dt.tz_convert("Asia/Shanghai").dt.tz_localize(None))
        return pd.DatetimeIndex(parsed)
    idx = pd.DatetimeIndex(parsed)
    if idx.tz is not None:
        idx = idx.tz_convert("Asia/Shanghai").tz_localize(None)
    return idx


def _validate_hourly_index(index: pd.DatetimeIndex, label: str) -> None:
    if index.has_duplicates:
        raise ValueError(f"{label} 时间戳存在重复")
    if not index.is_monotonic_increasing:
        raise ValueError(f"{label} 时间戳不是严格递增")
    if len(index) > 1:
        delta = pd.Series(index[1:] - index[:-1])
        if not (delta == pd.Timedelta(hours=1)).all():
            bad = delta[delta != pd.Timedelta(hours=1)].head().tolist()
            raise ValueError(f"{label} 不是无缺口逐小时时序，异常间隔示例: {bad}")


def _read_parameter_table(path: Path) -> dict[str, Any]:
    df = pd.read_csv(path)
    if not {"parameter", "value"}.issubset(df.columns):
        raise ValueError(f"参数文件缺少 parameter/value 列: {path}")
    if df["parameter"].duplicated().any():
        dup = df.loc[df["parameter"].duplicated(), "parameter"].tolist()
        raise ValueError(f"参数名重复: {dup}")
    out: dict[str, Any] = {}
    for row in df.itertuples(index=False):
        key = str(getattr(row, "parameter"))
        raw = getattr(row, "value")
        try:
            value = float(raw)
            if math.isfinite(value) and float(value).is_integer():
                value = int(value)
            out[key] = value
        except (TypeError, ValueError):
            out[key] = str(raw)
    return out


def _load_workload(path: Path, config: dict[str, Any], warnings: list[str]) -> pd.DataFrame:
    df = pd.read_csv(path)
    required = {
        "timestamp",
        "rigid_compute_arrival",
        "flex_compute_arrival",
        "spot_compute_demand",
    }
    missing = sorted(required - set(df.columns))
    if missing:
        raise ValueError(f"工作负荷文件缺少字段: {missing}")

    raw_idx = _normalise_timestamps(df["timestamp"])
    _validate_hourly_index(raw_idx, "原始工作负荷")

    hours = int(config["simulation_hours"])
    if len(df) < hours:
        raise ValueError(f"老师工作负荷只有{len(df)}行，小于simulation_hours={hours}")
    if len(df) > hours:
        warnings.append(f"工作负荷共有{len(df)}行，模型仅使用前{hours}行。")
        df = df.iloc[:hours].copy()
        raw_idx = raw_idx[:hours]
    else:
        df = df.copy()

    if bool(config.get("rebase_workload_timestamps", True)):
        start = pd.Timestamp(config["simulation_start"])
        idx = pd.date_range(start=start, periods=hours, freq="h")
        warnings.append(
            "老师168小时任务曲线仅作为相对时序形状使用，已自动映射到"
            f"{idx[0]}至{idx[-1]}；任务数值未修改。"
        )
    else:
        idx = raw_idx

    df["timestamp"] = idx
    for col in ["rigid_compute_arrival", "flex_compute_arrival", "spot_compute_demand"]:
        x = pd.to_numeric(df[col], errors="coerce")
        if x.isna().any() or np.isinf(x).any() or (x < 0).any():
            raise ValueError(f"工作负荷字段 {col} 含空值、无穷值或负值")
        df[col] = x.astype(float)

    if "fiber_availability" not in df:
        df["fiber_availability"] = 1.0
    fiber = pd.to_numeric(df["fiber_availability"], errors="coerce")
    if fiber.isna().any() or ((fiber < 0) | (fiber > 1)).any():
        raise ValueError("fiber_availability 必须位于[0,1]")
    df["fiber_availability"] = fiber.astype(float)

    if "spot_compute_price" in df:
        df["spot_compute_price"] = pd.to_numeric(df["spot_compute_price"], errors="coerce")
    return df


def _load_power_interface(
    economics_dir: Path,
    workload_index: pd.DatetimeIndex,
    config: dict[str, Any],
    warnings: list[str],
) -> pd.DataFrame:
    mode = str(config.get("power_interface_mode", "constant"))
    if mode == "constant":
        price = float(config["constant_electricity_price_yuan_per_mwh"])
        cap = float(config["constant_dc_power_cap_mw"])
        if price < 0 or cap < 0:
            raise ValueError("常量电价和DC功率上限不能为负")
        warnings.append(
            f"未使用逐时power_interface.csv；仿真期统一采用月度综合电价{price:.2f}元/MWh"
            f"和DC功率上限{cap:.2f}MW。"
        )
        return pd.DataFrame(
            {
                "timestamp": workload_index,
                "dc_power_cap_mw": cap,
                "electricity_price_yuan_per_mwh": price,
            }
        )

    path = economics_dir / "power_interface.csv"
    if not path.exists():
        raise FileNotFoundError("power_interface_mode=file，但未找到power_interface.csv")
    df = pd.read_csv(path)
    required = {"timestamp", "dc_power_cap_mw", "electricity_price_yuan_per_mwh"}
    missing = sorted(required - set(df.columns))
    if missing:
        raise ValueError(f"电力接口文件缺少字段: {missing}")
    idx = _normalise_timestamps(df["timestamp"])
    df = df.copy()
    df["timestamp"] = idx
    for col in ["dc_power_cap_mw", "electricity_price_yuan_per_mwh"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
        if df[col].isna().any() or np.isinf(df[col]).any() or (df[col] < 0).any():
            raise ValueError(f"电力接口字段 {col} 含空值、无穷值或负值")
    if len(df) != len(workload_index):
        raise ValueError(
            f"file模式要求power_interface.csv与仿真期同长度；当前{len(df)}行，期望{len(workload_index)}行。"
        )
    out = df.drop(columns="timestamp").copy()
    out.insert(0, "timestamp", workload_index)
    return out


def _decode_time(time_ds: h5py.Dataset) -> pd.DatetimeIndex:
    units = time_ds.attrs.get("units", b"")
    if isinstance(units, bytes):
        units = units.decode("utf-8", errors="ignore")
    units = str(units)
    values = np.asarray(time_ds[:], dtype=float)
    if "seconds since 1970-01-01" in units:
        times = pd.to_datetime(values, unit="s", utc=True)
    elif "hours since 1950-01-01" in units:
        times = pd.Timestamp("1950-01-01", tz="UTC") + pd.to_timedelta(values, unit="h")
    elif "days since 1950-01-01" in units:
        times = pd.Timestamp("1950-01-01", tz="UTC") + pd.to_timedelta(values, unit="D")
    else:
        raise ValueError(f"暂不支持的NetCDF时间单位: {units}")
    return pd.DatetimeIndex(times).tz_convert("Asia/Shanghai").tz_localize(None)


def _extract_nc_temperature(
    path: Path,
    target_lon: float,
    target_lat: float,
    target_depth_m: float,
) -> tuple[pd.Series, dict[str, Any]]:
    with h5py.File(path, "r") as f:
        required = {"thetao", "time", "depth", "latitude", "longitude"}
        missing = required - set(f.keys())
        if missing:
            raise ValueError(f"NetCDF缺少变量: {sorted(missing)}")

        theta = np.asarray(f["thetao"][:], dtype=float)
        if theta.ndim != 4:
            raise ValueError(f"thetao期望维度(time,depth,lat,lon)，实际shape={theta.shape}")
        times = _decode_time(f["time"])
        depths = np.asarray(f["depth"][:], dtype=float).reshape(-1)
        lats = np.asarray(f["latitude"][:], dtype=float).reshape(-1)
        lons = np.asarray(f["longitude"][:], dtype=float).reshape(-1)

        # 先按目标深度接近程度搜索；每个深度层中选择距离目标坐标最近且有有效数据的海洋格点。
        chosen: tuple[int, int, int] | None = None
        chosen_coverage = -1
        chosen_score = float("inf")
        for zi in np.argsort(np.abs(depths - target_depth_m)):
            layer = theta[:, zi, :, :]
            coverage = np.isfinite(layer).sum(axis=0)
            ys, xs = np.where(coverage > 0)
            for yi, xi in zip(ys, xs):
                # 经度按纬度余弦修正，形成近似平面距离；另加入轻微深度偏差惩罚。
                dx = (lons[xi] - target_lon) * math.cos(math.radians(target_lat))
                dy = lats[yi] - target_lat
                horizontal_score = dx * dx + dy * dy
                depth_score = ((depths[zi] - target_depth_m) / 100.0) ** 2
                score = horizontal_score + depth_score
                cov = int(coverage[yi, xi])
                if score < chosen_score - 1e-12 or (abs(score - chosen_score) <= 1e-12 and cov > chosen_coverage):
                    chosen = (int(zi), int(yi), int(xi))
                    chosen_score = score
                    chosen_coverage = cov
            if chosen is not None and abs(depths[chosen[0]] - target_depth_m) <= abs(depths[zi] - target_depth_m):
                # 已在当前最近深度层找到有效格点，无需搜索更远深度。
                break

        if chosen is None:
            raise ValueError("NetCDF区域内所有thetao格点均无有效值")
        zi, yi, xi = chosen
        values = theta[:, zi, yi, xi]
        series = pd.Series(values, index=times, name="sea_temperature_c").sort_index()
        diag = {
            "file": str(path),
            "thetao_shape": list(theta.shape),
            "selected_longitude": float(lons[xi]),
            "selected_latitude": float(lats[yi]),
            "selected_depth_m": float(depths[zi]),
            "target_longitude": float(target_lon),
            "target_latitude": float(target_lat),
            "target_depth_m": float(target_depth_m),
            "valid_temperature_count": int(np.isfinite(values).sum()),
            "total_temperature_count": int(values.size),
            "available_time_start": str(times.min()),
            "available_time_end": str(times.max()),
        }
        return series, diag


def _align_sea_temperature(
    cooling_dir: Path,
    workload_index: pd.DatetimeIndex,
    config: dict[str, Any],
    cooling_params: dict[str, float],
    warnings: list[str],
    diagnostics: dict[str, Any],
) -> pd.Series:
    fallback = float(config.get("fallback_sea_temperature_c", cooling_params.get("reference_sea_temperature", 23.5)))
    allow_fallback = bool(config.get("allow_invalid_sea_temperature_fallback", False))
    csv_path = cooling_dir / "sea_temperature.csv"

    if csv_path.exists():
        df = pd.read_csv(csv_path)
        if not {"timestamp", "sea_temperature_c"}.issubset(df.columns):
            raise ValueError("sea_temperature.csv 缺少 timestamp/sea_temperature_c")
        idx = _normalise_timestamps(df["timestamp"])
        values = pd.to_numeric(df["sea_temperature_c"], errors="coerce")
        raw = pd.Series(values.to_numpy(float), index=idx).sort_index()
        diagnostics["sea_temperature_source"] = str(csv_path)
    else:
        nc_files = sorted(cooling_dir.glob("*.nc"))
        if not nc_files:
            if not allow_fallback:
                raise FileNotFoundError("没有sea_temperature.csv或Copernicus NetCDF海温文件")
            warnings.append(f"未找到海温数据，使用常数回退值 {fallback:.2f}°C。")
            diagnostics["sea_temperature_source"] = "constant_fallback"
            diagnostics["sea_temperature_fallback_used"] = True
            return pd.Series(fallback, index=workload_index, name="sea_temperature_c")
        if len(nc_files) > 1:
            warnings.append(f"冷却目录存在{len(nc_files)}个NetCDF，已读取按文件名排序后的第一个: {nc_files[0].name}")
        try:
            raw, nc_diag = _extract_nc_temperature(
                nc_files[0],
                float(config.get("sea_target_longitude", 113.0)),
                float(config.get("sea_target_latitude", 21.2)),
                float(config.get("sea_target_depth_m", 50.0)),
            )
            diagnostics["sea_temperature_netcdf"] = nc_diag
            diagnostics["sea_temperature_source"] = str(nc_files[0])
        except Exception as exc:
            if not allow_fallback:
                raise
            warnings.append(f"NetCDF海温读取失败: {exc}；使用{fallback:.2f}°C回退。")
            diagnostics["sea_temperature_fallback_used"] = True
            return pd.Series(fallback, index=workload_index, name="sea_temperature_c")

    valid = raw.replace([np.inf, -np.inf], np.nan).dropna()
    if valid.empty:
        if not allow_fallback:
            raise ValueError("海温数据全部为空值")
        warnings.append(f"海温数据全部为空，使用{fallback:.2f}°C回退。")
        diagnostics["sea_temperature_fallback_used"] = True
        return pd.Series(fallback, index=workload_index, name="sea_temperature_c")

    # 日均海温视为当天00:00代表值，再线性插值到小时。原始21天文件无需手工裁剪。
    daily = valid.groupby(valid.index.normalize()).mean().sort_index()
    target_start = workload_index.min().normalize()
    target_end = workload_index.max().normalize()
    if daily.index.max() < target_start or daily.index.min() > target_end:
        raise ValueError(
            f"海温日期{daily.index.min().date()}~{daily.index.max().date()}不覆盖仿真期"
            f"{target_start.date()}~{target_end.date()}。请修改simulation_start或更换NetCDF。"
        )

    hourly_target = workload_index
    combined = daily.reindex(daily.index.union(hourly_target)).sort_index().interpolate(method="time").ffill().bfill()
    aligned = combined.reindex(hourly_target).astype(float)
    aligned.name = "sea_temperature_c"

    diagnostics["sea_temperature_fallback_used"] = False
    diagnostics["sea_temperature_valid_min_c"] = float(valid.min())
    diagnostics["sea_temperature_valid_max_c"] = float(valid.max())
    diagnostics["sea_temperature_used_min_c"] = float(aligned.min())
    diagnostics["sea_temperature_used_max_c"] = float(aligned.max())
    diagnostics["simulation_start"] = str(workload_index.min())
    diagnostics["simulation_end"] = str(workload_index.max())
    return aligned


def load_inputs(data_root: str | Path, config: dict[str, Any]) -> InputBundle:
    root = Path(data_root)
    warnings: list[str] = []
    diagnostics: dict[str, Any] = {}

    workload_path = root / "01_Workload" / "green_compute_v1_168h.csv"
    task_path = root / "01_Workload" / "task_type_parameters.csv"
    it_path = root / "02_IT_System" / "it_system_parameters.csv"
    cooling_path = root / "03_Cooling_PUE" / "cooling_parameters.csv"
    price_path = root / "04_Economics_Interface" / "compute_price.csv"
    required_files = [workload_path, task_path, it_path, cooling_path, price_path]
    missing = [str(p) for p in required_files if not p.exists()]
    if missing:
        raise FileNotFoundError("缺少必要输入文件:\n" + "\n".join(missing))

    workload = _load_workload(workload_path, config, warnings)
    workload_index = pd.DatetimeIndex(workload["timestamp"])
    power = _load_power_interface(root / "04_Economics_Interface", workload_index, config, warnings)
    it_params = _read_parameter_table(it_path)
    cooling_params_raw = _read_parameter_table(cooling_path)
    cooling_params = {k: float(v) for k, v in cooling_params_raw.items() if isinstance(v, (int, float))}
    task_params = pd.read_csv(task_path)
    price_table = pd.read_csv(price_path)

    if "equivalent_gpu_it_power_kw" not in it_params:
        if "equivalent_resource_count" in it_params:
            capacity = float(it_params["it_capacity"])
            count = float(it_params["equivalent_resource_count"])
            it_params["equivalent_gpu_it_power_kw"] = 1000.0 * capacity / count
            warnings.append(
                "it_system_parameters.csv仍使用equivalent_resource_count；已兼容换算为"
                f"equivalent_gpu_it_power_kw={it_params['equivalent_gpu_it_power_kw']:.4f}。"
                "建议后续直接改用等效GPU完整IT功率参数。"
            )
        else:
            raise ValueError("it_system_parameters.csv缺少 equivalent_gpu_it_power_kw")

    if "price_yuan_per_gpu_h" not in price_table.columns:
        if "price_yuan_per_resource_h" in price_table.columns:
            price_table = price_table.rename(columns={"price_yuan_per_resource_h": "price_yuan_per_gpu_h"})
            warnings.append("compute_price.csv旧列名price_yuan_per_resource_h已按等效GPU·h兼容读取，建议改名为price_yuan_per_gpu_h。")
        else:
            raise ValueError("compute_price.csv缺少 price_yuan_per_gpu_h")

    sea_temperature = _align_sea_temperature(
        root / "03_Cooling_PUE",
        workload_index,
        config,
        cooling_params,
        warnings,
        diagnostics,
    )

    if (root / "01_Workload" / "trace_seren.csv").exists():
        warnings.append("trace_seren.csv为作业级轨迹，当前聚合LP不读取；保留给连续训练任务MILP扩展。")
    if "continuous_training" in set(task_params.get("task_type", [])):
        warnings.append("continuous_training参数已保留，但老师聚合时序没有连续作业字段，当前版本不启用该任务类型。")

    diagnostics["workload_rows"] = len(workload)
    diagnostics["workload_start"] = str(workload_index.min())
    diagnostics["workload_end"] = str(workload_index.max())
    diagnostics["power_mode"] = config.get("power_interface_mode")
    diagnostics["power_rows_after_alignment"] = len(power)
    diagnostics["equivalent_gpu_it_power_kw"] = float(it_params["equivalent_gpu_it_power_kw"])
    diagnostics["gpu_hours_per_mwh_it"] = 1000.0 / float(it_params["equivalent_gpu_it_power_kw"])
    diagnostics["raw_peak_contract_arrival_mw_it"] = float(
        (workload["rigid_compute_arrival"] + workload["flex_compute_arrival"]).max()
    )
    diagnostics["scaled_peak_contract_arrival_mw_it"] = float(
        config["workload_scale"]
        * (workload["rigid_compute_arrival"] + workload["flex_compute_arrival"]).max()
    )
    capacity = float(it_params["it_capacity"])
    if diagnostics["scaled_peak_contract_arrival_mw_it"] > capacity + 1e-9:
        warnings.append("缩放后的刚性+柔性峰值仍超过IT服务容量，可能产生违约或积压。")

    return InputBundle(
        workload=workload,
        power=power,
        sea_temperature=sea_temperature,
        it_params=it_params,
        cooling_params=cooling_params,
        task_params=task_params,
        price_table=price_table,
        warnings=warnings,
        diagnostics=diagnostics,
    )
