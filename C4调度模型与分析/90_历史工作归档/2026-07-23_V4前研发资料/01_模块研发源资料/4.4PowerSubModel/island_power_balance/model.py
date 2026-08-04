# Model: Island Power Balance (per interface spec)  
import os, math, sys  
from dataclasses import dataclass, field  
from typing import List, Dict, Optional, Tuple  
from enum import Enum  
  
BASE_DIR = os.path.dirname(os.path.abspath(__file__))  
OUT_DIR = os.path.join(BASE_DIR, '..', '..', 'outputs', 'v2')  
os.makedirs(OUT_DIR, exist_ok=True) 
# ============================================================  
# Part 1: Measurement Points and Direction Conventions  
# ============================================================  
class MP:  
    DEVICE = 'MP-DEVICE'  
    SOURCE_POI = 'MP-03-SOURCE-POI'  
    COMMON_BUS = 'MP-04-COMMON-BUS'  
    CABLE_SEND = 'MP-CABLE-SEND'  
    CABLE_RECEIVE = 'MP-CABLE-RECEIVE'  
    DC_FACILITY = 'MP-DC-FACILITY'  
    ELECTROLYZER = 'MP-ELECTROLYZER'  
    H2_DELIVERY = 'MP-H2-DELIVERY' 
class PortDirection(Enum):  
    INJECT = 'inject'  
    CONSUME = 'consume'  
    BESS = 'bess'  
  
class GovernanceSection(Enum):  
    S4_3 = '4.3'  
    S4_4 = '4.4'  
    S4_5 = '4.5'  
    S4_6 = '4.6'  
    S4_7 = '4.7' 
@dataclass  
class RequestAcceptActual:  
    requested_mw: float = 0.0  
    accepted_mw: float = 0.0  
    actual_mw: float = 0.0  
    def ramp_check(self, prev_mw, rr, dt):  
        mc = rr * dt  
        self.accepted_mw = max(min(self.accepted_mw, prev_mw+mc), prev_mw-mc)  
        self.actual_mw = min(self.actual_mw, self.accepted_mw) 
# ============================================================  
# Part 2: Metrics and Parameter Packages  
# ============================================================  
@dataclass  
class PowerBalanceMetrics:  
    p_source_actual: float = 0.0  
    p_source_aux: float = 0.0  
    p_bess_discharge: float = 0.0  
    p_bess_charge: float = 0.0  
    p_electrolyzer: float = 0.0  
    p_dc_facility: float = 0.0  
    p_export_send: float = 0.0  
    p_marine: float = 0.0  
    p_grid_import: float = 0.0  
    p_spill: float = 0.0  
    p_unserved: float = 0.0  
    p_post_poi_loss: float = 0.0  
    p_common_aux: float = 0.0  
    p_residual: float = 0.0 
@dataclass  
class SourceParams:  
    wind_mw: float = 34.0  
    pv_mw: float = 4.0  
    tidal_mw: float = 2.0  
    wind_eff: float = 0.95  
    pv_eff: float = 0.90  
    tidal_eff: float = 0.85  
    coll_loss: float = 0.02  
    aux_ratio: float = 0.015  
    def total_mw(self): return self.wind_mw + self.pv_mw + self.tidal_mw 
@dataclass  
class BessParams:  
    power_mw: float = 20.0  
    energy_mwh: float = 80.0  
    min_soc: float = 0.1  
    max_soc: float = 0.9  
    init_soc: float = 0.5  
    chg_eff: float = 0.92  
    dis_eff: float = 0.92  
  
@dataclass  
class H2Params:  
    elec_mw: float = 10.0  
    sec_kwh_kg: float = 55.0  
    tank_kg: float = 500.0  
    init_kg: float = 100.0  
    min_kg: float = 0.0  
    max_kg: float = 500.0 
@dataclass  
class ComputingParams:  
    dc_facility_mw: float = 15.0  
    it_mw: float = 10.0  
    base_mw: float = 5.0  
    pue: float = 1.35  
  
@dataclass  
class ExportParams:  
    cable_mw: float = 40.0  
    cable_km: float = 50.0  
    loss_per_km: float = 0.001  
    loss_fixed: float = 0.005  
  
