import os
base = r"C:/Users/86188/Documents/Codex/2026-07-20/ge/work/island_power_balance"
def w(p, c):
    fn = os.path.join(base, p)
    os.makedirs(os.path.dirname(fn), exist_ok=True)
    with open(fn, "w", encoding="utf-8") as f:
        f.write(c)
    print("Wrote:", p)
print("Builder ready")
print("test")
print("step2")
w("core/__init__.py", "from .interfaces import MP, PortDirection\nfrom .ports import PortBase, SourcePort\n")
