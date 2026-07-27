from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
plt.rcParams["font.sans-serif"] = [
    "Microsoft YaHei",
    "SimHei",
    "Noto Sans CJK SC",
    "DejaVu Sans",
]
plt.rcParams["axes.unicode_minus"] = False


KPI_LABELS = {
    "sourceEnergyMWh": "源侧发电量",
    "windEnergyMWh": "风电发电量",
    "pvEnergyMWh": "光伏发电量",
    "tidalEnergyMWh": "潮流能发电量",
    "bessChargeEnergyMWh": "电池充电量",
    "bessDischargeEnergyMWh": "电池放电量",
    "bessFinalSOC": "电池期末SOC",
    "electrolyzerEnergyMWh": "电解槽用电量",
    "h2ProducedKg": "制氢量",
    "h2DeliveredKg": "氢气交付量",
    "computeFacilityEnergyMWh": "算力设施用电",
    "computeDeliveredMWhCS": "算力服务交付",
    "marineServedMWh": "海洋用能服务",
    "marineUnservedMWh": "海洋未供能",
    "exportSendMWh": "海缆送端电量",
    "electricityDeliveredMWh": "电力受端交付",
    "spillEnergyMWh": "弃电量",
    "renewableUtilization": "新能源利用率",
    "totalCostCNY": "总成本",
    "totalRevenueCNY": "总收入",
    "economicNetCostCNY": "经济净成本",
    "grossCapexCNY": "初始总CAPEX",
    "constructionFinancingCNY": "建设期融资",
    "financedCapexCNY": "含建设期融资CAPEX",
    "annualDepreciationCNY": "年折旧",
    "annualFinancingCostCNY": "年融资成本",
    "annualFixedOMCNY": "年固定运维",
    "replacementPresentValueCNY": "替换成本现值",
    "annualReplacementReserveCNY": "年替换准备金",
    "lifecycleCostPresentValueCNY": "全寿命成本现值",
    "lifecycleNPVAfterPenaltyCNY": "含惩罚全寿命NPV",
    "lifecycleNPVBeforePenaltyCNY": "不含惩罚全寿命NPV",
    "lifecycleEmissionKgCO2e": "生命周期排放代理",
    "EENSMWh": "EENS",
    "maxAbsBusResidualMW": "最大母线残差",
}


ECONOMIC_LABELS = {
    "annualizedCapitalCostCNY": "年化资本成本",
    "depreciationCostCNY": "本周期折旧",
    "financingCostCNY": "本周期融资成本",
    "fixedOMCostCNY": "本周期固定运维",
    "replacementReserveCostCNY": "本周期替换准备金",
    "sourceVariableOMCostCNY": "源侧变动运维",
    "bessDegradationCostCNY": "电池退化",
    "bessOpeningInventoryCostCNY": "期初电池机会成本",
    "hydrogenVariableCostCNY": "制氢变动成本",
    "hydrogenOpeningInventoryCostCNY": "期初氢机会成本",
    "hydrogenPipeTransportCostCNY": "氢气管输",
    "hydrogenShipTransportCostCNY": "氢气船运",
    "electrolyzerStartCostCNY": "电解槽启动",
    "spillPenaltyCNY": "弃电惩罚",
    "unservedPenaltyCNY": "缺供惩罚",
    "computeSLAPenaltyCNY": "算力SLA罚金",
    "computeVariableOMCNY": "算力变动运维",
    "electricityRevenueCNY": "电力收入",
    "hydrogenRevenueCNY": "氢气收入",
    "computeGrossRevenueCNY": "算力毛收入",
    "marineServiceRevenueCNY": "海洋服务收入",
}


EMISSION_LABELS = {
    "annualizedEmbodiedEmissionKgCO2e": "年化隐含排放",
    "sourceEmissionKgCO2e": "源侧生命周期排放",
    "bessThroughputEmissionKgCO2e": "电池吞吐排放",
    "gridImportEmissionKgCO2e": "电网输入排放",
    "hydrogenDeliveryEmissionKgCO2e": "氢气交付排放",
}


def _step(ax, x, y, label, *, linewidth=1.8, linestyle="-"):
    ax.step(x, y, where="post", label=label, linewidth=linewidth, linestyle=linestyle)


def _save(fig, path: Path, manifest: list[dict[str, str]], kind: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=190, bbox_inches="tight")
    plt.close(fig)
    manifest.append({"kind": kind, "file": str(path.name)})


