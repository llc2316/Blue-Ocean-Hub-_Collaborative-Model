# losses.py - 损耗模型
from enum import Enum
from dataclasses import dataclass
from typing import Dict, TYPE_CHECKING

if TYPE_CHECKING:
    from .components import EnergyIslandSystem


class LossType(Enum):
    LINE = "line_loss"
    TRANSFORMER = "transformer_loss"
    CONVERTER = "converter_loss"
    TRANSMISSION = "transmission_loss"
    AUXILIARY = "auxiliary_loss"
    THERMAL = "thermal_loss"
    OTHER = "other_loss"


@dataclass
class LossComponent:
    name: str
    loss_type: LossType
    base_loss_mw: float = 0.0
    variable_loss_ratio: float = 0.0
    current_loss_mw: float = 0.0


class LossModel:
    def __init__(self):
        self.components: Dict[str, LossComponent] = {}
        self.total_loss_mw: float = 0.0
        self._line_loss_ratio = 0.02
        self._transformer_loss_ratio = 0.01
        self._converter_loss_ratio = 0.03
        self._auxiliary_power_ratio = 0.01

    def set_loss_ratios(self, line=None, transformer=None,
                        converter=None, auxiliary=None):
        if line is not None:
            self._line_loss_ratio = line
        if transformer is not None:
            self._transformer_loss_ratio = transformer
        if converter is not None:
            self._converter_loss_ratio = converter
        if auxiliary is not None:
            self._auxiliary_power_ratio = auxiliary

    def calculate(self, system):
        """计算系统总损耗"""
        total_capacity = sum(s.rated_capacity_mw for s in system.sources.values())
        total_demand = (
            sum(l.rated_power_mw for l in system.loads.values()) +
            sum(c.rated_power_mw for c in system.computings.values())
        )
        avg_power_flow = min(total_capacity, total_demand)

        line_loss = avg_power_flow * self._line_loss_ratio
        transformer_loss = avg_power_flow * self._transformer_loss_ratio
        converter_loss = avg_power_flow * self._converter_loss_ratio
        auxiliary_loss = total_capacity * self._auxiliary_power_ratio

        self.components["line"] = LossComponent(
            "line", LossType.LINE, current_loss_mw=line_loss
        )
        self.components["transformer"] = LossComponent(
            "transformer", LossType.TRANSFORMER, current_loss_mw=transformer_loss
        )
        self.components["converter"] = LossComponent(
            "converter", LossType.CONVERTER, current_loss_mw=converter_loss
        )
        self.components["auxiliary"] = LossComponent(
            "auxiliary", LossType.AUXILIARY, current_loss_mw=auxiliary_loss
        )

        self.total_loss_mw = line_loss + transformer_loss + converter_loss + auxiliary_loss
        return self.total_loss_mw

    def get_breakdown(self):
        return {name: comp.current_loss_mw for name, comp in self.components.items()}

    def __repr__(self):
        return f"LossModel(total={self.total_loss_mw:.4f}MW, components={len(self.components)})"
