import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = "../outputs/深能源交流";
const outputPath = `${outputDir}/深能源交流问题清单_整理版.xlsx`;

const wb = Workbook.create();
const clean = wb.worksheets.add("整理后问题清单");
const mapping = wb.worksheets.add("原问题映射");

const sourceUrl = "https://docs.qq.com/sheet/DZkRtUVZnV2VDZGxF";

const cleanedRows = [
  [1, "交流与数据授权边界",
    "本次交流可讨论哪些新能源项目、设备型号和运行阶段？哪些数据可由集团、项目公司、运维单位、设计院或设备商分别提供？数据可用于哪些研究、验证和成果展示场景？",
    "请分别确认项目范围、设备范围、数据所有者、保管单位、脱敏要求、授权人以及成果引用边界。",
    "项目—设备—数据所有者—保管单位—授权人的对应表；可讨论/可提供/不可提供数据清单。",
    "集团业务部门、项目公司、法务/数据管理部门",
    "交流边界"],
  [2, "系统拓扑、测点与字段字典",
    "能否提供脱敏后的系统单线图、汇集母线及公共连接点边界、测点清单和SCADA字段字典？",
    "请说明设备交流端、源内集电网、公共母线、源侧辅机的测点边界，以及CT/PT、电表、时间戳、单位、P/Q/V/I/f、状态码、告警、限发和质量码。",
    "脱敏单线图、测点表、CT/PT及电表信息、字段字典、短周期样例数据。",
    "设计院、项目公司、集控中心、设备商",
    "测点与单线图；SCADA字段"],
  [3, "数据质量与同场环境数据",
    "项目是否具备风、浪、流、温度、气压和平台姿态等同场环境数据？其数据质量控制规则是什么？",
    "请说明测点位置、采样周期、可用时间段、计量精度、校准周期、时钟同步、缺失插补、漂移识别及质量码规则。",
    "环境测点元数据、可用时间段、校准证书摘要、时间同步和质量控制规则。",
    "项目公司、测风测海单位、运维单位",
    "同场环境数据；数据质量"],
  [4, "功率闭合与源储接口",
    "设备端毛功率、汇集点净功率、场用电及源内损耗能否在同一时间轴闭合？源侧与构网型储能如何交换实时量和备用需求？",
    "请说明计量误差、损耗校对方法、储能SOC安全边界、黑启动预留、新能源降额及备用判据。",
    "至少一周同步P/Q/场用电数据、损耗校对规则、源—储接口及备用判据。",
    "项目公司、集控中心、储能/变流器设备商",
    "功率与损耗闭合；源储接口"],
  [5, "调度链路与并网控制",
    "EMS/AGC指令从请求、接受到实际执行的链路如何定义？项目的并网和构网能力如何确定与验收？",
    "请区分requested、accepted和actual，说明刷新周期、延迟、拒绝原因、质量码及指令优先级；同时说明P-Q包络、AGC/AVC、爬坡限制、短路比、故障穿越和保护整定。",
    "三联量同步样例、接口说明、控制优先级、验收报告或脱敏能力包络。",
    "集控中心、设计院、电网、设备商、试验验收单位",
    "调度链路；并网能力"],
  [6, "事件、故障、运维与极端天气恢复",
    "项目如何统一记录资源不足、主动限发、电网限送、设备故障、检修、通信中断及极端天气事件？",
    "请提供事件分类、状态码、起止规则；并说明故障率、降额率、MTTR、天气等待、备件、船舶动员，以及典型台风预警—降额—停机—复归—恢复全过程。",
    "事件分类及状态码交叉表、故障模式统计、维修链条、典型极端天气完整时间轴。",
    "项目公司、运维单位、集控中心、设备商",
    "事件标签；台风与恢复；故障与运维"],
  [7, "预测数据与独立验证",
    "是否保留日前、日内和超短期预测档案？企业如何独立验收功率预测模型和控制响应？",
    "请说明预测发布时间、版本、预测值和实测值，划定独立验证数据窗，并明确RMSE、MAE、bias、coverage等指标及阈值。",
    "生产预测档案、实测对照数据、误差评估口径、验证窗口和验收阈值。",
    "集控中心、预测服务商、技术监督/验收单位",
    "预测数据；独立验证"],
  [8, "单一外送基准场景",
    "企业如何定义可与源储算用协同方案公平比较的“单一外送”基准？",
    "请统一装机容量、资源序列、送出限额、场用电、线路损耗、弃电口径、限发优先级及调度规则。",
    "与协同方案使用同一资源、设备和计量边界的基准场景及参数说明。",
    "项目公司、设计院、调度/交易人员",
    "单一外送基准"],
  [9, "漂浮式光伏适用性",
    "若集团拥有海上或漂浮式光伏实践，能否提供项目适用边界和可用于本研究的数据？",
    "请说明组件、逆变器、浮体姿态、组串拓扑、遮挡、盐雾、故障和运维数据；如无直接数据，请提供专家判断及数据责任方。",
    "适用项目清单、设备与环境数据说明；或不存在适用项目的明确结论及专家判断。",
    "新能源业务部门、项目公司、光伏设备商、设计院",
    "光伏适用性"],
];

