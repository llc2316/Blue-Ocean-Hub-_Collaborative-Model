# power_balance.py - 多端口耦合功率守恒方程
# Multi-port coupling power conservation equation
#
# 核心功率平衡方程:
#   ΣP_source + P_storage_discharge = ΣP_load + P_computing + P_storage_charge + P_loss + P_reserve_gap
#
# 等价形式 (母线节点功率守恒):
#   ΣP_inject - ΣP_absorb - P_loss - P_reserve_gap = 0

from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple
from enum import Enum

from .ports import PowerPort, PortCategory, PortDirection, validate_port_direction


class BalanceStatus(Enum):
    """功率平衡状态"""
    BALANCED = "balanced"              # 平衡
    SURPLUS = "surplus"                # 功率盈余
    DEFICIT = "deficit"                # 功率缺口
    RESERVE_ACTIVATED = "reserve_on"   # 备用启动


@dataclass
class PowerBalanceResult:
    """功率平衡结算结果"""
    total_generation_mw: float = 0.0       # 总发电 [MW]
    total_load_mw: float = 0.0             # 总负荷 [MW]
    total_computing_mw: float = 0.0        # 算力负荷 [MW]
    storage_charge_mw: float = 0.0         # 储能充电 [MW]
    storage_discharge_mw: float = 0.0      # 储能放电 [MW]
    total_loss_mw: float = 0.0             # 总损耗 [MW]
    reserve_gap_mw: float = 0.0            # 备用缺口 [MW]
    net_imbalance_mw: float = 0.0          # 净不平衡功率 [MW] (>0=盈余, <0=缺口)
    status: BalanceStatus = BalanceStatus.BALANCED
    port_details: Dict[str, float] = field(default_factory=dict)

    @property
    def total_demand_mw(self) -> float:
        """总有功需求 = 负荷 + 算力 + 储能充电 + 损耗 + 备用缺口"""
        return (self.total_load_mw + self.total_computing_mw +
                self.storage_charge_mw + self.total_loss_mw + self.reserve_gap_mw)

    @property
    def total_supply_mw(self) -> float:
        """总有功供给 = 发电 + 储能放电"""
        return self.total_generation_mw + self.storage_discharge_mw

    def surplus_ratio(self) -> float:
        """盈余/缺口比例"""
        if self.total_demand_mw == 0:
            return 0.0
        return self.total_supply_mw / self.total_demand_mw - 1.0


