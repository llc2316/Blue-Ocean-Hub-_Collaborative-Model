import os
base = r"C:\Users\86188\Documents\Codex\2026-07-20\ge\work\energy_island_model"
def w(p, c):
    fn = os.path.join(base, p)
    os.makedirs(os.path.dirname(fn), exist_ok=True)
    with open(fn, "w", encoding="utf-8") as f:
        f.write(c)
    print("Wrote:", fn)
print("Builder ready")
