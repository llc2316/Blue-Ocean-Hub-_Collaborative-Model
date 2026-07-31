from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from udc_dc_only.config import load_config
from udc_dc_only.data_loader import load_inputs


def main() -> None:
    parser = argparse.ArgumentParser(description="检查UDC_data输入完整性与单位兼容性")
    parser.add_argument("--config", default=str(ROOT / "config" / "default.json"))
    parser.add_argument("--data-root", default=None)
    args = parser.parse_args()
    cfg = load_config(args.config)
    data_root = Path(args.data_root or cfg["data_root"])
    if not data_root.is_absolute():
        data_root = ROOT / data_root
    bundle = load_inputs(data_root, cfg)
    report = {"warnings": bundle.warnings, "diagnostics": bundle.diagnostics}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("\n数据检查完成。警告不一定阻止运行，但应在报告中披露。")


if __name__ == "__main__":
    main()