const originalRows = [
  [1,"交流边界","本次可讨论哪些新能源项目、设备型号和运行阶段？哪些数据由集团、项目公司、运维单位、设计院或OEM分别持有？",1,"保留并扩展授权与成果使用边界"],
  [2,"测点与单线图","请确认设备交流端、源内集电网、source collection bus、源侧辅机及公共母线的实际测点和单线图边界。",2,"与SCADA字段合并为拓扑—测点—字段完整链条"],
  [3,"SCADA字段","能否提供一份脱敏SCADA通道样例及字段字典，包括时间、P/Q/V/I/f、状态码、告警、限发和质量码？",2,"与测点及单线图共同确认数据语义"],
  [4,"同场环境数据","项目是否具备同场风、浪、流、温度、气压和平台姿态数据？测点位置、采样周期、时间同步和有效期如何？",3,"与数据质量合并，形成环境数据可用性问题"],
  [5,"功率与损耗闭合","设备端毛功率、汇集点净功率、源内集电损耗和辅机耗电能否在相同时间轴闭合？现有计量误差多大？",4,"与源储接口合并到统一能量边界"],
  [6,"调度链路","EMS/AGC指令中requested、设备accepted和实际actual能否区分？刷新周期、延迟、质量码和拒绝原因是什么？",5,"与并网能力合并为控制指令—设备响应—验收链条"],
  [7,"事件标签","如何区分资源不足、主动限发、电网限送、设备故障、检修、环境保护、通信丢失和降额？",6,"与故障运维及台风恢复共享事件标签体系"],
  [8,"预测数据","是否保留日前、日内、超短期风功率及资源预测的发布时间、版本、预测值和实测值？",7,"与独立验证合并，形成预测档案—评价闭环"],
  [9,"并网能力","项目P-Q运行包络、AGC/AVC性能、爬坡限制、短路比、故障穿越及保护整定如何确定？",5,"与调度链路合并，但保留技术追问"],
  [10,"台风与恢复","能否获取一次典型台风或极端海况，说明预警、降额、停机、复归、恢复和人工干预全过程？",6,"纳入事件、故障与运维统一时间轴"],
  [11,"故障与运维","可否按部件或故障模式提供故障率、降额率、MTTR、天气等待、备件及船舶动员时间？",6,"纳入可靠性与恢复链条"],
  [12,"独立验证","企业通常用哪些KPI验收功率模型、预测模型和控制响应？能否划定独立验证时段？",7,"与预测数据合并，避免重复索取数据"],
  [13,"数据质量","计量精度、校准周期、时钟同步、缺失插补、漂移和质量码规则是什么？",3,"与同场环境数据合并为数据可用性审查"],
  [14,"源储接口","源侧向构网型储能提供哪些实时量和备用需求？SOC安全边界、黑启动预留和新能源降额如何协同？",4,"与功率闭合合并，但保留储能控制追问"],
  [15,"单一外送基准","企业如何定义单一外送模式的装机、送出限额、弃电和损耗口径？",8,"独立保留，是项目对比评价的基准"],
  [16,"光伏适用性","若集团拥有海上/漂浮式光伏实践，能否提供组件、逆变器、浮体姿态、组串拓扑、故障和海洋环境数据？",9,"独立保留，避免与风电环境数据混淆"],
];

