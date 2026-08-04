# Generator for comprehensive island model  
import os  
base = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_v2'  
out = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\outputs\v3'  
os.makedirs(out, exist_ok=True)  
def w(p, c):  
    fn = os.path.join(base, p)  
    os.makedirs(os.path.dirname(fn), exist_ok=True)  
    with open(fn, 'w', encoding='utf-8') as f:  
        f.write(c)  
    print('Wrote:', p)  
print('Generator ready') 
import os, sys, math  
from dataclasses import dataclass, field  
from enum import Enum  
from datetime import datetime  
  
PIPE = chr(124)   
BASE = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_v2'  
OUT = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\outputs\v3'  
os.makedirs(OUT, exist_ok=True) 
# ======== Symbol Table for Report ========  
SYMBOLS = {  
  'P_w': 'mW', 'P_pv': 'mW', 'P_t': 'mW', 'v_w': 'm/s', 'G': 'W/m2',  
  'SOC': '[0,1]', 'E_b': 'MWh', 'eta_ch': '-', 'eta_dis': '-',  
  'SEC': 'kWh/kg', 'm_H2': 'kg', 'PUE': '-', 'P_DC': 'mW',  
  'P_cable': 'mW', 'L_cable': 'km', 'rho_loss': '-', 'P_res': 'mW',  
  'P_aux': 'mW', 'P_spill': 'mW', 'P_unserved': 'mW',  
  'CF': '-', 'P_rated': 'mW', 'P_actual': 'mW', 'dt': 'h',  
}  
  
# ======== Parameter Classes ========  
@dataclass  
class SourceParams:  
    wind_mw: float = 34.0; pv_mw: float = 4.0; tidal_mw: float = 2.0  
    wind_eff: float = 0.95; pv_eff: float = 0.90; tidal_eff: float = 0.85  
    coll_loss: float = 0.02; aux_ratio: float = 0.015  
    def total_mw(self): return self.wind_mw + self.pv_mw + self.tidal_mw 
@dataclass  
class BessParams:  
    power_mw: float = 20.0; energy_mwh: float = 80.0  
    min_soc: float = 0.1; max_soc: float = 0.9; init_soc: float = 0.5  
    chg_eff: float = 0.92; dis_eff: float = 0.92  
  
@dataclass  
class H2Params:  
    elec_mw: float = 10.0; sec_kwh_kg: float = 55.0; tank_kg: float = 500.0  
    init_kg: float = 100.0  
  
@dataclass  
class ComputingParams:  
    facility_mw: float = 15.0; it_mw: float = 10.0; pue: float = 1.35  
  
@dataclass  
class ExportParams:  
    cable_mw: float = 40.0; cable_km: float = 50.0  
    loss_per_km: float = 0.001; loss_fixed: float = 0.005  
  
@dataclass  
class MarineParams:  
    load_mw: float = 2.0 
@dataclass  
class CommonCaseV1:  
    s: SourceParams = field(default_factory=SourceParams)  
    bess: BessParams = field(default_factory=BessParams)  
    h2: H2Params = field(default_factory=H2Params)  
    comp: ComputingParams = field(default_factory=ComputingParams)  
    exp: ExportParams = field(default_factory=ExportParams)  
    marine: MarineParams = field(default_factory=MarineParams)  
    dt_hour: float = 1.0  
  
# ======== Sub-model 4.3: Multi-source Supply ========  
class SourceModel_4_3:  
    def __init__(self, params: SourceParams):  
        self.p = params  
    def wind_power(self, v_ms):  
        vci, vr, vco = 3.0, 12.0, 25.0  
        if v_ms >= vr: return self.p.wind_mw  
        return self.p.wind_mw * ((v_ms - vci) / (vr - vci))**3  
    def pv_power(self, g_wm2):  
        g_stc = 1000.0; k = -0.0035; t_cell = 25.0  
        p_mp = self.p.pv_mw * (g_wm2 / g_stc) * (1 + k * (t_cell - 25.0))  
        return max(0, p_mp)  
    def tidal_power(self, v_t_ms):  
        v_rated = 2.5  
        ratio = min(1.0, (v_t_ms / v_rated)**3)  
        return self.p.tidal_mw * ratio  
    def compute_output(self, v_w, g, v_t):  
        p_gross = self.wind_power(v_w) + self.pv_power(g) + self.tidal_power(v_t)  
        p_poi = p_gross * (1 - self.p.coll_loss)   
        p_aux = p_poi * self.p.aux_ratio  
        return dict(gross=p_gross, poi=p_poi, aux=p_aux, net=(p_poi - p_aux)) 
