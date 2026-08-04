import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scenarios.base_scenarios import create_base_scenario
from visualization.plots import plot_power_balance, plot_system_overview
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "outputs")
os.makedirs(out_dir, exist_ok=True)
sys = create_base_scenario()
res = sys.solve()
print("Generation:", res.total_generation_mw)
print("Load:", res.total_load_mw)
print("Computing:", res.total_computing_mw)
print("Loss:", res.total_loss_mw)
print("Reserve Gap:", res.reserve_gap_mw)
print("Net Imbalance:", res.net_imbalance_mw)
print("Status:", res.status.value)
fig1 = plot_power_balance(sys, res, save_path=os.path.join(out_dir, "base_scenario.png"))
fig2 = plot_system_overview(sys, save_path=os.path.join(out_dir, "system_overview.png"))
print("Plots saved successfully!")
print("Output directory:", out_dir)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matplotlib
matplotlib.use("Agg")
from scenarios.base_scenarios import create_base_scenario, create_stress_scenario, create_parameter_sweep_scenario
from visualization.plots import plot_power_balance, plot_system_overview, plot_parameter_sweep
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "outputs")
os.makedirs(out_dir, exist_ok=True)

print("="*60)
print("Scene 1: Base")
print("="*60)
s1 = create_base_scenario()
r1 = s1.solve()
print(f"Gen:{r1.total_generation_mw:.2f} Load:{r1.total_load_mw:.2f} Comp:{r1.total_computing_mw:.2f}")
print(f"Loss:{r1.total_loss_mw:.2f} Resv:{r1.reserve_gap_mw:.2f} Net:{r1.net_imbalance_mw:.2f}")
print(f"Status:{r1.status.value}")
plot_power_balance(s1, r1, save_path=os.path.join(out_dir, "base_scenario.png"))
plot_system_overview(s1, save_path=os.path.join(out_dir, "system_overview.png"))
print("Plots saved")

print("="*60)
print("Scene 2: Stress")
print("="*60)
s2 = create_stress_scenario()
r2 = s2.solve()
print(f"Gen:{r2.total_generation_mw:.2f} Load:{r2.total_load_mw:.2f} Comp:{r2.total_computing_mw:.2f}")
print(f"Loss:{r2.total_loss_mw:.2f} Resv:{r2.reserve_gap_mw:.2f} Net:{r2.net_imbalance_mw:.2f}")
print(f"Status:{r2.status.value}")
plot_power_balance(s2, r2, save_path=os.path.join(out_dir, "stress_scenario.png"))
print("Plots saved")

print("="*60)
print("Scene 3: Parameter Sweep")
print("="*60)
scenarios = create_parameter_sweep_scenario()
results = []
for sl, ll, s in scenarios:
    results.append((sl, ll, s.solve()))
print(f"Completed {len(results)} points")
plot_parameter_sweep(results, save_path=os.path.join(out_dir, "param_sweep.png"))
print("Plots saved")

print("="*60)
print("All done! Outputs in:", out_dir)
print("="*60)
