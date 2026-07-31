# components.py - 源、储、算、用组件类
# Source, Storage, Computing, Load Component Classes

from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple
from enum import Enum

from .ports import PowerPort, PortDirection, PortCategory
from .power_balance import PowerBalanceEquation, PowerBalanceResult, BalanceStatus
from .losses import LossModel, LossType
from .reserve import ReserveGap, ReserveStatus


class SourceType(Enum):
    """源类型"""
    WIND_OFFSHORE = "offshore_wind"         # 海上风电
    WIND_ONSHORE = "onshore_wind"           # 陆上风电
    SOLAR_PV = "solar_pv"                   # 光伏
    WAVE = "wave_energy"                    # 波浪能
    TIDAL = "tidal_energy"                  # 潮汐能
    DIESEL = "diesel_genset"                # 柴油发电机(备用)
    GAS_TURBINE = "gas_turbine"             # 燃气轮机
    HYDROGEN = "hydrogen_fuel_cell"         # 氢燃料电池


class StorageType(Enum):
    """储能类型"""
    BATTERY_LI = "lithium_battery"           # 锂电池
    BATTERY_FLOW = "flow_battery"            # 液流电池
    HYDROGEN = "hydrogen_storage"            # 氢储能
    PUMPED_HYDRO = "pumped_hydro"            # 抽水蓄能
    FLYWHEEL = "flywheel"                    # 飞轮储能
    SUPERCAP = "supercapacitor"              # 超级电容


@dataclass
class SourceUnit:
    """源单元 - 发电侧组件"""
    name: str
    source_type: SourceType
    rated_capacity_mw: float                 # 额定装机容量 [MW]
    current_output_mw: float = 0.0           # 当前出力 [MW]
    efficiency: float = 1.0                  # 发电效率
    availability: float = 1.0                # 可用率 [0-1]
    is_renewable: bool = True                # 是否可再生能源
    metadata: dict = field(default_factory=dict)

    def __post_init__(self):
        if not (0.0 <= self.availability <= 1.0):
            raise ValueError(f"可用率必须在[0,1]范围内: {self.availability}")
        if not (0.0 <= self.efficiency <= 1.0):
            raise ValueError(f"效率必须在[0,1]范围内: {self.efficiency}")

    @property
    def available_capacity_mw(self) -> float:
        """可用容量 = 额定容量 * 可用率"""
        return self.rated_capacity_mw * self.availability

    @property
    def curtailed_power_mw(self) -> float:
        """弃电功率 = 可用容量 - 当前出力"""
        return max(0, self.available_capacity_mw - self.current_output_mw)

    def to_port(self) -> PowerPort:
        """转换为功率端口"""
        return PowerPort(
            name=self.name,
            category=PortCategory.SOURCE,
            direction=PortDirection.POSITIVE,
            rated_power_mw=self.rated_capacity_mw,
            current_power_mw=self.current_output_mw,
            efficiency=self.efficiency,
            is_controllable=not self.is_renewable,
            metadata={
                "source_type": self.source_type.value,
                "availability": self.availability,
                "is_renewable": self.is_renewable,
            }
        )


