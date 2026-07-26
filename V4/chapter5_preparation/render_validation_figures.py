from __future__ import annotations

from pathlib import Path

from render_v4_results import render_scenario


ROOT = Path(__file__).resolve().parents[1]


if __name__ == "__main__":
    render_scenario(ROOT / "outputs")
    render_scenario(ROOT / "outputs" / "chapter5_all_channel_48h")
