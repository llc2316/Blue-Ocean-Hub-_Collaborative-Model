# reserve.py - 备用缺口分析
from enum import Enum
from dataclasses import dataclass


class ReserveStatus(Enum):
    SUFFICIENT = "sufficient"
    INSUFFICIENT = "insufficient"
    CRITICAL = "critical"


@dataclass
class ReserveGap:
    spinning_reserve_mw: float = 0.0
    contingency_reserve_mw: float = 0.0
    total_reserve_required_mw: float = 0.0
    total_reserve_available_mw: float = 0.0
    gap_mw: float = 0.0
    gap_ratio: float = 0.0
    status: ReserveStatus = ReserveStatus.SUFFICIENT

    def analyze(self, system, balance_result):
        total_gen = sum(s.current_output_mw for s in system.sources.values())
        total_load = (
            sum(l.current_load_mw for l in system.loads.values()) +
            sum(c.current_load_mw for c in system.computings.values())
        )
        max_unit = max(
            [s.rated_capacity_mw for s in system.sources.values()] + [0]
        )
        self.spinning_reserve_mw = max(max_unit, 0.1 * total_load)
        self.contingency_reserve_mw = 0.05 * total_load
        self.total_reserve_required_mw = (
            self.spinning_reserve_mw + self.contingency_reserve_mw
        )
        imbalance = balance_result.net_imbalance_mw
        if imbalance >= 0:
            self.total_reserve_available_mw = imbalance
        else:
            storage_available = sum(
                st.available_energy_mwh for st in system.storages.values()
            )
            curtailable_load = sum(
                l.current_load_mw for l in system.loads.values()
                if l.is_curtailable
            )
            self.total_reserve_available_mw = storage_available + curtailable_load
        self.gap_mw = max(
            0, self.total_reserve_required_mw - self.total_reserve_available_mw
        )
        if self.total_reserve_required_mw > 0:
            self.gap_ratio = self.gap_mw / self.total_reserve_required_mw
        if self.gap_ratio == 0:
            self.status = ReserveStatus.SUFFICIENT
        elif self.gap_ratio < 0.5:
            self.status = ReserveStatus.INSUFFICIENT
        else:
            self.status = ReserveStatus.CRITICAL
        return self.gap_mw

    def __repr__(self):
        return (f"ReserveGap(gap={self.gap_mw:.2f}MW, "
                f"ratio={self.gap_ratio:.1%}, "
                f"status={self.status.value})")