@dataclass
class StorageUnit:
    """储能单元"""
    name: str
    storage_type: StorageType
    rated_power_mw: float                     # 额定功率 [MW]
    rated_energy_mwh: float                   # 额定容量 [MWh]
    current_soc: float = 0.5                  # 当前荷电状态 [0-1]
    min_soc: float = 0.1                      # 最小SOC [0-1]
    max_soc: float = 0.9                      # 最大SOC [0-1]
    charge_efficiency: float = 0.9            # 充电效率 [0-1]
    discharge_efficiency: float = 0.9         # 放电效率 [0-1]
    self_discharge_rate: float = 0.01         # 自放电率 [%/h]
    metadata: dict = field(default_factory=dict)

    def __post_init__(self):
        if not (self.min_soc <= self.current_soc <= self.max_soc):
            raise ValueError(
                f"SOC={self.current_soc} 超出范围[{self.min_soc}, {self.max_soc}]"
            )

    @property
    def available_energy_mwh(self) -> float:
        """可用能量 [MWh]"""
        return self.rated_energy_mwh * (self.current_soc - self.min_soc)

    @property
    def chargeable_energy_mwh(self) -> float:
        """可充电量 [MWh]"""
        return self.rated_energy_mwh * (self.max_soc - self.current_soc)

    def charge(self, power_mw: float, duration_h: float) -> float:
        """充电模拟，返回实际充电功率 [MW]"""
        energy = power_mw * duration_h
        max_chargeable = self.chargeable_energy_mwh
        actual_energy = min(energy, max_chargeable)
        actual_power = actual_energy / duration_h if duration_h > 0 else 0
        actual_power = min(actual_power, self.rated_power_mw)

        soc_change = actual_energy / self.rated_energy_mwh
        self.current_soc = min(self.current_soc + soc_change, self.max_soc)
        return actual_power

    def discharge(self, power_mw: float, duration_h: float) -> float:
        """放电模拟，返回实际放电功率 [MW]"""
        energy = power_mw * duration_h
        max_dischargeable = self.available_energy_mwh
        actual_energy = min(energy, max_dischargeable)
        actual_power = actual_energy / duration_h if duration_h > 0 else 0
        actual_power = min(actual_power, self.rated_power_mw)

        soc_change = actual_energy / self.rated_energy_mwh
        self.current_soc = max(self.current_soc - soc_change, self.min_soc)
        return actual_power

    def to_port(self, power_mw: float) -> PowerPort:
        """
        转换为功率端口
        power_mw > 0: 放电(注入母线)
        power_mw < 0: 充电(从母线吸收)
        """
        eff = self.discharge_efficiency if power_mw >= 0 else self.charge_efficiency
        return PowerPort(
            name=self.name,
            category=PortCategory.STORAGE,
            direction=PortDirection.BIDIRECTIONAL,
            rated_power_mw=self.rated_power_mw,
            current_power_mw=power_mw,
            efficiency=eff,
            is_controllable=True,
            metadata={
                "storage_type": self.storage_type.value,
                "soc": self.current_soc,
                "rated_energy_mwh": self.rated_energy_mwh,
            }
        )


@dataclass
class ComputingUnit:
    """算力单元 - 数据中心/计算负荷"""
    name: str
    rated_power_mw: float                     # 额定功率 [MW]
    current_load_mw: float = 0.0              # 当前负载 [MW]
    utilization: float = 0.0                  # 算力利用率 [0-1]
    pue: float = 1.4                          # 电能使用效率(PUE)
    is_critical: bool = False                 # 是否关键负荷
    metadata: dict = field(default_factory=dict)

    def __post_init__(self):
        if not (0.0 <= self.utilization <= 1.0):
            raise ValueError(f"利用率必须在[0,1]范围内: {self.utilization}")
        if self.pue < 1.0:
            raise ValueError(f"PUE必须 >= 1.0: {self.pue}")

    @property
    def it_load_mw(self) -> float:
        """IT设备负载 [MW]"""
        return self.current_load_mw / self.pue if self.pue > 0 else 0

    def set_load(self, load_mw: float) -> None:
        """设置当前负载"""
        self.current_load_mw = min(load_mw, self.rated_power_mw)
        self.utilization = self.current_load_mw / self.rated_power_mw if self.rated_power_mw > 0 else 0

    def to_port(self) -> PowerPort:
        """转换为功率端口"""
        return PowerPort(
            name=self.name,
            category=PortCategory.COMPUTING,
            direction=PortDirection.NEGATIVE,
            rated_power_mw=self.rated_power_mw,
            current_power_mw=-self.current_load_mw,
            efficiency=1.0 / self.pue,
            is_controllable=not self.is_critical,
            metadata={
                "pue": self.pue,
                "utilization": self.utilization,
                "it_load_mw": self.it_load_mw,
            }
        )


@dataclass
class LoadUnit:
    """用能单元 - 一般负荷"""
    name: str
    rated_power_mw: float                     # 额定功率 [MW]
    current_load_mw: float = 0.0              # 当前负载 [MW]
    load_factor: float = 1.0                  # 负荷率 [0-1]
    is_critical: bool = False                 # 是否关键负荷
    is_curtailable: bool = False              # 是否可削减
    metadata: dict = field(default_factory=dict)

    def __post_init__(self):
        if not (0.0 <= self.load_factor <= 1.0):
            raise ValueError(f"负荷率必须在[0,1]范围内: {self.load_factor}")

    def set_load(self, load_mw: float) -> None:
        """设置当前负载"""
        self.current_load_mw = min(load_mw, self.rated_power_mw)

    def to_port(self) -> PowerPort:
        """转换为功率端口"""
        return PowerPort(
            name=self.name,
            category=PortCategory.LOAD,
            direction=PortDirection.NEGATIVE,
            rated_power_mw=self.rated_power_mw,
            current_power_mw=-self.current_load_mw,
            efficiency=1.0,
            is_controllable=self.is_curtailable,
            metadata={
                "load_factor": self.load_factor,
                "is_critical": self.is_critical,
                "is_curtailable": self.is_curtailable,
            }
        )