@dataclass  
class MarineParams:  
    load_mw: float = 2.0 
@dataclass  
class CommonCaseV1:  
    case_id: str = 'common_case_v1'  
    s: SourceParams = field(default_factory=SourceParams)  
    bess: BessParams = field(default_factory=BessParams)  
    h2: H2Params = field(default_factory=H2Params)  
    comp: ComputingParams = field(default_factory=ComputingParams)  
    exp: ExportParams = field(default_factory=ExportParams)  
    marine: MarineParams = field(default_factory=MarineParams)  
    dt_hour: float = 1.0 
# ============================================================  
# Part 3: Port Classes (request-accept-actual)  
# ============================================================  
@dataclass  
class PortBase:  
    name: str  
    mp: str  
    direction: PortDirection  
    governance: GovernanceSection  
    raa: RequestAcceptActual = field(default_factory=RequestAcceptActual)  
  
@dataclass  
class SourcePort:  
    name: str = 'Source'  
    mp: str = MP.SOURCE_POI  
    direction: PortDirection = PortDirection.INJECT  
    gov: GovernanceSection = GovernanceSection.S4_3  
    p_actual_mw: float = 0.0  
    p_aux_mw: float = 0.0  
    p_gross_mw: float = 0.0  
    coll_loss_mw: float = 0.0  
    def net_inject_mw(self): return self.p_actual_mw - self.p_aux_mw 
@dataclass  
class BessPort:  
    name: str = 'BESS'  
    mp: str = MP.COMMON_BUS  
    gov: GovernanceSection = GovernanceSection.S4_5  
    params: BessParams = field(default_factory=BessParams)  
    p_ch_mw: float = 0.0  
    p_dis_mw: float = 0.0  
    soc: float = 0.5  
    def net_mw(self): return self.p_dis_mw - self.p_ch_mw  
    def update_soc(self, dt_h):  
        e_ch = self.p_ch_mw * dt_h * self.params.chg_eff  
        e_dis = self.p_dis_mw * dt_h / self.params.dis_eff  
        de = (e_ch - e_dis) / self.params.energy_mwh  
        self.soc = max(self.params.min_soc, min(self.params.max_soc, self.soc + de)) 
@dataclass  
class ElectrolyzerPort:  
    name: str = 'Electrolyzer'  
    mp: str = MP.ELECTROLYZER  
    gov: GovernanceSection = GovernanceSection.S4_5  
    p_actual_mw: float = 0.0  
    h2_prod_kg: float = 0.0  
  
@dataclass  
class DcFacilityPort:  
    name: str = 'DC_Facility'  
    mp: str = MP.DC_FACILITY  
    gov: GovernanceSection = GovernanceSection.S4_6  
    p_actual_mw: float = 0.0  
    p_it_mw: float = 0.0  
    p_cooling_mw: float = 0.0  
  
@dataclass  
class ExportPort:  
    name: str = 'Export'  
    mp: str = MP.CABLE_SEND  
    gov: GovernanceSection = GovernanceSection.S4_7  
    p_send_mw: float = 0.0  
    p_receive_mw: float = 0.0  
    cable_loss_mw: float = 0.0  
  
@dataclass  
class MarinePort:  
    name: str = 'Marine'  
    mp: str = MP.COMMON_BUS  
    gov: GovernanceSection = GovernanceSection.S4_7  
    p_actual_mw: float = 0.0  
  
@dataclass  
class GridImportPort:  
    name: str = 'GridImport'  
    p_actual_mw: float = 0.0  
  
@dataclass  
class SpillPort:  
    name: str = 'Spill'  
    p_actual_mw: float = 0.0 
# ============================================================  
# Part 4: Common Bus Power Balance (MP-04)  
# ============================================================  
class CommonBusBalance:  
    def __init__(self):  
        self.source = SourcePort()  
        self.bess = BessPort()  
        self.elec = ElectrolyzerPort()  
        self.dc = DcFacilityPort()  
        self.export = ExportPort()  
        self.marine = MarinePort()  
        self.grid = GridImportPort()  
        self.spill = SpillPort()  
        self.p_post_poi_loss = 0.0  
        self.p_common_aux = 0.0  
        self.p_residual = 0.0 