// Sheet 1: cleaned list
clean.showGridLines = false;
clean.getRange("A1:G1").merge();
clean.getRange("A1").values = [["深能源交流问题清单（整理版）"]];
clean.getRange("A2:G2").merge();
clean.getRange("A2").values = [["整理原则：无逐字重复项；将交叉重复问题归并为9组主问题，原技术细节保留为追问。来源类型：企业交流问题清单（待形成企业访谈一手数据）。"]];
clean.getRange("A4:B4").values = [["原问题数", null]];
clean.getRange("B4").formulas = [["=COUNTA('原问题映射'!A5:A20)"]];
clean.getRange("C4:D4").values = [["整理后主问题数", null]];
clean.getRange("D4").formulas = [["=COUNTA(A9:A17)"]];
clean.getRange("E4:F4").values = [["减少重复提问", null]];
clean.getRange("F4").formulas = [["=B4-D4"]];
clean.getRange("G4").values = [["压缩率"]];
clean.getRange("G5").formulas = [["=1-D4/B4"]];
clean.getRange("A6:G6").merge();
clean.getRange("A6").values = [[`原始文档：${sourceUrl}｜当前清单为访谈准备材料，不代表企业已经确认相关数据或参数。`]];
clean.getRange("A8:G8").values = [["编号","归并主题","核心提问","必要追问","预期交付物/回答","建议回答对象","合并的原主题"]];
clean.getRange("A9:G17").values = cleanedRows;

clean.getRange("A1:G1").format = {fill:"#17365D",font:{bold:true,color:"#FFFFFF",size:18},horizontalAlignment:"center",verticalAlignment:"center"};
clean.getRange("A2:G2").format = {fill:"#DCE6F1",font:{color:"#244062",size:10},wrapText:true,verticalAlignment:"center"};
clean.getRange("A4:G5").format = {fill:"#F3F6FA",font:{bold:true,color:"#244062"},horizontalAlignment:"center",verticalAlignment:"center",borders:{preset:"outside",style:"thin",color:"#A6B8CE"}};
for (const addr of ["B4","D4","F4","G5"]) clean.getRange(addr).format = {font:{bold:true,color:"#C65911",size:13},horizontalAlignment:"center"};
clean.getRange("G5").format.numberFormat = "0%";
clean.getRange("A6:G6").format = {font:{italic:true,color:"#666666",size:9},wrapText:true};
clean.getRange("A8:G8").format = {fill:"#5B9BD5",font:{bold:true,color:"#FFFFFF"},horizontalAlignment:"center",verticalAlignment:"center",wrapText:true,borders:{preset:"outside",style:"thin",color:"#2F5597"}};
clean.getRange("A9:G17").format = {font:{size:10,color:"#1F1F1F"},verticalAlignment:"top",wrapText:true,borders:{insideHorizontal:{style:"thin",color:"#D9E2F3"},bottom:{style:"thin",color:"#A6B8CE"}}};
clean.getRange("A9:A17").format.horizontalAlignment = "center";
clean.getRange("A9:B17").format.fill = "#EDF3F8";
clean.getRange("A1:G17").format.font.name = "Microsoft YaHei";
clean.getRange("A1:G17").format.autofitRows();
clean.getRange("A1").format.rowHeight = 34;
clean.getRange("A2").format.rowHeight = 38;
clean.getRange("A8").format.rowHeight = 30;
clean.getRange("A9:A17").format.rowHeight = 92;
const cleanWidths = [8,20,49,49,38,26,28];
for (let i=0;i<cleanWidths.length;i++) clean.getRangeByIndexes(0,i,17,1).format.columnWidth = cleanWidths[i];
clean.freezePanes.freezeRows(8);
clean.freezePanes.freezeColumns(2);
const cleanTable = clean.tables.add("A8:G17", true, "CleanQuestionsTable");
cleanTable.style = "TableStyleMedium2";
cleanTable.showBandedRows = true;

