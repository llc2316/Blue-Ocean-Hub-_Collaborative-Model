from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def configure_chinese_font() -> None:
    """Use common Chinese fonts when available; otherwise keep Matplotlib fallback."""
    plt.rcParams["font.sans-serif"] = [
        "Microsoft YaHei",
        "SimHei",
        "Noto Sans CJK SC",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    plt.rcParams["axes.unicode_minus"] = False


def require_columns(df: pd.DataFrame, columns: Iterable[str]) -> None:
    missing = [column for column in columns if column not in df.columns]
    if missing:
        raise ValueError(f"hourly_results.csv 缺少字段: {missing}")


def save_current_figure(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(path, dpi=220, bbox_inches="tight")
    plt.close()


def load_inputs(input_dir: Path) -> tuple[pd.DataFrame, dict]:
    hourly_path = input_dir / "hourly_results.csv"
    summary_path = input_dir / "summary.json"

    if not hourly_path.exists():
        raise FileNotFoundError(f"未找到 {hourly_path}，请先运行模型。")
    if not summary_path.exists():
        raise FileNotFoundError(f"未找到 {summary_path}，请先运行模型。")

    df = pd.read_csv(hourly_path)
    if "timestamp" not in df.columns:
        raise ValueError("hourly_results.csv 缺少 timestamp 字段。")
    df["timestamp"] = pd.to_datetime(df["timestamp"], errors="raise")

    with summary_path.open("r", encoding="utf-8") as file:
        summary = json.load(file)

    return df, summary


def plot_workload_arrival_and_service(df: pd.DataFrame, out: Path) -> None:
    require_columns(
        df,
        [
            "timestamp",
            "rigid_arrival_mwh_it",
            "rigid_served_mwh_it",
            "flex_arrival_mwh_it",
            "flex_served_mwh_it",
        ],
    )
    x = df["timestamp"]
    plt.figure(figsize=(13, 5.5))
    plt.plot(x, df["rigid_arrival_mwh_it"], label="刚性任务到达")
    plt.plot(x, df["rigid_served_mwh_it"], label="刚性任务执行")
    plt.plot(x, df["flex_arrival_mwh_it"], label="柔性任务到达")
    plt.plot(x, df["flex_served_mwh_it"], label="柔性任务执行")
    plt.xlabel("时间")
    plt.ylabel("每小时任务工作量（MWh-IT）")
    plt.title("算力任务到达与优化执行结果")
    plt.legend(ncol=2)
    plt.grid(alpha=0.25)
    save_current_figure(out / "01_任务到达与执行.png")


def plot_flexible_queue(df: pd.DataFrame, out: Path) -> None:
    require_columns(df, ["timestamp", "flex_queue_mwh_it"])
    plt.figure(figsize=(13, 4.8))
    plt.plot(df["timestamp"], df["flex_queue_mwh_it"], label="柔性任务队列")
    plt.fill_between(df["timestamp"], 0, df["flex_queue_mwh_it"], alpha=0.25)
    plt.xlabel("时间")
    plt.ylabel("待处理任务量（MWh-IT）")
    plt.title("柔性任务积压与清空过程")
    plt.legend()
    plt.grid(alpha=0.25)
    save_current_figure(out / "02_柔性任务队列.png")


def plot_power_stack(df: pd.DataFrame, out: Path) -> None:
    require_columns(
        df,
        ["timestamp", "it_power_mw", "cooling_power_mw", "dc_power_mw", "dc_power_cap_mw"],
    )
    other_overhead = (
        df["dc_power_mw"] - df["it_power_mw"] - df["cooling_power_mw"]
    ).clip(lower=0.0)

    plt.figure(figsize=(13, 5.5))
    plt.stackplot(
        df["timestamp"],
        df["it_power_mw"],
        df["cooling_power_mw"],
        other_overhead,
        labels=["IT功率", "冷却功率", "供配电及固定辅助损耗"],
        alpha=0.75,
    )
    plt.plot(df["timestamp"], df["dc_power_cap_mw"], label="DC功率上限")
    plt.xlabel("时间")
    plt.ylabel("功率（MW）")
    plt.title("数据中心功率构成与外部功率上限")
    plt.legend(ncol=2)
    plt.grid(alpha=0.25)
    save_current_figure(out / "03_DC功率构成与上限.png")


def plot_pue_and_temperature(df: pd.DataFrame, out: Path) -> None:
    require_columns(df, ["timestamp", "pue", "sea_temperature_c"])

    fig, ax_pue = plt.subplots(figsize=(13, 5.2))
    ax_temp = ax_pue.twinx()

    line_pue = ax_pue.plot(df["timestamp"], df["pue"], label="动态PUE")
    line_temp = ax_temp.plot(df["timestamp"], df["sea_temperature_c"], label="海水温度")

    ax_pue.set_xlabel("时间")
    ax_pue.set_ylabel("PUE")
    ax_temp.set_ylabel("海水温度（℃）")
    ax_pue.set_title("动态PUE与海水温度时序")
    ax_pue.grid(alpha=0.25)

    lines = line_pue + line_temp
    labels = [line.get_label() for line in lines]
    ax_pue.legend(lines, labels, loc="best")

    fig.tight_layout()
    fig.savefig(out / "04_动态PUE与海温.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def plot_pue_driver_scatter(df: pd.DataFrame, out: Path) -> None:
    require_columns(df, ["sea_temperature_c", "pue", "it_load_ratio"])

    marker_size = 25.0 + 100.0 * df["it_load_ratio"].clip(lower=0.0, upper=1.0)
    corr_temp = float(df[["sea_temperature_c", "pue"]].corr().iloc[0, 1])
    corr_load = float(df[["it_load_ratio", "pue"]].corr().iloc[0, 1])

    plt.figure(figsize=(8.5, 6.0))
    plt.scatter(
        df["sea_temperature_c"],
        df["pue"],
        s=marker_size,
        alpha=0.6,
        label="每小时运行点（点大小代表IT负载率）",
    )
    plt.xlabel("海水温度（℃）")
    plt.ylabel("PUE")
    plt.title("海温、IT负载与PUE的关系")
    plt.text(
        0.02,
        0.98,
        f"corr(海温, PUE) = {corr_temp:.3f}\ncorr(IT负载率, PUE) = {corr_load:.3f}",
        transform=plt.gca().transAxes,
        va="top",
    )
    plt.legend()
    plt.grid(alpha=0.25)
    save_current_figure(out / "05_PUE驱动因素散点图.png")


def plot_energy_breakdown(summary: dict, out: Path) -> None:
    it_energy = float(summary["total_it_energy_mwh"])
    cooling_energy = float(summary["total_cooling_energy_mwh"])
    dc_energy = float(summary["total_dc_energy_mwh"])
    other_energy = max(dc_energy - it_energy - cooling_energy, 0.0)

    labels = ["IT设备", "冷却系统", "供配电及固定辅助"]
    values = [it_energy, cooling_energy, other_energy]

    plt.figure(figsize=(8.5, 5.5))
    bars = plt.bar(labels, values)
    plt.ylabel("168小时能耗（MWh）")
    plt.title("数据中心能耗构成")
    plt.grid(axis="y", alpha=0.25)
    for bar, value in zip(bars, values):
        plt.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height(),
            f"{value:.1f}",
            ha="center",
            va="bottom",
        )
    save_current_figure(out / "06_能耗构成.png")


def plot_economic_breakdown(summary: dict, out: Path) -> None:
    revenue = float(summary["total_compute_revenue_yuan"]) / 10000.0
    electricity = float(summary["total_electricity_cost_yuan"]) / 10000.0
    penalty = float(summary["total_unmet_penalty_yuan"]) / 10000.0
    margin = float(summary["electricity_contribution_margin_yuan"]) / 10000.0

    labels = ["算力收入", "电费", "任务惩罚", "电力边际贡献"]
    values = [revenue, electricity, penalty, margin]

    plt.figure(figsize=(9.5, 5.5))
    bars = plt.bar(labels, values)
    plt.ylabel("金额（万元/168小时）")
    plt.title("算力中心经济结果构成")
    plt.grid(axis="y", alpha=0.25)
    for bar, value in zip(bars, values):
        plt.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height(),
            f"{value:.1f}",
            ha="center",
            va="bottom",
        )
    save_current_figure(out / "07_经济结果构成.png")


def plot_cumulative_economics(df: pd.DataFrame, out: Path) -> None:
    require_columns(
        df,
        [
            "timestamp",
            "rigid_revenue_yuan",
            "flex_revenue_yuan",
            "spot_revenue_yuan",
            "electricity_cost_yuan",
            "electricity_contribution_margin_yuan",
        ],
    )
    revenue = (
        df["rigid_revenue_yuan"]
        + df["flex_revenue_yuan"]
        + df["spot_revenue_yuan"]
    ).cumsum() / 10000.0
    electricity = df["electricity_cost_yuan"].cumsum() / 10000.0
    margin = df["electricity_contribution_margin_yuan"].cumsum() / 10000.0

    plt.figure(figsize=(13, 5.5))
    plt.plot(df["timestamp"], revenue, label="累计算力收入")
    plt.plot(df["timestamp"], electricity, label="累计电费")
    plt.plot(df["timestamp"], margin, label="累计电力边际贡献")
    plt.xlabel("时间")
    plt.ylabel("累计金额（万元）")
    plt.title("168小时累计经济结果")
    plt.legend()
    plt.grid(alpha=0.25)
    save_current_figure(out / "08_累计收入电费与边际贡献.png")


def plot_load_duration_curve(df: pd.DataFrame, out: Path) -> None:
    require_columns(df, ["it_load_ratio"])
    sorted_load = np.sort(df["it_load_ratio"].to_numpy(float))[::-1] * 100.0
    rank = np.arange(1, len(sorted_load) + 1)

    plt.figure(figsize=(9.5, 5.5))
    plt.plot(rank, sorted_load, label="IT负载持续曲线")
    plt.axhline(float(np.mean(sorted_load)), label=f"平均负载率 {np.mean(sorted_load):.1f}%")
    plt.xlabel("按负载率从高到低排列的小时序号")
    plt.ylabel("IT负载率（%）")
    plt.title("IT负载持续曲线")
    plt.legend()
    plt.grid(alpha=0.25)
    save_current_figure(out / "09_IT负载持续曲线.png")


def save_visual_summary(df: pd.DataFrame, summary: dict, out: Path) -> None:
    metrics = [
        ("仿真时长", summary.get("hours"), "h"),
        ("合同任务完成率", 100.0 * float(summary.get("contract_service_rate", np.nan)), "%"),
        ("平均IT负载率", 100.0 * float(summary.get("average_it_load_ratio", np.nan)), "%"),
        ("平均PUE", summary.get("average_pue"), "-"),
        ("最低PUE", summary.get("min_pue"), "-"),
        ("最高PUE", summary.get("max_pue"), "-"),
        ("IT能耗", summary.get("total_it_energy_mwh"), "MWh"),
        ("冷却能耗", summary.get("total_cooling_energy_mwh"), "MWh"),
        ("DC总能耗", summary.get("total_dc_energy_mwh"), "MWh"),
        ("算力收入", float(summary.get("total_compute_revenue_yuan", np.nan)) / 10000.0, "万元"),
        ("电费", float(summary.get("total_electricity_cost_yuan", np.nan)) / 10000.0, "万元"),
        (
            "电力边际贡献",
            float(summary.get("electricity_contribution_margin_yuan", np.nan)) / 10000.0,
            "万元",
        ),
        ("海温最低值", float(df["sea_temperature_c"].min()), "℃"),
        ("海温最高值", float(df["sea_temperature_c"].max()), "℃"),
    ]
    pd.DataFrame(metrics, columns=["指标", "数值", "单位"]).to_csv(
        out / "visualization_summary.csv", index=False, encoding="utf-8-sig"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="生成UDC DC-only模型报告可视化")
    parser.add_argument(
        "--input",
        default="outputs/base_case",
        help="包含hourly_results.csv和summary.json的模型输出目录",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="图表输出目录；默认是<input>/figures",
    )
    args = parser.parse_args()

    configure_chinese_font()
    input_dir = Path(args.input).resolve()
    output_dir = Path(args.output).resolve() if args.output else input_dir / "figures"
    output_dir.mkdir(parents=True, exist_ok=True)

    df, summary = load_inputs(input_dir)

    plot_workload_arrival_and_service(df, output_dir)
    plot_flexible_queue(df, output_dir)
    plot_power_stack(df, output_dir)
    plot_pue_and_temperature(df, output_dir)
    plot_pue_driver_scatter(df, output_dir)
    plot_energy_breakdown(summary, output_dir)
    plot_economic_breakdown(summary, output_dir)
    plot_cumulative_economics(df, output_dir)
    plot_load_duration_curve(df, output_dir)
    save_visual_summary(df, summary, output_dir)

    print(f"可视化生成完成：{output_dir}")
    for path in sorted(output_dir.glob("*.png")):
        print(f"- {path.name}")
    print("- visualization_summary.csv")


if __name__ == "__main__":
    main()
