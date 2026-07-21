from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load_config(path: str | Path) -> dict[str, Any]:
    config_path = Path(path)
    with config_path.open("r", encoding="utf-8") as f:
        cfg = json.load(f)

    required = {
        "data_root",
        "output_dir",
        "simulation_start",
        "simulation_hours",
        "workload_scale",
        "spot_workload_scale",
        "piecewise_segments",
        "power_interface_mode",
    }
    missing = sorted(required - set(cfg))
    if missing:
        raise ValueError(f"配置文件缺少字段: {missing}")
    if int(cfg["simulation_hours"]) <= 0:
        raise ValueError("simulation_hours 必须大于0")
    if float(cfg["workload_scale"]) <= 0:
        raise ValueError("workload_scale 必须大于0")
    if float(cfg["spot_workload_scale"]) < 0:
        raise ValueError("spot_workload_scale 不能为负")
    if int(cfg["piecewise_segments"]) < 2:
        raise ValueError("piecewise_segments 至少为2")
    if cfg["power_interface_mode"] not in {"constant", "file"}:
        raise ValueError("power_interface_mode 只能为 constant 或 file")
    if cfg["power_interface_mode"] == "constant":
        for key in ["constant_dc_power_cap_mw", "constant_electricity_price_yuan_per_mwh"]:
            if key not in cfg:
                raise ValueError(f"constant模式缺少配置项: {key}")
    return cfg