# ======== Sub-model 4.3 Multi-source Supply ========  
class SourceModel_4_3:  
    def __init__(self, p): self.p = p  
    def wind_power(self, v):  
        vci,vr,vco=3.0,12.0,25.0; v = abs(v)  
        if v >= vr: return self.p.wind_mw if v < vco else 0.0  
        if v < vci: return 0.0  
        return self.p.wind_mw * ((v-vci)/(vr-vci))**3  
    def pv_power(self, g): return max(0, self.p.pv_mw * g/1000.0)  
    def tidal_power(self, v): return self.p.tidal_mw * min(1.0, (abs(v)/2.5)**3)  
    def run(self, v_w, g, v_t):  
        pg = self.wind_power(v_w) + self.pv_power(g) + self.tidal_power(v_t)  
        po = pg * (1 - self.p.coll_loss); pa = po * self.p.aux_ratio  
        return dict(gross=pg, poi=po, aux=pa, net=(po-pa)) 
# ======== Sub-model 4.5: Battery + H2 ========  
class BessH2Model_4_5:  
    def __init__(self, bp, hp):  
        self.bp = bp; self.hp = hp; self.soc = bp.init_soc; self.h2_kg = hp.init_kg  
    def charge_bess(self, p_mw, dt):  
        p = min(p_mw, self.bp.power_mw); e = p * dt * self.bp.chg_eff  
        dsoc = e / self.bp.energy_mwh  
        self.soc = min(self.bp.max_soc, self.soc + dsoc); return p  
    def discharge_bess(self, p_mw, dt):  
        p = min(p_mw, self.bp.power_mw); e = p * dt / self.bp.dis_eff  
        dsoc = e / self.bp.energy_mwh  
        self.soc = max(self.bp.min_soc, self.soc - dsoc); return p  
    def run_electrolyzer(self, p_mw, dt):  
        p = min(p_mw, self.hp.elec_mw)  
        h2_prod = p * dt * 1000.0 / self.hp.sec_kwh_kg  
        self.h2_kg = min(self.hp.tank_kg, self.h2_kg + h2_prod)  
        return p, h2_prod 
# ======== Sub-model 4.6: Computing ========  
class ComputingModel_4_6:  
    def __init__(self, cp): self.cp = cp  
    def power_demand(self, utilization):  
        p_it = self.cp.it_mw * utilization  
        p_cooling = p_it * (self.cp.pue - 1.0)  
        total = p_it + p_cooling  
        return min(self.cp.facility_mw, total)  
  
# ======== Sub-model 4.7: Export + Marine ========  
class ExportMarineModel_4_7:  
    def __init__(self, ep, mp): self.ep = ep; self.mp = mp  
    def cable_loss(self, p_send):  
        return p_send * (self.ep.loss_fixed + self.ep.loss_per_km * self.ep.cable_km)  
    def export(self, p_send):  
        p_s = min(p_send, self.ep.cable_mw)  
        loss = self.cable_loss(p_s)  
        return dict(send=p_s, receive=(p_s - loss), loss=loss)  
    def marine_load(self): return self.mp.load_mw 
# ======== Common Bus Balance 4.4 ========  
class CommonBusBalance_4_4:  
    def solve(self, src, bess, comp, export, marine, grid, spill):  
        p_inject = src['net'] + grid + max(0, bess)  
        p_consume = comp + export + marine + spill + abs(min(0, bess))  
        post_loss = (p_inject + p_consume) * 0.01  
        common_aux = (p_inject + p_consume) * 0.005  
        residual = p_inject - p_consume - post_loss - common_aux  
        return dict(inject=p_inject, consume=p_consume,  
                post_loss=post_loss, common_aux=common_aux,  
                residual=residual, status=self._status(residual))  
    def _status(self, r):  
        tol = 0.001  
        if abs(r) < tol: return 'balanced'  
        if r < 0: return 'deficit'   
        return 'surplus' 
