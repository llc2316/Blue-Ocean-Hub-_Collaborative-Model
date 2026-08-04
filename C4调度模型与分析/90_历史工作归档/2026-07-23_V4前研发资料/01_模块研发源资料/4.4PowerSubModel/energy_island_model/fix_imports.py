import os
base = r"C:\Users\86188\Documents\Codex\2026-07-20\ge\work\energy_island_model"
files_to_fix = [
    "scenarios/base_scenarios.py",
    "scenarios/__init__.py",
]
old = "..core."
new = "core."
for fn in files_to_fix:
    fp = os.path.join(base, fn)
    with open(fp, "r", encoding="utf-8") as f:
        c = f.read()
    c = c.replace(old, new)
    with open(fp, "w", encoding="utf-8") as f:
        f.write(c)
    print("Fixed:", fn)
print("Done")
import os
base = r"C:\Users\86188\Documents\Codex\2026-07-20\ge\work\energy_island_model"
files_to_fix = [
    "scenarios/base_scenarios.py",
    "scenarios/__init__.py",
    "visualization/__init__.py",
    "visualization/plots.py",
]
old_dotdot = "..core."
new_dot = "core."
for fn in files_to_fix:
    fp = os.path.join(base, fn)
    with open(fp, "r", encoding="utf-8") as f:
        c = f.read()
    c = c.replace(old_dotdot, new_dot)
    with open(fp, "w", encoding="utf-8") as f:
        f.write(c)
    print("Fixed:", fn)
print("Done")
