from core.components import EnergyIslandSystem, SourceUnit, SourceType, StorageUnit, StorageType, ComputingUnit, LoadUnit
def create_base_scenario():
    s = EnergyIslandSystem(name="Base")
    s.add_source(SourceUnit("Wind", SourceType.WIND_OFFSHORE, 100.0, 70.0, 0.95, 0.85))
    s.add_source(SourceUnit("Solar", SourceType.SOLAR_PV, 50.0, 30.0, 0.90, 0.75))
    s.add_storage(StorageUnit("Battery", StorageType.BATTERY_LI, 40.0, 160.0, 0.6, 0.1, 0.9, 0.92, 0.92))
    s.add_computing(ComputingUnit("DC", 30.0, 20.0, 0.67, 1.35, False))
    s.add_load(LoadUnit("Industrial", 40.0, 35.0, 1.0, True, False))
    s.add_load(LoadUnit("Residential", 20.0, 15.0, 1.0, False, True))
    return s
def create_stress_scenario():
    s = EnergyIslandSystem(name="Stress")
    s.add_source(SourceUnit("Wind", SourceType.WIND_OFFSHORE, 100.0, 20.0, 0.90, 0.85))
    s.add_source(SourceUnit("Solar", SourceType.SOLAR_PV, 50.0, 5.0, 0.85, 0.75))
    s.add_source(SourceUnit("Diesel", SourceType.DIESEL, 30.0, 30.0, 0.85, 1.0, False))
    s.add_storage(StorageUnit("Battery", StorageType.BATTERY_LI, 40.0, 160.0, 0.3, 0.1, 0.9, 0.92, 0.92))
    s.add_computing(ComputingUnit("DC", 30.0, 28.0, 0.93, 1.40, False))
    s.add_load(LoadUnit("Industrial", 40.0, 38.0, 1.0, True, False))
    s.add_load(LoadUnit("Residential", 20.0, 18.0, 1.0, False, True))
    return s
def create_parameter_sweep_scenario():
    res = []
    for s_lvl in [0.2, 0.4, 0.6, 0.8, 1.0]:
        for l_lvl in [0.6, 0.8, 1.0, 1.2]:
            s = EnergyIslandSystem(f"scan_{s_lvl}_{l_lvl}")
            s.add_source(SourceUnit("Wind", SourceType.WIND_OFFSHORE, 100.0, 100.0*s_lvl, 0.95, 0.85))
            s.add_source(SourceUnit("Solar", SourceType.SOLAR_PV, 50.0, 50.0*s_lvl, 0.90, 0.75))
            s.add_storage(StorageUnit("Battery", StorageType.BATTERY_LI, 40.0, 160.0, 0.5, 0.1, 0.9, 0.92, 0.92))
            s.add_computing(ComputingUnit("DC", 30.0, 20.0, 0.67, 1.35, False))
            s.add_load(LoadUnit("Industrial", 40.0, 40.0*l_lvl))
            s.add_load(LoadUnit("Residential", 20.0, 20.0*l_lvl))
            res.append((s_lvl, l_lvl, s))
    return res
