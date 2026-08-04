from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from udc_dc_only.config import load_config
from udc_dc_only.data_loader import load_inputs
from udc_dc_only.raw_model import solve_dc_only

from udc_dc_only.reporting import save_outputs


def main() -> None:
    parser = argparse.ArgumentParser(description="运行深蓝海能源岛DC-only算力中心模型")
    parser.add_argument("--config", default=str(ROOT / "config" / "default.json"))
    parser.add_argument("--data-root", default=None, help="UDC_data文件夹路径")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    cfg = load_config(args.config)
    data_root = Path(args.data_root or cfg["data_root"])
    if not data_root.is_absolute():
        data_root = ROOT / data_root
    output = Path(args.output or cfg["output_dir"])
    if not output.is_absolute():
        output = ROOT / output

    bundle = load_inputs(data_root, cfg)
    result = solve_dc_only(bundle, cfg)
    save_outputs(result, output, bundle.warnings, bundle.diagnostics, cfg)

    print("模型运行完成")
    print(f"输出目录: {output}")
    print(json.dumps(result.summary, ensure_ascii=False, indent=2))
    if bundle.warnings:
        print("\n数据警告:")
        for warning in bundle.warnings:
            print(f"- {warning}")
    if not result.audit["passed"]:
        raise RuntimeError(f"结果审计未通过: {result.audit}")


if __name__ == "__main__":
    main()