// Sheet 2: traceable mapping
mapping.showGridLines = false;
mapping.getRange("A1:E1").merge();
mapping.getRange("A1").values = [["原问题—整理后问题映射"]];
mapping.getRange("A2:E2").merge();
mapping.getRange("A2").values = [["用途：核对归并过程，确保未因去重丢失测点、控制、运维和验证等关键细节。"]];
mapping.getRange("A3:E3").merge();
mapping.getRange("A3").values = [[`来源类型：企业交流问题清单（待访谈）｜原始文档：${sourceUrl}`]];
mapping.getRange("A4:E4").values = [["原编号","原主题","原问题","归并后编号","归并处理说明"]];
mapping.getRange("A5:E20").values = originalRows;
mapping.getRange("A1:E1").format = {fill:"#17365D",font:{bold:true,color:"#FFFFFF",size:17},horizontalAlignment:"center",verticalAlignment:"center"};
mapping.getRange("A2:E3").format = {fill:"#DCE6F1",font:{color:"#244062",size:9.5},wrapText:true};
mapping.getRange("A4:E4").format = {fill:"#5B9BD5",font:{bold:true,color:"#FFFFFF"},horizontalAlignment:"center",verticalAlignment:"center",wrapText:true};
mapping.getRange("A5:E20").format = {font:{size:10,color:"#1F1F1F"},verticalAlignment:"top",wrapText:true,borders:{insideHorizontal:{style:"thin",color:"#D9E2F3"},bottom:{style:"thin",color:"#A6B8CE"}}};
mapping.getRange("A5:A20").format.horizontalAlignment = "center";
mapping.getRange("D5:D20").format.horizontalAlignment = "center";
mapping.getRange("A1:E20").format.font.name = "Microsoft YaHei";
mapping.getRange("A1:E20").format.autofitRows();
mapping.getRange("A1").format.rowHeight = 34;
mapping.getRange("A4").format.rowHeight = 30;
mapping.getRange("A5:A20").format.rowHeight = 62;
const mapWidths = [9,20,62,13,40];
for (let i=0;i<mapWidths.length;i++) mapping.getRangeByIndexes(0,i,20,1).format.columnWidth = mapWidths[i];
mapping.freezePanes.freezeRows(4);
const mapTable = mapping.tables.add("A4:E20", true, "OriginalMappingTable");
mapTable.style = "TableStyleMedium2";
mapTable.showBandedRows = true;

await fs.mkdir(outputDir, {recursive:true});

const check1 = await wb.inspect({kind:"table",range:"整理后问题清单!A1:G17",include:"values,formulas",tableMaxRows:20,tableMaxCols:8,maxChars:5000});
console.log(check1.ndjson);
const errors = await wb.inspect({kind:"match",searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",options:{useRegex:true,maxResults:100},summary:"final formula error scan"});
console.log(errors.ndjson);

const preview1 = await wb.render({sheetName:"整理后问题清单",range:"A1:G17",scale:1,format:"png"});
await fs.writeFile("preview_clean.png",new Uint8Array(await preview1.arrayBuffer()));
const preview2 = await wb.render({sheetName:"原问题映射",range:"A1:E20",scale:1,format:"png"});
await fs.writeFile("preview_mapping.png",new Uint8Array(await preview2.arrayBuffer()));

const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(outputPath);
console.log(outputPath);
