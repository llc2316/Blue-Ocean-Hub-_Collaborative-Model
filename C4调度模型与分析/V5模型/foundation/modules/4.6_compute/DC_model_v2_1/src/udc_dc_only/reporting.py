from __future__ import annotations

import json
from pathlib import Path
from typing import Any
import hashlib

import matplotlib.pyplot as plt
import pandas as pd

from .model import ModelResult


def _json_dump(obj: Any, path: Path) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=True)


def save_outputs(result: ModelResult, output_dir: str | Path, warnings: list[str], diagnostics: dict[str, Any], config: dict[str, Any]) -> None:
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    result.hourly.to_csv(out / "hourly_results.csv", index=False, encoding="utf-8-sig")
    _json_dump(result.summary, out / "summary.json")
    _json_dump(result.solver, out / "solver.json")
    _json_dump(result.audit, out / "audit.json")
    _json_dump({"warnings": warnings, "diagnostics": diagnostics}, out / "data_check.json")
    canonical = json.dumps(config, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    metadata = {
        "config_sha256": hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
        "model": "UDC DC-only",
        "model_version": "1.1.0",
    }
    _json_dump(metadata, out / "run_metadata.json")
    _save_plots(result.hourly, out)


def _save_plots(df: pd.DataFrame, out: Path) -> None:
    x = pd.to_datetime(df["timestamp"])

    plt.figure(figsize=(12, 5))
    plt.plot(x, df["rigid_served_mwh_it"], label="Rigid served")
    plt.plot(x, df["flex_served_mwh_it"], label="Flexible served")
    plt.plot(x, df["spot_served_mwh_it"], label="Spot served")
    plt.plot(x, df["flex_queue_mwh_it"], label="Flexible queue")
    plt.xlabel("Time")
    plt.ylabel("MWh-IT per hour / queue")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out / "workload_dispatch.png", dpi=180)
    plt.close()

    plt.figure(figsize=(12, 5))
    plt.plot(x, df["it_power_mw"], label="IT power")
    plt.plot(x, df["cooling_power_mw"], label="Cooling power")
    plt.plot(x, df["dc_power_mw"], label="DC total power")
    plt.plot(x, df["dc_power_cap_mw"], label="Power cap")
    plt.xlabel("Time")
    plt.ylabel("MW")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out / "power_profile.png", dpi=180)
    plt.close()

    plt.figure(figsize=(12, 5))
    plt.plot(x, df["pue"], label="Dynamic PUE")
    plt.xlabel("Time")
    plt.ylabel("PUE")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out / "dynamic_pue.png", dpi=180)
    plt.close()

    plt.figure(figsize=(12, 5))
    plt.plot(x, df["electricity_contribution_margin_yuan"], label="Hourly margin")
    plt.xlabel("Time")
    plt.ylabel("CNY/h")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out / "hourly_margin.png", dpi=180)
    plt.close()
