import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core.components import EnergyIslandSystem, SourceUnit, SourceType, StorageUnit, StorageType, ComputingUnit, LoadUnit
from core.power_balance import BalanceStatus
from scenarios.base_scenarios import create_base_scenario, create_stress_scenario, create_parameter_sweep_scenario
from visualization.plots import plot_power_balance, plot_system_overview, plot_parameter_sweep
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "outputs")
os.makedirs(out_dir, exist_ok=True)
def run_base():
    print("="*60)
    print("Scene 1: Base")
    print("="*60)
    sys = create_base_scenario()
    print(sys)
    res = sys.solve()
    print(f"  Gen:{res.total_generation_mw:>8.2f}  StgDis:{res.storage_discharge_mw:>8.2f}  Load:{res.total_load_mw:>8.2f}")
    print(f"  Comp:{res.total_computing_mw:>8.2f}  StgChg:{res.storage_charge_mw:>8.2f}  Loss:{res.total_loss_mw:>8.2f}")
    print(f"  ResvGap:{res.reserve_gap_mw:>8.2f}  Net:{res.net_imbalance_mw:>8.2f}  Status:{res.status.value}")
    print(f"  SurplusRatio: {res.surplus_ratio():.2%}")
    plot_power_balance(sys, res, save_path=os.path.join(out_dir,"base_scenario.png"))
    plot_system_overview(sys, save_path=os.path.join(out_dir,"system_overview.png"))
    return sys, res
def run_stress():
    print("="*60)
    print("Scene 2: Stress")
    print("="*60)
    sys = create_stress_scenario()
    print(sys)
    res = sys.solve()
    print(f"  Gen:{res.total_generation_mw:>8.2f}  StgDis:{res.storage_discharge_mw:>8.2f}  Load:{res.total_load_mw:>8.2f}")
    print(f"  Comp:{res.total_computing_mw:>8.2f}  StgChg:{res.storage_charge_mw:>8.2f}  Loss:{res.total_loss_mw:>8.2f}")
    print(f"  ResvGap:{res.reserve_gap_mw:>8.2f}  Net:{res.net_imbalance_mw:>8.2f}  Status:{res.status.value}")
    plot_power_balance(sys, res, save_path=os.path.join(out_dir,"stress_scenario.png"))
    return sys, res
def run_sweep():
    print("="*60)
    print("Scene 3: Parameter Sweep")
    print("="*60)
    scenarios = create_parameter_sweep_scenario()
    results = []
    for sl, ll, sys in scenarios:
        results.append((sl, ll, sys.solve()))
    print(f"Completed {len(results)} points")
    plot_parameter_sweep(results, save_path=os.path.join(out_dir,"param_sweep.png"))
    return results
if __name__ == "__main__":
    run_base()
    run_stress()
    run_sweep()
    print("\nDone!")
    print(f"Outputs in: {out_dir}")
