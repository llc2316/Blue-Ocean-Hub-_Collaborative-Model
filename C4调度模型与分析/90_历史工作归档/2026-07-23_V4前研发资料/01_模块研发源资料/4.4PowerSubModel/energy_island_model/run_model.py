import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from main import run_base, run_stress, run_sweep
if __name__ == "__main__":
    run_base()
    run_stress()
    run_sweep()
    print("Done.")
