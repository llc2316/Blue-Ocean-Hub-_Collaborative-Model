from __future__ import annotations

from pathlib import Path

import pandas as pd
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Image,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUTPUT_PDF = HERE.parent / "报告.pdf"
TEMP_PDF = ROOT / "tmp" / "pdfs" / "4.4_bus_report_current.pdf"


def register_fonts() -> tuple[str, str]:
    regular = Path(r"C:\Windows\Fonts\msyh.ttc")
    bold = Path(r"C:\Windows\Fonts\msyhbd.ttc")
    if regular.exists() and bold.exists():
        pdfmetrics.registerFont(TTFont("CJK", str(regular), subfontIndex=0))
        pdfmetrics.registerFont(TTFont("CJK-Bold", str(bold), subfontIndex=0))
        return "CJK", "CJK-Bold"
    return "Helvetica", "Helvetica-Bold"


def build() -> None:
    data = pd.read_csv(ROOT / "outputs" / "v4_hourly_summary.csv")
    regular, bold = register_fonts()
    TEMP_PDF.parent.mkdir(parents=True, exist_ok=True)

    styles = getSampleStyleSheet()
    title = ParagraphStyle(
        "TitleCJK",
        parent=styles["Title"],
        fontName=bold,
        fontSize=18,
        leading=25,
        alignment=TA_CENTER,
        spaceAfter=12,
    )
    heading = ParagraphStyle(
        "HeadingCJK",
        parent=styles["Heading2"],
        fontName=bold,
        fontSize=12,
        leading=18,
        spaceBefore=7,
        spaceAfter=5,
    )
    body = ParagraphStyle(
        "BodyCJK",
        parent=styles["BodyText"],
        fontName=regular,
        fontSize=9.5,
        leading=16,
        spaceAfter=5,
    )
    small = ParagraphStyle(
        "SmallCJK",
        parent=body,
        fontSize=8.3,
        leading=13,
        textColor=colors.HexColor("#4B5563"),
    )

    source = data["sourceMW"].sum()
    export = data["exportSendMW"].sum()
    spill = data["spillMW"].sum()
    unserved = data["marineUnservedMW"].sum()
    h2_production = data["h2ProductionKg"].sum()
    h2_delivery = data["h2DeliveredKg"].sum()
    max_residual = data["busResidualMW"].abs().max()
    coexistence = (
        (data["spillMW"] > 1e-7) & (data["marineUnservedMW"] > 1e-7)
    ).sum()

    story = [
        Paragraph("4.4 公共母线功率平衡：V4现行模型报告", title),
        Paragraph(
            "报告口径：BLUE_HUB_CH4_SCHEMA_V2 / common_case_v2 / "
            "interface_smoke；数据由2026-07-26当前V4联合入口生成。",
            small,
        ),
        Paragraph("1. 模型责任", heading),
        Paragraph(
            "4.4是V4唯一公共母线实际功率总账。它只读取4.3、4.5、4.6、4.7"
            "已经提交的actual量，计算逐时残差；不执行跨模块分配，不修改SOC、"
            "氢库存或算力队列。实际弃电与分类缺供由4.9确认，4.4仅核账。",
            body,
        ),
        Paragraph("2. 冻结平衡式", heading),
        Paragraph(
            "r = Psource + Pbess_dis + Pgrid_import - Pbess_ch - Pelectrolyzer "
            "- Pdc_facility - Pexport_send - Pmarine - Psource_aux "
            "- Pcommon_aux - Ppost_POI_loss - Pspill。",
            body,
        ),
        Paragraph(
            "缺供是可靠性KPI，不作为虚拟功率注入。电池效率由4.5在SOC方程内"
            "处理；电解槽SEC、水耗和储氢损失由4.5处理；PUE由4.6处理；海缆"
            "损耗由4.7处理，4.4不得重复扣减。",
            body,
        ),
        Paragraph("3. 当前24小时联调结果", heading),
    ]

    table_data = [
        [
            Paragraph("<b>指标</b>", body),
            Paragraph("<b>当前结果</b>", body),
            Paragraph("<b>数据状态/来源</b>", body),
        ],
        ["源侧实际电量", f"{source:.3f} MWh", "模型仿真结果 / 4.3 actual"],
        ["电力外送量", f"{export:.3f} MWh", "模型仿真结果 / 4.7 actual"],
        [
            "实际弃电量",
            "0 MWh（数值舍入）" if spill < 1e-9 else f"{spill:.3f} MWh",
            "模型仿真结果 / 4.9确认、4.4记账",
        ],
        ["海洋未供能", f"{unserved:.3f} MWh", "模型仿真结果 / 4.7 KPI"],
        ["制氢量", f"{h2_production:.3f} kg", "模型仿真结果 / 4.5 actual"],
        ["氢气交付量", f"{h2_delivery:.3f} kg", "模型仿真结果 / 4.7 actual"],
        ["弃电与缺供并存时段", f"{int(coexistence)}", "模型一致性检查"],
        ["最大母线残差", f"{max_residual:.3e} MW", "模型仿真结果"],
        ["冻结容差", "1.000e-6 MW", "4.2冻结接口"],
    ]
    table = Table(table_data, colWidths=[48 * mm, 45 * mm, 82 * mm], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (-1, -1), regular),
                ("FONTNAME", (0, 0), (-1, 0), bold),
                ("FONTSIZE", (0, 0), (-1, -1), 8.4),
                ("LEADING", (0, 0), (-1, -1), 13),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#DCEAF7")),
                ("GRID", (0, 0), (-1, -1), 0.45, colors.HexColor("#9CA3AF")),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F8FAFC")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.extend(
        [
            table,
            Spacer(1, 5 * mm),
            Paragraph(
                "当前最大残差低于冻结容差。默认40 MW级源侧算例中，算力响应释放的"
                "功率按海洋缺口、海缆余量和同小时直通制氢顺序再分配，因此电力外送"
                "和制氢均为非零、弃电为零；仍有海洋未供说明总供能规模不足，但不存在"
                "弃电与缺供同时发生的调度矛盾。",
                body,
            ),
            Paragraph(
                "容量、负荷、效率、价格和未签认成本均含 "
                "<b>[假设值，待企业调研校准]</b>；本页数据属于 <b>[模型仿真结果]</b>。",
                small,
            ),
            PageBreak(),
            Paragraph("4. 逐时图像与代码数据一致性", heading),
        ]
    )

    figure = HERE / "assets" / "figure_4_4_v4_hourly_balance.png"
    story.append(Image(str(figure), width=181 * mm, height=101.5 * mm))
    story.extend(
        [
            Spacer(1, 4 * mm),
            Paragraph(
                "图4-4-1 V4公共母线逐时实际量与残差。全部序列直接读取"
                "outputs/v4_hourly_summary.csv；上图展示源侧、已列示用能端、电池"
                "放电、海缆外送和弃电，下图展示残差及±1e-6 MW冻结容差。",
                small,
            ),
            Paragraph("5. 适用限制", heading),
            Paragraph(
                "本报告只证明当前24小时接口联调闭合及调度一致性。默认场景已形成"
                "非零制氢和交付，48小时全通道压力场景另行验证了满功率制氢和船运"
                "链路。当前结果不能作为长期循环经济性、项目容量最优或构网动态结论。",
                body,
            ),
        ]
    )

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFont(regular, 8)
        canvas.setFillColor(colors.HexColor("#6B7280"))
        canvas.drawString(18 * mm, 11 * mm, "蓝海枢纽 V4 - 4.4公共母线核账")
        canvas.drawRightString(192 * mm, 11 * mm, f"第 {doc.page} 页")
        canvas.restoreState()

    doc = SimpleDocTemplate(
        str(TEMP_PDF),
        pagesize=A4,
        leftMargin=17 * mm,
        rightMargin=17 * mm,
        topMargin=15 * mm,
        bottomMargin=17 * mm,
        title="4.4 公共母线功率平衡：V4现行模型报告",
        author="蓝海枢纽V4联合模型",
    )
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    OUTPUT_PDF.write_bytes(TEMP_PDF.read_bytes())


if __name__ == "__main__":
    build()