# ------------------------------------------------------------  
# Core Power Conservation at MP-04-COMMON-BUS  
# pSource + pGridImport + pBessDis  
# = pBessCh + pElec + pDC + pExportSend + pMarine + pSpill + Losses  
# ------------------------------------------------------------  
    def solve(self):  
        s = self.source.net_inject_mw()  
        b_net = self.bess.net_mw()  
        g = self.grid.p_actual_mw  
        e = self.elec.p_actual_mw  
        d = self.dc.p_actual_mw  
        x = self.export.p_send_mw  
        m = self.marine.p_actual_mw  
        sp = self.spill.p_actual_mw  
        lp = self.p_post_poi_loss + self.p_common_aux  
        self.p_residual = s + g + b_net - e - d - x - m - sp - lp  
        return self.get_metrics() 
    def get_metrics(self):  
        m = PowerBalanceMetrics()  
        m.p_source_actual = self.source.p_actual_mw  
        m.p_source_aux = self.source.p_aux_mw  
        m.p_bess_discharge = self.bess.p_dis_mw  
        m.p_bess_charge = self.bess.p_ch_mw  
        m.p_electrolyzer = self.elec.p_actual_mw  
        m.p_dc_facility = self.dc.p_actual_mw  
        m.p_export_send = self.export.p_send_mw  
        m.p_marine = self.marine.p_actual_mw  
        m.p_grid_import = self.grid.p_actual_mw  
        m.p_spill = self.spill.p_actual_mw  
        m.p_post_poi_loss = self.p_post_poi_loss  
        m.p_common_aux = self.p_common_aux  
        m.p_residual = self.p_residual  
        return m 
# ============================================================  
# Part 5: Loss Model (per responsibility per interface spec)  
# ============================================================  
class LossModel:  
    def compute_source_losses(self, src: SourcePort):  
        src.coll_loss_mw = src.p_gross_mw * 0.02  
        src.p_actual_mw = src.p_gross_mw - src.coll_loss_mw  
        src.p_aux_mw = src.p_actual_mw * 0.015  
  
    def compute_cable_losses(self, exp: ExportPort, params: ExportParams):  
        exp.cable_loss_mw = exp.p_send_mw * (params.loss_fixed + params.loss_per_km * params.cable_km)  
        exp.p_receive_mw = exp.p_send_mw - exp.cable_loss_mw  
  
    def compute_common_losses(self, total_flow, params):  
        post_poi = total_flow * 0.01  
        common_aux = total_flow * 0.005  
        return post_poi, common_aux 
# ============================================================  
# Part 6: Scenario Setup and Simulation  
# ============================================================  
def create_common_case(params=None):  
    if params is None: params = CommonCaseV1()  
    cb = CommonBusBalance()  
    return cb, params  
  
def run_balance(cb, params, scenario_type='base'):  
    lm = LossModel()  
    s = params.s  
    if scenario_type == 'base':  
        wf = 0.7; pf = 0.6; tf = 0.5  # source capacity factors  
        lf = 0.7  # load factor  
    elif scenario_type == 'peak':  
        wf = 0.3; pf = 0.2; tf = 0.4; lf = 0.9  
    else:  
        wf = 0.5; pf = 0.5; tf = 0.5; lf = 0.5  
    gross = s.wind_mw*wf + s.pv_mw*pf + s.tidal_mw*tf  
    cb.source.p_gross_mw = gross  
    lm.compute_source_losses(cb.source)  
    cb.elec.p_actual_mw = params.h2.elec_mw * 0.6 * lf  
    cb.dc.p_actual_mw = params.comp.dc_facility_mw * lf  
    cb.dc.p_it_mw = params.comp.it_mw * lf  
    cb.dc.p_cooling_mw = cb.dc.p_actual_mw - cb.dc.p_it_mw  
    cb.export.p_send_mw = params.exp.cable_mw * 0.5 * lf  
    lm.compute_cable_losses(cb.export, params.exp)  
    cb.marine.p_actual_mw = params.marine.load_mw  
    total_flow = gross  
    cb.p_post_poi_loss, cb.p_common_aux = lm.compute_common_losses(total_flow, None)  
    cb.solve()  
    return cb.get_metrics() 
# ============================================================  
