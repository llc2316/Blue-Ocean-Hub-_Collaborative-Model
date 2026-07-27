# ports.py - 端口方向约定与端口基类
# Port direction conventions and base port class for Energy Island Power Balance Model

from enum import Enum, auto
from typing import Optional
from dataclasses import dataclass, field


class PortDirection(Enum):
    """功率方向约定
    Power direction convention:
    以能源岛交流母线为正方向参考节点
    POSITIVE = 功率流入母线（源/发电侧）
    NEGATIVE = 功率流出母线（负荷/耗能侧）
    BIDIRECTIONAL = 双向可逆（储能）
    """
    POSITIVE = "inject"       # 注入母线: 源
    NEGATIVE = "absorb"       # 从母线吸收: 负荷
    BIDIRECTIONAL = "bi_dir"  # 双向可逆: 储能


class PortCategory(Enum):
    """端口分类
    Port categories of the energy island
    """
    SOURCE = "source"        # 源: 新能源发电
    STORAGE = "storage"      # 储: 储能系统
    COMPUTING = "computing"  # 算: 算力负荷
    LOAD = "load"            # 用: 用能负荷
    LOSS = "loss"            # 损耗通道
    RESERVE = "reserve"      # 备用缺口


@dataclass
class PowerPort:
    """功率端口基类
    Base class representing a single power port on the energy island bus

    Attributes:
        name: 端口名称
        category: 端口类别（源/储/算/用）
        direction: 功率方向约定
        rated_power_mw: 额定功率 [MW]
        current_power_mw: 当前功率 [MW] (正=注入母线，负=从母线吸收)
        efficiency: 端口效率 [0-1]，用于计算损耗
        is_controllable: 是否可控
    """
    name: str
    category: PortCategory
    direction: PortDirection
    rated_power_mw: float = 0.0
    current_power_mw: float = 0.0
    efficiency: float = 1.0
    is_controllable: bool = True
    metadata: dict = field(default_factory=dict)

    def __post_init__(self):
        if not (0.0 <= self.efficiency <= 1.0):
            raise ValueError(f"效率值必须在[0,1]范围内: {self.efficiency}")

    @property
    def loss_power_mw(self) -> float:
        """端口损耗功率 [MW]"""
        gross_power = abs(self.current_power_mw)
        return gross_power * (1.0 - self.efficiency)

    @property
    def net_power_mw(self) -> float:
        """端口净功率 [MW] (已扣除损耗)"""
        if self.current_power_mw >= 0:
            return self.current_power_mw * self.efficiency
        else:
            return self.current_power_mw / self.efficiency

    def set_power(self, power_mw: float) -> None:
        """设置当前功率值
        正 = 注入母线(POSITIVE/BIDIRECTIONAL)
        负 = 从母线吸收(NEGATIVE/BIDIRECTIONAL)
        """
        if self.direction == PortDirection.POSITIVE and power_mw < 0:
            raise ValueError(f"正向端口{self.name}不能为负功率(吸收)")
        if self.direction == PortDirection.NEGATIVE and power_mw > 0:
            raise ValueError(f"负向端口{self.name}不能为正功率(注入)")
        if abs(power_mw) > self.rated_power_mw:
            raise ValueError(
                f"功率{power_mw:.2f} MW超过端口{self.name}额定值{self.rated_power_mw:.2f} MW"
            )
        self.current_power_mw = power_mw

    def utilization(self) -> float:
        """当前利用率 [0-1]"""
        if self.rated_power_mw == 0:
            return 0.0
        return abs(self.current_power_mw) / self.rated_power_mw

    def __repr__(self) -> str:
        return (f"Port({self.name}|{self.category.value}|"
                f"{self.current_power_mw:+.2f}MW/{self.rated_power_mw:.2f}MW|"
                f"eff={self.efficiency:.2f})")


def validate_port_direction(port: PowerPort) -> bool:
    """校验端口功率方向是否符合约定"""
    if port.direction == PortDirection.POSITIVE and port.current_power_mw < 0:
        return False
    if port.direction == PortDirection.NEGATIVE and port.current_power_mw > 0:
        return False
    return True