class PowerBalanceEquation:
    """
    多端口耦合电功率平衡模型
    Multi-port coupled electric power balance model

    能源岛母线节点功率守恒关系:
    ΣP_source_i + ΣP_storage_discharge_j - ΣP_load_k - ΣP_computing_l
        - ΣP_storage_charge_m - P_loss_total - P_reserve_gap = 0
    """

    def __init__(self):
        self.ports: List[PowerPort] = []
        self._bus_voltage_pu: float = 1.0  # 母线电压标幺值
        self._frequency_pu: float = 1.0    # 频率标幺值

    def add_port(self, port: PowerPort) -> None:
        """添加端口到母线"""
        self.ports.append(port)

    def remove_port(self, port_name: str) -> None:
        """移除端口"""
        self.ports = [p for p in self.ports if p.name != port_name]

    def get_ports_by_category(self, category: PortCategory) -> List[PowerPort]:
        """按类别获取端口列表"""
        return [p for p in self.ports if p.category == category]

    def solve_balance(self) -> PowerBalanceResult:
        """
        求解功率平衡方程
        Solve the power balance equation

        计算步骤:
        1. 统计各端口分类的功率
        2. 计入效率损耗
        3. 计算净不平衡量
        4. 判定备用缺口
        """
        result = PowerBalanceResult()
        port_details = {}

        # --- 1. 统计源功率 (注入母线) ---
        source_ports = self.get_ports_by_category(PortCategory.SOURCE)
        for sp in source_ports:
            if not validate_port_direction(sp):
                continue
            net = sp.net_power_mw  # 已扣除端口损耗
            result.total_generation_mw += max(net, 0)
            port_details[f"source_{sp.name}"] = net
            port_details[f"loss_{sp.name}"] = sp.loss_power_mw
            result.total_loss_mw += sp.loss_power_mw

        # --- 2. 统计负荷功率 (从母线吸收) ---
        load_ports = self.get_ports_by_category(PortCategory.LOAD)
        for lp in load_ports:
            if not validate_port_direction(lp):
                continue
            net = abs(lp.net_power_mw)
            result.total_load_mw += net
            port_details[f"load_{lp.name}"] = -net
            port_details[f"loss_{lp.name}"] = lp.loss_power_mw
            result.total_loss_mw += lp.loss_power_mw

        # --- 3. 统计算力负荷 ---
        computing_ports = self.get_ports_by_category(PortCategory.COMPUTING)
        for cp in computing_ports:
            if not validate_port_direction(cp):
                continue
            net = abs(cp.net_power_mw)
            result.total_computing_mw += net
            port_details[f"computing_{cp.name}"] = -net
            port_details[f"loss_{cp.name}"] = cp.loss_power_mw
            result.total_loss_mw += cp.loss_power_mw

        # --- 4. 统计储能 (双向) ---
        storage_ports = self.get_ports_by_category(PortCategory.STORAGE)
        for sp in storage_ports:
            if sp.current_power_mw >= 0:
                # 放电: 注入母线
                net = sp.net_power_mw
                result.storage_discharge_mw += net
                port_details[f"storage_discharge_{sp.name}"] = net
            else:
                # 充电: 从母线吸收
                net = abs(sp.net_power_mw)
                result.storage_charge_mw += net
                port_details[f"storage_charge_{sp.name}"] = -net
            port_details[f"loss_{sp.name}"] = sp.loss_power_mw
            result.total_loss_mw += sp.loss_power_mw

        # --- 5. 统计损耗通道 ---
        loss_ports = self.get_ports_by_category(PortCategory.LOSS)
        for lp in loss_ports:
            result.total_loss_mw += abs(lp.current_power_mw)
            port_details[f"loss_{lp.name}"] = abs(lp.current_power_mw)

        # --- 6. 计算净不平衡量 ---
        result.net_imbalance_mw = (result.total_supply_mw - result.total_demand_mw)

        # --- 7. 备用缺口分析 ---
        reserve_ports = self.get_ports_by_category(PortCategory.RESERVE)
        for rp in reserve_ports:
            result.reserve_gap_mw += abs(rp.current_power_mw)

        # 如果净不平衡且备用电量不足以弥补
        if result.net_imbalance_mw < -result.reserve_gap_mw:
            result.status = BalanceStatus.DEFICIT
            additional_gap = abs(result.net_imbalance_mw) - result.reserve_gap_mw
            result.reserve_gap_mw += additional_gap
        elif result.net_imbalance_mw > 0:
            result.status = BalanceStatus.SURPLUS
        elif result.reserve_gap_mw > 0:
            result.status = BalanceStatus.RESERVE_ACTIVATED
        else:
            result.status = BalanceStatus.BALANCED

        result.port_details = port_details

        # 重新计算净不平衡(含备用)
        result.net_imbalance_mw = (result.total_supply_mw - result.total_demand_mw)

        return result

    def check_feasibility(self) -> Tuple[bool, str]:
        """
        检查功率平衡可行性
        Returns: (是否可行, 描述信息)
        """
        total_gen = sum(
            p.rated_power_mw
            for p in self.ports
            if p.category == PortCategory.SOURCE
        )
        total_demand = sum(
            p.rated_power_mw
            for p in self.ports
            if p.category in (PortCategory.LOAD, PortCategory.COMPUTING)
        )
        total_storage = sum(
            p.rated_power_mw
            for p in self.ports
            if p.category == PortCategory.STORAGE
        )

        # 最大可用供给 = 源 + 储能放电
        max_supply = total_gen + total_storage
        # 最小需求 = 负荷 + 算力 (不含储能充电)
        min_demand = total_demand

        if max_supply < min_demand:
            msg = (f"不可行: 最大供给({max_supply:.1f}MW) < 最小需求({min_demand:.1f}MW), "
                   f"缺口={min_demand - max_supply:.1f}MW")
            return False, msg
        elif max_supply >= min_demand * 1.5:
            msg = (f"可行但有显著盈余: 最大供给({max_supply:.1f}MW) >> 最小需求({min_demand:.1f}MW), "
                   f"建议配置储能或削减发电")
            return True, msg
        else:
            msg = (f"可行: 最大供给({max_supply:.1f}MW) >= 最小需求({min_demand:.1f}MW)")
            return True, msg

    def __repr__(self) -> str:
        n_ports = len(self.ports)
        cats = {c.value: len(self.get_ports_by_category(c)) for c in PortCategory}
        return (f"PowerBalanceEquation(ports={n_ports}, "
                f"src={cats['source']}, stg={cats['storage']}, "
                f"cmp={cats['computing']}, load={cats['load']}, "
                f"loss={cats['loss']}, rsv={cats['reserve']})")