class EnergyIslandSystem:
    """
    能源岛系统 - 整合所有组件
    Energy Island System - Integrated System Model

    将源、储、算、用组件接入同一个功率平衡方程
    """

    def __init__(self, name: str = "能源岛"):
        self.name = name
        self.sources: Dict[str, SourceUnit] = {}
        self.storages: Dict[str, StorageUnit] = {}
        self.computings: Dict[str, ComputingUnit] = {}
        self.loads: Dict[str, LoadUnit] = {}
        self.loss_model = LossModel()
        self.reserve_gap = ReserveGap()
        self.balance = PowerBalanceEquation()
        self.last_result: Optional[PowerBalanceResult] = None

    def add_source(self, source: SourceUnit) -> None:
        """添加发电单元"""
        self.sources[source.name] = source
        port = source.to_port()
        self.balance.add_port(port)

    def add_storage(self, storage: StorageUnit) -> None:
        """添加储能单元"""
        self.storages[storage.name] = storage
        # 默认以0功率接入，由solve时更新
        port = storage.to_port(0)
        self.balance.add_port(port)

    def add_computing(self, computing: ComputingUnit) -> None:
        """添加算力单元"""
        self.computings[computing.name] = computing
        port = computing.to_port()
        self.balance.add_port(port)

    def add_load(self, load: LoadUnit) -> None:
        """添加用能单元"""
        self.loads[load.name] = load
        port = load.to_port()
        self.balance.add_port(port)

    def update_system_state(self) -> None:
        """更新所有组件状态到功率平衡方程"""
        self.balance = PowerBalanceEquation()

        # 重新添加源端口
        for src in self.sources.values():
            self.balance.add_port(src.to_port())

        # 重新添加负荷端口
        for ld in self.loads.values():
            self.balance.add_port(ld.to_port())

        # 重新添加算力端口
        for cmp in self.computings.values():
            self.balance.add_port(cmp.to_port())

    def solve(self, time_step_h: float = 0.0) -> PowerBalanceResult:
        """
        求解系统功率平衡

        流程:
        1. 更新所有端口状态
        2. 求解母线功率守恒方程
        3. 计算系统损耗
        4. 分析备用缺口
        """
        self.update_system_state()

        # 计算基础损耗
        self.loss_model.calculate(self)

        # 添加损耗端口
        loss_port = PowerPort(
            name="system_losses",
            category=PortCategory.LOSS,
            direction=PortDirection.NEGATIVE,
            rated_power_mw=self.loss_model.total_loss_mw,
            current_power_mw=-self.loss_model.total_loss_mw,
            efficiency=1.0,
            is_controllable=False,
        )
        self.balance.add_port(loss_port)

        # 求解基础平衡
        base_result = self.balance.solve_balance()

        # 分析备用缺口
        gap = self.reserve_gap.analyze(self, base_result)

        if gap > 0:
            reserve_port = PowerPort(
                name="reserve_gap",
                category=PortCategory.RESERVE,
                direction=PortDirection.NEGATIVE,
                rated_power_mw=gap,
                current_power_mw=-gap,
                efficiency=1.0,
                is_controllable=False,
            )
            self.balance.add_port(reserve_port)

        # 最终求解
        self.last_result = self.balance.solve_balance()
        return self.last_result

    def get_system_summary(self) -> Dict:
        """获取系统概要"""
        return {
            "name": self.name,
            "total_source_capacity_mw": sum(
                s.rated_capacity_mw for s in self.sources.values()
            ),
            "total_storage_capacity_mw": sum(
                s.rated_power_mw for s in self.storages.values()
            ),
            "total_storage_energy_mwh": sum(
                s.rated_energy_mwh for s in self.storages.values()
            ),
            "total_computing_capacity_mw": sum(
                c.rated_power_mw for c in self.computings.values()
            ),
            "total_load_capacity_mw": sum(
                l.rated_power_mw for l in self.loads.values()
            ),
            "num_sources": len(self.sources),
            "num_storages": len(self.storages),
            "num_computings": len(self.computings),
            "num_loads": len(self.loads),
        }

    def __repr__(self) -> str:
        s = self.get_system_summary()
        return (f"EnergyIslandSystem({self.name}|"
                f"src={s['num_sources']}({s['total_source_capacity_mw']:.0f}MW)|"
                f"stg={s['num_storages']}({s['total_storage_capacity_mw']:.0f}MW/"
                f"{s['total_storage_energy_mwh']:.0f}MWh)|"
                f"cmp={s['num_computings']}({s['total_computing_capacity_mw']:.0f}MW)|"
                f"load={s['num_loads']}({s['total_load_capacity_mw']:.0f}MW))")
