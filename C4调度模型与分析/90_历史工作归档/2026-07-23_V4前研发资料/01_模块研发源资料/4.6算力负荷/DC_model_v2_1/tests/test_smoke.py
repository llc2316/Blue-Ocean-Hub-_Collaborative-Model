from __future__ import annotations

import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from udc_dc_only.pue import facility_power


def test_design_pue_anchor() -> None:
    it = {
        "it_capacity": 7.08,
        "idle_power_ratio": 0.30,
        "power_curve_exponent": 1.0,
        "distribution_efficiency": 0.96,
    }
    cool = {
        "reference_sea_temperature": 23.5,
        "cooling_fixed_power": 0.05,
        "cooling_linear_coeff": 0.03410556,
        "cooling_quadratic_coeff": 0.0001,
        "temperature_coefficient": 0.002,
        "cooling_power_min": 0.05,
        "fixed_auxiliary_power": 0.10,
    }
    _, _, _, pue = facility_power(np.array([7.08]), np.array([23.5]), it, cool)
    assert abs(float(pue[0]) - 1.10) < 1e-6