# ======== Simulation Runner ========  
def run_simulation(params, scenario):  
    s4_3 = SourceModel_4_3(params.s)  
    s4_5 = BessH2Model_4_5(params.bess, params.h2)  
    s4_6 = ComputingModel_4_6(params.comp)  
    s4_7 = ExportMarineModel_4_7(params.exp, params.marine)  
    s4_4 = CommonBusBalance_4_4()  
  
    if scenario == 'base': vw,g,vt,util=8,600,2.0,0.6  
    elif scenario == 'peak': vw,g,vt,util=4,200,1.0,0.9  
    else: vw,g,vt,util=6,400,1.5,0.7  
  
    src_res = s4_3.run(vw, g, vt)  
    dc_power = s4_6.power_demand(util)  
    export_res = s4_7.export(10.0)  
    marine_p = s4_7.marine_load()  
    elec_p = params.h2.elec_mw * 0.6  
    bess_p = 0.0  
  
    bal = s4_4.solve(src_res, bess_p, dc_power,  
        export_res['send'], marine_p, 0, 0)  
  
    return dict(params=params, scenario=scenario,  
        source=src_res, dc=dc_power, export=export_res,  
        marine=marine_p, electrolyzer=elec_p, balance=bal) 
# ======== Report Generator ========  
def generate_report(results):  
    P = chr(124); L = []; A = lambda s: L.append(s)  
    A('# 能源岛功率平衡模型 - 详细报告')  
    A('')  
    A('## 1 符号定义表')  
    A('')  
    A(f'{P} 符号 {P} 含义 {P} 单位 {P}')  
    A(f'{P} --- {P} --- {P} --- {P}')  
    A(f'{P} P_w {P} 风电功率 {P} MW {P}')  
    A(f'{P} P_pv {P} 光伏功率 {P} MW {P}')  
    A(f'{P} P_t {P} 潮流能功率 {P} MW {P}')  
    A(f'{P} v_w {P} 风速 {P} m/s {P}')  
    A(f'{P} G {P} 辐照度 {P} W/m2 {P}')  
    A(f'{P} SOC {P} 电池荷电状态 {P} [0,1] {P}')  
    A(f'{P} E_b {P} 电池容量 {P} MWh {P}')  
    A(f'{P} eta_ch {P} 充电效率 {P} - {P}')  
    A(f'{P} eta_dis {P} 放电效率 {P} - {P}')  
    A(f'{P} SEC {P} 电解槽比能耗 {P} kWh/kg {P}')  
    A(f'{P} m_H2 {P} 储氢量 {P} kg {P}')  
    A(f'{P} PUE {P} 电能使用效率 {P} - {P}')  
    A(f'{P} P_cable {P} 海缆功率 {P} MW {P}')  
    A(f'{P} L_cable {P} 海缆长度 {P} km {P}')  
    A(f'{P} rho_loss {P} 线路损耗率 {P} - {P}')  
    A(f'{P} P_res {P} 不平衡残差 {P} MW {P}')  
    A(f'{P} CF {P} 容量因子 {P} - {P}')  
    A(f'{P} dt {P} 时间步长 {P} h {P}') 
    A('')  
    A('## 2 子模型数学推导')  
    A('')  
    A('### 2.1 4.3 多源供给模型')  
    A('')  
    A('**风电出力模型**:')  
    A('P_wind(v) = 0, v in [0,vci) U (vco,inf)')  
    A('P_wind(v) = P_rated * (v - vci)3 / (vr - vci)3, v in [vci,vr]')  
    A('P_wind(v) = P_rated, v in (vr,vco]')  
    A('其中 vci=3m/s, vr=12m/s, vco=25m/s')  
    A('')  
    A('**光伏出力模型**:')  
    A('P_pv(G) = P_pv_rated * (G / G_stc) * [1 + k*(T_cell - 25)]')  
    A('G_stc = 1000 W/m2, k = -0.0035 /degC')  
    A('')  
    A('**潮流能出力模型**:')  
    A('P_tidal(v) = P_tidal_rated * min(1, (v/v_rated)3)')  
    A('v_rated = 2.5 m/s')  
    A('')  
    A('**汇集点功率**:')  
    A('P_poi = (P_wind + P_pv + P_tidal) * (1 - eta_collection)')  
    A('P_aux = P_poi * eta_aux')  
    A('P_net = P_poi - P_aux')  
    A('')  
    A('### 2.2 4.5 电池-制氢储氢模型')  
    A('')  
    A('**电池SOC状态方程**:')  
    A('SOC(t+dt) = SOC(t) + [P_ch*dt*eta_ch - P_dis*dt/eta_dis] / E_b')  
    A('')  
    A('**电解槽产氢模型**:')  
    A('m_H2(t) = P_elec * dt / SEC')  
    A('H2_stock(t+dt) = H2_stock(t) + m_H2(t) - m_H2_delivered(t)')  
    A('') 
test append  