def _value(kpi: pd.DataFrame, indicator: str) -> float:
    rows = kpi.loc[kpi["indicator"] == indicator, "value"]
    return float(rows.iloc[0]) if not rows.empty else np.nan


def _format_value(value: float, unit: str) -> str:
    if not np.isfinite(value):
        return "N/A"
    if unit == "fraction":
        return f"{100 * value:,.2f}%"
    if unit == "p.u.":
        return f"{value:,.3f}"
    if unit in {"CNY", "kg", "kgCO2e"}:
        return f"{value:,.2f} {unit}"
    if unit == "MW":
        return f"{value:.3e} MW" if abs(value) < 0.001 else f"{value:,.3f} MW"
    return f"{value:,.3f} {unit}"


def render_kpi_table(kpi: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    ordered = [
        "sourceEnergyMWh",
        "windEnergyMWh",
        "pvEnergyMWh",
        "tidalEnergyMWh",
        "bessChargeEnergyMWh",
        "bessDischargeEnergyMWh",
        "electrolyzerEnergyMWh",
        "h2ProducedKg",
        "h2DeliveredKg",
        "computeFacilityEnergyMWh",
        "computeDeliveredMWhCS",
        "marineServedMWh",
        "marineUnservedMWh",
        "exportSendMWh",
        "electricityDeliveredMWh",
        "spillEnergyMWh",
        "renewableUtilization",
        "totalCostCNY",
        "totalRevenueCNY",
        "economicNetCostCNY",
        "grossCapexCNY",
        "constructionFinancingCNY",
        "financedCapexCNY",
        "annualDepreciationCNY",
        "annualFinancingCostCNY",
        "annualFixedOMCNY",
        "replacementPresentValueCNY",
        "annualReplacementReserveCNY",
        "lifecycleCostPresentValueCNY",
        "lifecycleNPVAfterPenaltyCNY",
        "lifecycleNPVBeforePenaltyCNY",
        "lifecycleEmissionKgCO2e",
        "EENSMWh",
        "maxAbsBusResidualMW",
    ]
    rows = []
    for indicator in ordered:
        match = kpi.loc[kpi["indicator"] == indicator]
        if match.empty:
            continue
        row = match.iloc[0]
        rows.append(
            [
                str(row["category"]),
                KPI_LABELS.get(indicator, indicator),
                _format_value(float(row["value"]), str(row["unit"])),
                str(row["dataSourceType"]),
            ]
        )

    fig_height = max(6.8, 0.34 * len(rows) + 1.5)
    fig, ax = plt.subplots(figsize=(13.2, fig_height))
    ax.axis("off")
    table = ax.table(
        cellText=rows,
        colLabels=["类别", "指标", "最终结果", "数据状态"],
        colWidths=[0.12, 0.28, 0.25, 0.35],
        cellLoc="left",
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1, 1.35)
    for (row, col), cell in table.get_celld().items():
        cell.set_linewidth(0.4)
        if row == 0:
            cell.set_text_props(weight="bold")
            cell.set_facecolor("#DCEAF7")
        elif row % 2 == 0:
            cell.set_facecolor("#F5F7FA")
    ax.set_title("最终指标汇总（与全周期时序结果分开展示）", pad=18)
    _save(fig, out / "01_最终KPI汇总.png", manifest, "final")


def render_economics(
    economics: pd.DataFrame, out: Path, manifest: list[dict[str, str]]
) -> None:
    data = economics.copy()
    data["signed"] = np.where(data["category"] == "revenue", -data["value"], data["value"])
    data = data.loc[data["value"].abs() > 1e-9].copy()
    data["label"] = data["item"].map(ECONOMIC_LABELS).fillna(data["item"])
    data = data.sort_values("signed")
    colors = np.where(data["signed"] >= 0, "#D55E00", "#0072B2")
    fig, ax = plt.subplots(figsize=(11.8, max(5.2, 0.43 * len(data) + 1.2)))
    ax.barh(data["label"], data["signed"] / 1e4, color=colors, alpha=0.86)
    ax.axvline(0, color="0.35", linewidth=0.8)
    ax.set_xlabel("金额 / 万元（收入以负值显示）")
    ax.set_title("经济成本与收入分项")
    ax.grid(axis="x", alpha=0.22)
    _save(fig, out / "02_经济收支分项.png", manifest, "final")


def render_environment_reliability(
    emissions: pd.DataFrame,
    kpi: pd.DataFrame,
    out: Path,
    manifest: list[dict[str, str]],
) -> None:
    data = emissions.copy()
    data["label"] = data["item"].map(EMISSION_LABELS).fillna(data["item"])
    fig, axes = plt.subplots(1, 2, figsize=(13.2, 5.4), constrained_layout=True)
    axes[0].barh(data["label"], data["value"], color="#009E73", alpha=0.85)
    axes[0].set_xlabel("kgCO2e")
    axes[0].set_title("环境指标分项")
    axes[0].grid(axis="x", alpha=0.22)

    reliability = [
        ("弃电量", _value(kpi, "spillEnergyMWh")),
        ("海洋未供能", _value(kpi, "marineUnservedMWh")),
        ("EENS", _value(kpi, "EENSMWh")),
    ]
    labels = [item[0] for item in reliability]
    values = [item[1] for item in reliability]
    axes[1].barh(labels, values, color="#CC79A7", alpha=0.85)
    axes[1].set_xlabel("MWh")
    axes[1].set_title("可靠性最终指标")
    axes[1].grid(axis="x", alpha=0.22)
    _save(fig, out / "03_环境与可靠性分项.png", manifest, "final")


def render_source(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    pairs = [
        ("windActualMW", "风电"),
        ("pvActualMW", "光伏"),
        ("tidalActualMW", "潮流能"),
    ]
    fig, axes = plt.subplots(
        2,
        1,
        figsize=(13.2, 7.2),
        sharex=True,
        constrained_layout=True,
        gridspec_kw={"height_ratios": [2.2, 1.4]},
    )
    _step(axes[0], x, detail["sourceAvailableMW"], "源侧可用功率", linestyle="--")
    _step(axes[0], x, detail["sourceActualMW"], "源侧实际功率", linewidth=2.1)
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("多源供能：可用功率与实际功率")
    axes[0].legend(frameon=False, ncol=2)
    axes[0].grid(True, alpha=0.22)
    for column, label in pairs:
        if column in detail:
            _step(axes[1], x, detail[column], label)
    axes[1].set_xlabel("时段起点 / h")
    axes[1].set_ylabel("分源功率 / MW")
    axes[1].legend(frameon=False, ncol=3)
    axes[1].grid(True, alpha=0.22)
    _save(fig, out / "01_多源供能时序.png", manifest, "timeseries")


def render_dispatch(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, axes = plt.subplots(
        2,
        1,
        figsize=(13.2, 7.4),
        sharex=True,
        constrained_layout=True,
        gridspec_kw={"height_ratios": [2.4, 1.2]},
    )
    for column, label in [
        ("sourceActualMW", "源侧实际功率"),
        ("marineActualMW", "海洋用能"),
        ("dcFacilityActualMW", "算力设施"),
        ("exportSendActualMW", "海缆外送"),
        ("electrolyzerActualMW", "电解槽"),
    ]:
        _step(axes[0], x, detail[column], label)
    _step(axes[0], x, detail["spillMW"], "弃电", linewidth=2.1, linestyle="--")
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("源—储—算—用实际功率分配")
    axes[0].legend(frameon=False, ncol=3)
    axes[0].grid(True, alpha=0.22)

    _step(axes[1], x, detail["totalUnservedMW"], "总缺供")
    _step(axes[1], x, detail["marineUnservedMW"], "海洋未供")
    _step(axes[1], x, detail["spillMW"], "弃电", linestyle="--")
    axes[1].set_xlabel("时段起点 / h")
    axes[1].set_ylabel("功率 / MW")
    axes[1].legend(frameon=False, ncol=3)
    axes[1].grid(True, alpha=0.22)
    _save(fig, out / "02_功率分配与供需状态.png", manifest, "timeseries")


def render_storage(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, axes = plt.subplots(
        2, 1, figsize=(13.2, 7.0), sharex=True, constrained_layout=True
    )
    _step(axes[0], x, detail["bessChargeActualMW"], "充电")
    _step(axes[0], x, -detail["bessDischargeActualMW"], "放电（负值）")
    axes[0].axhline(0, color="0.35", linewidth=0.8)
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("电池充放电及SOC全周期变化")
    axes[0].legend(frameon=False, ncol=2)
    axes[0].grid(True, alpha=0.22)
    _step(axes[1], x, 100 * detail["bessSOC"], "SOC", linewidth=2.0)
    axes[1].set_xlabel("时段起点 / h")
    axes[1].set_ylabel("SOC / %")
    axes[1].grid(True, alpha=0.22)
    _save(fig, out / "03_电池功率与SOC时序.png", manifest, "timeseries")


def render_hydrogen(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, axes = plt.subplots(
        3, 1, figsize=(13.2, 9.0), sharex=True, constrained_layout=True
    )
    _step(axes[0], x, detail["electrolyzerRequestedMW"], "电解槽请求")
    _step(axes[0], x, detail["electrolyzerActualMW"], "电解槽实际")
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("制氢—储氢—交付全周期变化")
    axes[0].legend(frameon=False, ncol=2)
    axes[0].grid(True, alpha=0.22)

    _step(axes[1], x, detail["h2ProductionKg"], "制氢量")
    _step(axes[1], x, detail["h2WithdrawnKg"], "提取量")
    _step(axes[1], x, detail["h2DeliveredKg"], "交付量")
    axes[1].set_ylabel("氢气 / kg·时段")
    axes[1].legend(frameon=False, ncol=3)
    axes[1].grid(True, alpha=0.22)

    _step(axes[2], x, detail["h2InventoryKg"], "储氢库存", linewidth=2.0)
    axes[2].set_xlabel("时段起点 / h")
    axes[2].set_ylabel("库存 / kg")
    axes[2].grid(True, alpha=0.22)
    _save(fig, out / "04_制氢储氢交付时序.png", manifest, "timeseries")


def render_compute(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, axes = plt.subplots(
        3, 1, figsize=(13.2, 9.2), sharex=True, constrained_layout=True
    )
    _step(axes[0], x, detail["computeRequestedMW"], "请求功率")
    _step(axes[0], x, detail["dcFacilityActualMW"], "设施实际功率")
    _step(axes[0], x, detail["itPowerMW"], "IT功率")
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("算力功率、服务队列与SLA全周期变化")
    axes[0].legend(frameon=False, ncol=3)
    axes[0].grid(True, alpha=0.22)

    _step(axes[1], x, detail["computeServedMWhCS"], "服务量")
    _step(axes[1], x, detail["computeQueueMWhCS"], "队列")
    _step(axes[1], x, detail["computeRigidUnservedMWhCS"], "刚性未服务")
    axes[1].set_ylabel("MWh-CS")
    axes[1].legend(frameon=False, ncol=3)
    axes[1].grid(True, alpha=0.22)

    axes[2].plot(x, detail["computeGrossRevenueCNY"].cumsum(), label="累计毛收入")
    axes[2].plot(x, detail["computeSLAPenaltyCNY"].cumsum(), label="累计SLA罚金")
    axes[2].set_xlabel("时段起点 / h")
    axes[2].set_ylabel("累计金额 / CNY")
    axes[2].legend(frameon=False, ncol=2)
    axes[2].grid(True, alpha=0.22)
    _save(fig, out / "05_算力功率队列收益时序.png", manifest, "timeseries")


def render_delivery(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, axes = plt.subplots(
        3, 1, figsize=(13.2, 9.0), sharex=True, constrained_layout=True
    )
    _step(axes[0], x, detail["exportSendActualMW"], "海缆送端")
    _step(axes[0], x, detail["cableReceiveMW"], "陆上受端")
    _step(axes[0], x, detail["cableLossMW"], "海缆损耗")
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("电力、氢气与海洋服务交付时序")
    axes[0].legend(frameon=False, ncol=3)
    axes[0].grid(True, alpha=0.22)

    _step(axes[1], x, detail["h2PipeDeliveredKg"], "管输氢")
    _step(axes[1], x, detail["h2ShipDeliveredKg"], "船运氢")
    axes[1].set_ylabel("交付量 / kg·时段")
    axes[1].legend(frameon=False, ncol=2)
    axes[1].grid(True, alpha=0.22)

    _step(axes[2], x, detail["marineRequestedMW"], "海洋需求")
    _step(axes[2], x, detail["marineActualMW"], "海洋实际服务")
    _step(axes[2], x, detail["marineUnservedMW"], "海洋未供")
    axes[2].set_xlabel("时段起点 / h")
    axes[2].set_ylabel("功率 / MW")
    axes[2].legend(frameon=False, ncol=3)
    axes[2].grid(True, alpha=0.22)
    _save(fig, out / "06_多形态产品交付时序.png", manifest, "timeseries")


def render_redispatch(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, axes = plt.subplots(
        2, 1, figsize=(13.2, 7.0), sharex=True, constrained_layout=True
    )
    for column, label in [
        ("computeReleasedMW", "算力释放"),
        ("marineTopUpMW", "海洋回补"),
        ("exportTopUpMW", "外送回补"),
        ("electrolyzerTopUpMW", "直通制氢回补"),
    ]:
        _step(axes[0], x, detail[column], label)
    axes[0].set_ylabel("功率 / MW")
    axes[0].set_title("算力响应后再调度过程")
    axes[0].legend(frameon=False, ncol=4)
    axes[0].grid(True, alpha=0.22)
    _step(axes[1], x, detail["spillMW"], "最终弃电")
    _step(axes[1], x, detail["totalUnservedMW"], "最终缺供")
    axes[1].set_xlabel("时段起点 / h")
    axes[1].set_ylabel("功率 / MW")
    axes[1].legend(frameon=False, ncol=2)
    axes[1].grid(True, alpha=0.22)
    _save(fig, out / "07_响应后再调度时序.png", manifest, "timeseries")


def render_balance(detail: pd.DataFrame, out: Path, manifest: list[dict[str, str]]) -> None:
    x = detail["timeH"].to_numpy(float)
    fig, ax = plt.subplots(figsize=(13.2, 4.8), constrained_layout=True)
    _step(ax, x, detail["busResidualMW"], "母线残差", linewidth=1.6)
    ax.axhline(1e-6, color="tab:red", linestyle="--", linewidth=1.0, label="冻结容差 ±1e-6 MW")
    ax.axhline(-1e-6, color="tab:red", linestyle="--", linewidth=1.0)
    ax.set_xlabel("时段起点 / h")
    ax.set_ylabel("残差 / MW")
    ax.set_title("公共母线残差全周期变化")
    ax.grid(True, alpha=0.22)
    ax.legend(frameon=False)
    ax.ticklabel_format(axis="y", style="sci", scilimits=(-3, 3))
    _save(fig, out / "08_母线残差时序.png", manifest, "timeseries")


def render_scenario(scenario_dir: Path) -> None:
    scenario_dir = scenario_dir.resolve()
    detail = pd.read_csv(scenario_dir / "v4_hourly_detail.csv")
    kpi = pd.read_csv(scenario_dir / "v4_kpi_summary.csv")
    economics = pd.read_csv(scenario_dir / "v4_economic_breakdown.csv")
    emissions = pd.read_csv(scenario_dir / "v4_environment_breakdown.csv")
    final_dir = scenario_dir / "figures" / "final_kpi"
    time_dir = scenario_dir / "figures" / "timeseries"
    manifest: list[dict[str, str]] = []

    render_kpi_table(kpi, final_dir, manifest)
    render_economics(economics, final_dir, manifest)
    render_environment_reliability(emissions, kpi, final_dir, manifest)
    render_source(detail, time_dir, manifest)
    render_dispatch(detail, time_dir, manifest)
    render_storage(detail, time_dir, manifest)
    render_hydrogen(detail, time_dir, manifest)
    render_compute(detail, time_dir, manifest)
    render_delivery(detail, time_dir, manifest)
    render_redispatch(detail, time_dir, manifest)
    render_balance(detail, time_dir, manifest)
    pd.DataFrame(manifest).to_csv(
        scenario_dir / "figures" / "figure_manifest.csv", index=False, encoding="utf-8-sig"
    )
    scenario_id = str(kpi["scenarioId"].iloc[0])
    if scenario_id == "chapter5_all_channel_48h":
        shutil.copy2(
            time_dir / "02_功率分配与供需状态.png",
            ROOT / "chapter5_preparation" / "assets" / "figure_ch5_all_channel_48h.png",
        )

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render separated final-KPI and full-horizon V4 result figures."
    )
    parser.add_argument(
        "--scenario-dir",
        action="append",
        required=True,
        help="Scenario output directory; repeat to render more than one scenario.",
    )
    args = parser.parse_args()
    for item in args.scenario_dir:
        render_scenario(Path(item))


if __name__ == "__main__":
    main()
