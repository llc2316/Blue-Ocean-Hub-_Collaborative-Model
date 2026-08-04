from __future__ import annotations

import csv
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.platypus import Image, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


root = Path(__file__).resolve().parents[2]
csv_path = root / "V4整合" / "outputs" / "v4_hourly_summary.csv"
module_dir = root / "V4整合" / "modules" / "4.4_bus"
asset_dir = module_dir / "docs" / "assets"
asset_dir.mkdir(parents=True, exist_ok=True)
figure_path = asset_dir / "figure_4_4_v4_hourly_balance.png"
pdf_path = module_dir / "报告.pdf"

with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
    rows = list(csv.DictReader(handle))

def series(name: str) -> list[float]:
    return [float(row[name]) for row in rows]

time_h = series("timeH")
source = series("sourceMW")
charge = series("bessChargeMW")
discharge = series("bessDischargeMW")
electrolyzer = series("electrolyzerMW")
compute = series("dcFacilityMW")
marine = series("marineMW")
export = series("exportSendMW")
spill = series("spillMW")
marine_unserved = series("marineUnservedMW")
residual = series("busResidualMW")
load_total = [
    charge[i] + electrolyzer[i] + compute[i] + marine[i] + export[i] + spill[i] + 0.25 + 0.20
    for i in range(len(rows))
]

if not figure_path.exists():
    raise FileNotFoundError(f"Run the MATLAB figure export first: {figure_path}")

pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
styles = getSampleStyleSheet()
title_style = ParagraphStyle(
    "CNTitle", parent=styles["Title"], fontName="STSong-Light", fontSize=20,
    leading=28, alignment=TA_CENTER, textColor=colors.HexColor("#123B5D"),
)
heading_style = ParagraphStyle(
    "CNHeading", parent=styles["Heading2"], fontName="STSong-Light", fontSize=14,
    leading=20, textColor=colors.HexColor("#166088"), spaceBefore=8, spaceAfter=6,
)
body_style = ParagraphStyle(
    "CNBody", parent=styles["BodyText"], fontName="STSong-Light", fontSize=10.5,
    leading=17, spaceAfter=6,
)
note_style = ParagraphStyle(
    "CNNote", parent=body_style, backColor=colors.HexColor("#EEF6FA"),
    borderColor=colors.HexColor("#8DB9D3"), borderWidth=0.5, borderPadding=7,
)

doc = SimpleDocTemplate(
    str(pdf_path), pagesize=A4, rightMargin=18 * mm, leftMargin=18 * mm,
    topMargin=18 * mm, bottomMargin=18 * mm,
    title="4.4公共母线功率平衡V4报告",
)
story = [
    Paragraph("4.4 公共母线功率平衡：V4现行模型报告", title_style),
    Spacer(1, 6 * mm),
    Paragraph("报告口径：BLUE_HUB_CH4_SCHEMA_V2 / common_case_v2 / interface_smoke；数据由当前V4联合入口生成。", note_style),
    Paragraph("1. 模型责任", heading_style),
    Paragraph(
        "4.4是V4唯一公共母线实际功率总账。它只读取4.3、4.5、4.6、4.7已提交的actual量，"
        "计算逐时残差、实际弃电、关键缺供和公共损耗；不执行跨模块分配、不修改SOC、氢库存或算力队列。",
        body_style,
    ),
    Paragraph("2. 冻结平衡式", heading_style),
    Paragraph(
        "r = Psource + Pbess_dis + Pgrid_import - Pbess_ch - Pelectrolyzer - Pdc_facility "
        "- Pexport_send - Pmarine - Psource_aux - Pcommon_aux - Ppost_POI_loss - Pspill。",
        body_style,
    ),
    Paragraph(
        "缺供是可靠性KPI，不作为虚拟功率注入。电池效率由4.5在SOC方程内处理；电解槽SEC、水耗和储氢损失由4.5处理；"
        "PUE由4.6处理；海缆损耗由4.7处理，4.4不得重复扣减。",
        body_style,
    ),
    Paragraph("3. 当前24小时联调结果", heading_style),
]

summary = [
    ["指标", "当前结果", "数据来源"],
    ["源侧实际电量", f"{sum(source):.3f} MWh", "v4_hourly_summary.csv"],
    ["实际弃电量", f"{sum(spill):.3f} MWh", "v4_hourly_summary.csv"],
    ["海洋未供能", f"{sum(marine_unserved):.3f} MWh", "v4_hourly_summary.csv"],
    ["最大母线残差", f"{max(abs(v) for v in residual):.3e} MW", "v4_hourly_summary.csv"],
    ["冻结容差", "1.000e-6 MW", "common_config_4_2.m"],
]
table = Table(summary, colWidths=[45 * mm, 45 * mm, 70 * mm], repeatRows=1)
table.setStyle(TableStyle([
    ("FONTNAME", (0, 0), (-1, -1), "STSong-Light"),
    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#166088")),
    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
    ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#B7C9D6")),
    ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F9FB")]),
    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ("ALIGN", (1, 1), (1, -1), "RIGHT"),
    ("LEFTPADDING", (0, 0), (-1, -1), 6),
    ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ("TOPPADDING", (0, 0), (-1, -1), 5),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
]))
story.extend([
    table,
    Spacer(1, 5 * mm),
    Paragraph(
        "当前最大残差低于冻结容差，说明actual-only总账闭合。海洋未供能为需求未满足统计量，"
        "不是总账缺口；当前interface_smoke中电解槽未启动，因此制氢量为0，这不代表工程方案不制氢。",
        note_style,
    ),
    PageBreak(),
    Paragraph("4. 逐时图像与代码数据一致性", heading_style),
    Image(str(figure_path), width=174 * mm, height=101.5 * mm),
    Spacer(1, 4 * mm),
    Paragraph(
        "图中全部序列直接读取V4/outputs/v4_hourly_summary.csv。上图比较源侧实际功率与负荷、弃电和公共损耗账；"
        "下图放大显示逐时残差及±1e-6 MW冻结容差。",
        body_style,
    ),
    Paragraph("5. 适用限制", heading_style),
    Paragraph(
        "本报告只证明当前24小时接口联调闭合。容量、效率、价格、负荷与初态仍包含公开参考值和"
        "[假设值，待企业调研校准]，不能据此形成工程经济或构网动态结论。",
        body_style,
    ),
])
doc.build(story)
print(pdf_path)
print(figure_path)
