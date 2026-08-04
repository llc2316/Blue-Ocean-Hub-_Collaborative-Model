import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "C:/Users/llcqc/Desktop/多源能源/4_3_data_freeze/蓝海枢纽_4.3数据冻结与证据矩阵.xlsx";
const outputDir = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_4_9_multiobjective_update";
const outputPath = `${outputDir}/蓝海枢纽_4.3-4.9数据冻结与多目标证据矩阵.xlsx`;
await fs.mkdir(`${outputDir}/previews`, { recursive: true });

const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));

const navy = "#17365D";
const blue = "#1F4E78";
const teal = "#0F6B78";
const paleBlue = "#DDEBF7";
const paleTeal = "#DDEBF7";
const paleGold = "#FFF2CC";
const paleGreen = "#E2F0D9";
const paleRed = "#FCE4D6";
const gray = "#E7E6E6";
const white = "#FFFFFF";
const border = { preset: "all", style: "thin", color: "#B4C6E7" };

function styleTitle(sheet, range, title) {
  const r = sheet.getRange(range);
  r.merge();
  r.values = [[title]];
  r.format = { fill: navy, font: { bold: true, color: white, size: 16 }, verticalAlignment: "center" };
  r.format.rowHeight = 28;
}

function styleNote(sheet, range, note) {
  const r = sheet.getRange(range);
  r.merge();
  r.values = [[note]];
  r.format = { fill: "#EAF2F8", font: { italic: true, color: "#404040" }, wrapText: true, verticalAlignment: "center" };
  r.format.rowHeight = 38;
}

function styleHeader(range, fill = blue) {
  range.format = { fill, font: { bold: true, color: white }, wrapText: true, verticalAlignment: "center", horizontalAlignment: "center", borders: border };
  range.format.rowHeight = 28;
}

function styleBody(range) {
  range.format = { wrapText: true, verticalAlignment: "top", borders: border };
}

// 1) 在原“06_企业交流清单”上补齐4.3闭环数据。
const s06 = wb.worksheets.getItem("06_企业交流清单");
const add43 = [
  ["ASK-DG-01","业主/计量与数据平台主管","全部环境、SCADA、计量测点的传感器型号、量程、精度等级、校准证书、安装坐标/高度/深度、时钟同步方式及漂移记录","公开数据无法证明测点可比性和误差边界；直接影响参数校准与不确定度","设备级元数据；每次校准/更换形成版本","证书编号可脱敏；保留精度与有效期","IEC/GB测量等级作为下限，不能替代项目证书","QC-001，D-DATA，所有环境/功率变量","P0","未发起"],
  ["ASK-FCST-01","业主/预测服务商/EMS","日前、日内、超短期风光潮预测档案：发布时间、预测时域、模型版本、概率分位/场景、实测值及可用性标签","4.9随机/滚动优化必须使用当时可获得的预测，不能用事后实测替代","原始发布时间；1min/15min/1h；至少完整一年","可匿名预测商与模型；保留版本和误差","ERA5等可生成基线预测，但不能替代生产预测误差","pForecastAvailable，forecastError，scenarioId","P0","未发起"],
  ["ASK-LBL-01","业主/SCADA/运维","统一且互斥的事件标签：资源不足、EMS限发、电网限送、故障、检修、环境保护、通信丢失、降额、跟踪误差及起止时间","不分离事件会把限发和故障误拟合为资源—功率曲线","事件级，秒/分钟时间戳；与功率同步","故障文字可编码化；仅保留类别和持续时间","公开资料只能给分类框架","stateFlag，curtailmentFlag，availability，lossCause","P0","未发起"],
  ["ASK-CFG-01","各设备OEM/业主","投运、固件/控制器、功率曲线、组件/机组更换、改造、阵列布局变化及参数集版本历史","同一设备跨版本不能直接合并校准；需追溯每段数据采用的参数集","每次变更事件；parameterSetId关联到时间段","可隐藏固件细节，仅给版本号和生效时间","公开资料通常只有当前版本","parameterSetId，validFrom/To，assetConfigId","P0","未发起"],
  ["ASK-EXT-01","业主/OEM/海洋预报方","台风、极端浪流、高温、盐雾等事件下的预警—降额—停机—重启—恢复全过程及阈值","4.3运行状态机和4.9韧性场景需基于真实恢复序列","事件前后1s/1min；完整事件包","阈值可区间化；事件可编号匿名","公开台风路径可作环境输入，不能替代设备响应","extremeEventId，stateFlag，recoveryTime，deratingLimit","P0","未发起"],
  ["ASK-W-05","风场业主/设计院/OEM","风机坐标、轮毂高度/叶轮直径、尾流控制/偏航/限发策略、阵列损失矩阵及可用SCADA/CFD验证结果","单机功率曲线无法代表风场净出力和空间相关性","机位级；风向/风速分箱；至少一季典型数据","坐标可相对化，损失矩阵可匿名","开源尾流模型可作先验","W-loss，pWindGross/Net，wakeFactor，layoutId","P0","未发起"],
  ["ASK-PV-05","漂浮光伏业主/EPC/逆变器厂家","组串—汇流箱—逆变器—变压器映射、MPPT拓扑、电缆长度、遮挡/失配/旁路事件、绝缘与接地故障记录","海上姿态与盐雾会形成非均匀失配；只用组件效率会高估净出力","组串/逆变器级；1s—15min；事件级","拓扑可编号化；不披露供应商价格","典型拓扑可作占位，不可校准失配","PV-loss，pPvDc/Ac，mismatchFactor，topologyId","P1","未发起"],
  ["ASK-TC-05","潮流场业主/设计院/海洋测绘方","机组坐标、安装深度/朝向、局部水深地形、海床粗糙度、阵列尾流/阻塞与可达性限制","流速立方模型未含阵列相互作用与部署边界","设备/网格级；涨落潮分别标定","坐标相对化；地形降采样","公开海图只能作初始场","TC-loss，blockageFactor，wakeFactor，layoutId","P1","未发起"],
  ["ASK-GRID-01","设计院/电气总包/并网方","源侧汇集母线电压/频率运行包络、短路比、谐波/闪变、故障穿越、保护配合、集电线路热稳与无功限制","4.3需向4.4/4.5交付可行P-Q包络，而非仅有有功上限","母线/馈线级；典型及故障工况","可提供经脱敏的边界包络和试验结论","标准只给合规框架，不能替代项目整定值","p/qAvailable，v/fEnvelope，rampLimit，protectionState","P0","未发起"],
  ["ASK-QC-01","业主/计量/数据平台主管","电能表、CT/PT精度和变比、数据缺失/插补规则、传感器漂移、质量码及测量不确定度预算","用于区分模型误差与测量误差，并给4.8/4.9结果置信区间","测点级；质量码逐样本；年度不确定度复核","资产编号可匿名；保留精度和规则","标准可提供方法，不能替代项目误差预算","qualityFlag，uMeasurement，lossUncertainty","P0","未发起"],
  ["ASK-VAL-01","业主/第三方检测","独立验证时段或第二项目数据、验收KPI与阈值、基准模型设置及不合格处理规则","同一数据集拟合与验证会高估泛化能力","至少一个完整季节；保留极端事件与低资源时段","可在安全沙箱运行，仅输出KPI","公开样例只能做代码验收","calibrationSet，validationSet，RMSE/MAE/bias/coverage","P0","未发起"],
  ["ASK-ENV-01","业主/海事/环保与运维单位","季节性禁限作业、航道/渔业/生态窗口、海生物附着与腐蚀检查、可维护天气窗口及其导致的降额/停机","这些条件会改变可用率和恢复时间，不能仅作为文字风险","日历/事件级；与设备状态、天气同步","敏感坐标可网格化；仅保留时间窗和约束","法规提供上限，项目许可和运维窗口仍需企业","availability，maintenanceWindow，environmentalConstraint","P1","未发起"]
];
const start06 = 21;
s06.getRange(`A${start06}:J${start06 + add43.length - 1}`).values = add43;
styleBody(s06.getRange(`A${start06}:J${start06 + add43.length - 1}`));
for (let r = start06; r < start06 + add43.length; r++) {
  s06.getRange(`A${r}:J${r}`).format.fill = (r % 2 === 1) ? "#D9EEF7" : "#F4FAFD";
  s06.getRange(`I${r}`).format.fill = paleGold;
}
s06.getRange(`A${start06}:J${start06 + add43.length - 1}`).format.rowHeight = 52;
s06.getRange(`I${start06}:I${start06 + add43.length - 1}`).dataValidation = { rule: { type: "list", values: ["P0","P1","P2"] } };
s06.getRange(`J${start06}:J${start06 + add43.length - 1}`).dataValidation = { rule: { type: "list", values: ["未发起","沟通中","已获取","不可获取","用公开替代"] } };
s06.getRange("A2:J2").unmerge();
s06.getRange("A2:J2").merge();
s06.getRange("A2:J2").values = [["P0项决定模型能否从“通用代理”升级为“项目设备可落地模型”。本版新增：标定与版本、预测归档、事件标签、阵列/拓扑损耗、极端天气、独立验证和不确定度闭环。"]];
s06.getRange("A2:J2").format = { fill: "#EAF2F8", font: { italic: true, color: "#404040" }, wrapText: true, verticalAlignment: "center" };
s06.getRange("A2:J2").format.rowHeight = 34;
s06.getRange("A1:J32").format.font = { name: "Microsoft YaHei", size: 10 };
s06.freezePanes.freezeRows(4);

// 2) 新增4.8—4.9三目标架构。
const s08 = wb.worksheets.getOrAdd("08_4.8-4.9目标架构");
const old08 = s08.getUsedRange(); if (old08) old08.clear({ applyTo: "all" });
s08.deleteAllDrawings(); s08.showGridLines = false;
styleTitle(s08, "A1:L1", "4.8—4.9 多目标优化架构：经济—环保—可靠性");
styleNote(s08, "A2:L2", "章节分工：4.8只定义目标、核算边界、归一化和Pareto选择；4.9统一承接4.3—4.7物理约束、随机场景、求解与滚动执行。可靠性动态校核由4.5/快速仿真提供边界或代理约束，不在4.3重复建模。公式为可写入正文的结构式；参数值须经文献或企业证据校准。 ");

s08.getRange("A4:F4").values = [["章节","系统角色","主要输入","核心模型/动作","主要输出","防重复边界"]];
styleHeader(s08.getRange("A4:F4"));
const flowRows = [
  ["4.1","边界与口径冻结","场址、装机、测点、时间尺度、情景","定义系统边界、功能单位、基准方案","统一时空/损耗/核算边界","不在后续反复改变测点和成本/碳边界"],
  ["4.2","统一语义层","集合、参数、变量、状态、版本","变量字典、单位、索引、参数集","可被MATLAB/优化器调用的数据结构","只定义，不计算出力或收益"],
  ["4.3","多能源可用功率生成器","同场风光潮环境、设备曲线、状态、阵列损失","单机→阵列→设备端→汇集端可用P/Q与不确定度","pAvailable、qCapability、ramp、state、scenario","不做储能补偿和最终负荷分配"],
  ["4.4","多端口守恒与损耗账本","4.3源侧、4.5—4.7各端口、固定测点","逐时/场景电功率平衡、网络/变换损耗","balanceResidual、各端口净功率","不决定哪个端口更优；只保证守恒"],
  ["4.5","灵活性与构网执行层","功率缺口、SOC/H2库存、频率电压状态","电池/长时储能/制氢动态、P-Q/备用/黑启动边界","可调功率、能量状态、快速稳定边界","不重复源侧资源模型；向4.9提供约束/代理模型"],
  ["4.6","算力柔性负荷","作业队列、SLA、PUE、可迁移/可延期范围","算力—电力转换与任务服务约束","算力负荷可行域、收益、违约量","不把算力当无约束消纳池"],
  ["4.7","多形态输出端口","海缆/并网、H2/NH3物流、海洋负荷边界","外送、燃料、海洋用能与收入/服务量","端口容量、交付量、价格/合同边界","不在此做多目标权衡"],
  ["4.8","价值函数层","4.3—4.7输出、财务/LCA/可靠性参数","经济、环保、可靠性目标；归一化和Pareto偏好","目标向量与评价KPI","避免将三目标粗暴加权成一个无量纲不一致的数"],
  ["4.9","优化与验证层","目标向量、全部约束、预测场景、故障/极端场景","ε约束/Pareto、两阶段或滚动优化、可行性和动态复核","调度计划、Pareto前沿、实施策略","优化器不改写物理模型；动态不合格方案返回收紧边界"]
];
s08.getRange(`A5:F${4 + flowRows.length}`).values = flowRows;
styleBody(s08.getRange(`A5:F${4 + flowRows.length}`));
for (let r = 5; r <= 4 + flowRows.length; r++) s08.getRange(`A${r}:F${r}`).format.fill = r % 2 ? "#F4FAFD" : paleBlue;
s08.getRange(`A5:F${4 + flowRows.length}`).format.rowHeight = 48;

s08.getRange("A15:L15").values = [["目标ID","目标名称","4.8建议主公式（结构式）","最小化含义/单位","直接决策变量","关键外生参数","上游章节","4.9处理方式","主要KPI","公开依据","企业校准重点","状态"]];
styleHeader(s08.getRange("A15:L15"), teal);
const objectiveRows = [
  ["OBJ-ECO","经济目标","min F_eco = C_ann^cap + Σ_sπ_sΣ_t[(C_om+C_start+C_deg+C_buy+C_curt+C_ENS+C_carbon) − (R_elec+R_H2+R_NH3+R_compute+R_marine)]Δt","年化净成本，元/年；投资层可另算NPV/IRR/回收期","容量、各端口功率/产量、启停、备用、弃电、缺供","CAPEX/OPEX、寿命、WACC、合同价格、罚则、退化/更换成本","4.3出力；4.4损耗；4.5—4.7成本与收益量","先求单目标理想点，再用ε约束/Pareto；碳价仅作政策情景，避免与环保目标重复计权","NPV、IRR、回收期、LCOE/LCOS/LCOH、年净收益","IEC 60300-3-3:2017；IRENA折现现金流/LCOE方法","EPC分项、运维船舶、停机损失、融资税务、各产品承购合同","需原文/企业校准"],
  ["OBJ-ENV","环保目标","min F_env = E_emb + Σ_sπ_sΣ_t(E_grid+E_fuel+E_process+E_logistics+E_refrig)Δt + E_replace − E_recycle","生命周期温室气体，kgCO2e/年或全寿命；同时报告功能单位强度","设备选择/更换、购电、制氢制氨、运输、算力与运维策略","设备隐含碳、时变电力因子、燃料/物流/泄漏因子、回收规则","4.1核算边界；4.3—4.7物质/能量流","按ISO 14040/14044做目标范围—清单—影响—解释；避免排放量与避免排放量同时入目标","全寿命tCO2e、gCO2e/kWh、kgCO2e/kgH2或NH3、kgCO2e/算力服务","ISO 14040:2006、ISO 14044:2006、ISO 14067:2018","EPD/BOM、船舶燃料、冷媒、备件更换、H2/NH3辅助能耗与逸散、产品分摊规则","需原文/企业校准"],
  ["OBJ-REL","可靠性目标","min F_rel = EENS = Σ_sπ_sΣ_t P_unserved(t,s)Δt","期望未供能量，MWh/年；按负荷等级分别统计","备用、储能SOC/H2库存、端口削减、关键负荷供给、黑启动/恢复策略","故障率、修复时间、天气可达性、预测误差、关键负荷/SLA、N-1与频率指标","4.3随机可用率；4.4平衡；4.5构网/备用；4.6—4.7服务要求","场景法计算EENS/LOLE；N-1、备用、SOC安全、频率最低点/ROCOF作硬约束或动态复核","EENS、LOLE/LOLP、关键负荷供电率、恢复时间、N-1通过率、频率最低点/ROCOF","IEA资源充裕度方法强调天气与故障随机性；动态指标需电力系统文献/试验","部件停运/维修、台风共因、海上交通时延、VOLL/SLA、备用与黑启动验收阈值","需原文/企业校准"],
  ["OBJ-MO","多目标集成","min [f_eco*, f_env*, f_rel*]；f_i*=(F_i−F_i^ideal)/(F_i^nadir−F_i^ideal)","无量纲归一化目标向量；输出Pareto前沿而非唯一答案","同上","理想点/最差点、管理偏好或ε阈值","4.8三目标","推荐ε约束或Pareto；加权和仅用于已归一化且权重经决策者确认的情形","Pareto解集、边际替代率、鲁棒性、可实施推荐解","多目标优化通用结构，[需查证文献支撑]","权重/阈值需管理层确认；不能由建模人员代填","待决策确认"]
];
s08.getRange("A16:L19").values = objectiveRows;
styleBody(s08.getRange("A16:L19"));
s08.getRange("A16:L16").format.fill = paleGold;
s08.getRange("A17:L17").format.fill = paleGreen;
s08.getRange("A18:L18").format.fill = paleRed;
s08.getRange("A19:L19").format.fill = paleBlue;
s08.getRange("A16:L19").format.rowHeight = 100;

s08.getRange("A21:H21").values = [["4.9约束组","来源章节","约束结构（示意）","三目标作用","需要的企业数据","建议数学处理","动态/高保真复核","不合格时回传"]];
styleHeader(s08.getRange("A21:H21"));
const constraints = [
  ["源侧可用域","4.3","0≤p_i≤p_i,available；(p_i,q_i)∈Ω_i；|Δp_i|≤ramp_i；state_i允许时才发电","经济/环保/可靠性","设备曲线、状态码、阵列损失、预测误差","情景参数+分段线性/查表","极端天气与P-Q/故障穿越试验","收紧可用功率、爬坡、状态转移"],
  ["母线功率平衡","4.4","Σp_source+p_dis+p_import = p_export+p_load+p_charge+p_electrolyzer+p_curt+p_loss","三目标共同底座","测点、线路/变压器损耗、辅机、自用电","逐时等式；损耗可分段线性","潮流/短路/谐波校核","更新损耗函数和端口上限"],
  ["储能/氢状态","4.5","SOC/H2库存递推、上下限、互斥充放、效率、退化、备用与黑启动能量","经济/可靠性为主，环保次之","效率图、退化、启停、备用、最低安全库存","MILP/MINLP或凸近似；快慢时间尺度分层","频率最低点、ROCOF、电压恢复、黑启动仿真","提高SOC/库存下限、备用量或缩小功率边界"],
  ["算力服务","4.6","任务到达—完成、功率/PUE、可延期/迁移、SLA与违约","经济/可靠性/环保","任务曲线、PUE、IT功率范围、SLA、价格与罚则","队列/时间窗线性化或滚动优化","热管理、通信与备用电验证","收紧可延期量和功率变化率"],
  ["外送与多形态输出","4.7","海缆容量/损耗、H2/NH3产储运、海洋负荷、合同交付上下限","三目标","合同、港口/船期、海缆限额、产品质量与储运损耗","容量/库存/批次和交付约束","海缆热稳、工艺动态、港口可达性","降低端口容量、增加安全库存/交付裕度"],
  ["故障/极端/共因场景","4.3—4.7","scenario s含天气、预测误差、设备/海缆/通信故障与恢复路径","可靠性主导","故障率、修复时间、天气窗、台风共因、备件物流","两阶段随机/鲁棒优化；EENS/LOLE/CVaR","故障序列和恢复演练","增加场景、提高备用、改变恢复策略"],
  ["投资与投收边界","4.8—4.9","容量/投资预算、建设期、寿命、更换、最低IRR或回收期上限","经济主导","EPC、融资、税务、折旧、寿命、价格合同","规划层与运营层分开；年化或DCF一致口径","商业尽调/合同压力测试","调整容量或产品组合"],
  ["碳核算与产品分摊","4.1/4.8","固定系统边界、功能单位、多产品分摊、回收与避免排放基准","环保主导","BOM/EPD、能耗、物流、冷媒、分摊规则","LCA清单与调度结果逐时联结","第三方LCA审查","修订因子、边界或分摊规则"]
];
s08.getRange(`A22:H${21 + constraints.length}`).values = constraints;
styleBody(s08.getRange(`A22:H${21 + constraints.length}`));
for (let r = 22; r <= 21 + constraints.length; r++) s08.getRange(`A${r}:H${r}`).format.fill = r % 2 ? "#F7FBFD" : paleBlue;
s08.getRange(`A22:H${21 + constraints.length}`).format.rowHeight = 62;

s08.getRange("A32:F32").values = [["建议小节","标题建议","写作主线","直接承接","向后输出","完成判据"]];
styleHeader(s08.getRange("A32:F32"), teal);
const sectionRows = [
  ["4.8.1","经济目标与财务口径","先冻结现金流边界，再定义年化净成本；NPV/IRR/LCOX作评价指标","4.3—4.7能量/产品量","F_eco及经济KPI","成本和收入无重复计量；含建设/更换/退役"],
  ["4.8.2","生命周期环境目标","定义功能单位和LCA边界，调度量映射到碳清单","4.1边界、4.3—4.7物质能量流","F_env及碳强度KPI","避免排放只用于基准对比；多产品分摊规则明确"],
  ["4.8.3","可靠性与韧性目标","以EENS为主目标，LOLE/关键负荷率/恢复时间为KPI","4.3随机出力、4.5构网与库存、4.6—4.7服务等级","F_rel及验收阈值","天气、故障、预测误差和共因事件均进入场景"],
  ["4.8.4","目标归一化与决策偏好","单目标理想点→归一化→Pareto/ε阈值→推荐解","三目标结果","目标向量、理想/最差点、决策阈值","权重由决策者确认并做敏感性"],
  ["4.9.1","约束条件总表","按4.3—4.7逐条引用，不复制推导；列索引、单位、线性化与状态条件","全部物理模型","统一可行域","每个约束可追溯到公式—参数—设备—来源"],
  ["4.9.2","不确定性与场景生成","同场同步天气+预测误差+故障/极端情景，保留相关性","4.3场景、企业故障/恢复数据","场景集及概率/鲁棒集合","训练、校准、验证时段相互独立"],
  ["4.9.3","分层求解与滚动执行","规划容量层—日前/日内调度层—秒级动态校核；失败则收紧代理边界","4.5快速仿真、EMS接口","可实施滚动计划","优化解通过功率平衡、设备、动态和合同四类校验"],
  ["4.9.4","基准、Pareto与敏感性","单一外送基准 vs 源储算用协同；正常/极端/故障；价格/碳/设备敏感性","所有目标与约束","提升幅度、Pareto前沿、推荐方案","经济/环保/可靠性指标采用同一边界和年份"]
];
s08.getRange("A33:F40").values = sectionRows;
styleBody(s08.getRange("A33:F40"));
for (let r = 33; r <= 40; r++) s08.getRange(`A${r}:F${r}`).format.fill = r % 2 ? "#F4FAFD" : paleBlue;
s08.getRange("A33:F40").format.rowHeight = 54;

s08.getRange("A42:F42").values = [["公开依据ID","文件/机构","用途","可公开获取内容","本模型使用边界","链接"]];
styleHeader(s08.getRange("A42:F42"));
const sources = [
  ["PUB-MO-01","IEC 60300-3-3:2017（IEC）","经济/全寿命成本","生命周期成本分析流程及可靠性相关成本框架","支撑成本边界；项目价格仍需企业校准","https://webstore.iec.ch/en/publication/31206"],
  ["PUB-MO-02","IRENA Project Navigator/LCOE方法","经济指标","折现现金流与LCOE结构式","支撑LCOE/折现口径；WACC、寿命、成本用项目值","https://www.irena.org/-/media/Files/IRENA/Agency/Events/2014/Jul/14/IRENA_Project_Navigator_training_2014.pdf"],
  ["PUB-MO-03","ISO 14040:2006 / ISO 14044:2006","环保/LCA","目标与范围、清单、影响评价、解释和审查","支撑LCA流程；设备清单和因子需企业/EPD","https://www.iso.org/standard/38498.html"],
  ["PUB-MO-04","ISO 14067:2018（ISO）","产品碳足迹","产品碳足迹量化原则","用于电、氢、氨、算力等功能单位强度","https://www.iso.org/standard/71206.html"],
  ["PUB-MO-05","IEA Electricity 2025—Reliability","可靠性/充裕度","天气和设备故障随机性、损失负荷小时等充裕度思路","支撑场景化可靠性方法；工程阈值仍需企业","https://www.iea.org/reports/electricity-2025/reliability"]
];
s08.getRange("A43:F47").values = sources;
styleBody(s08.getRange("A43:F47"));
for (let r = 43; r <= 47; r++) s08.getRange(`A${r}:F${r}`).format.fill = r % 2 ? "#F7FBFD" : paleBlue;
s08.getRange("A43:F47").format.rowHeight = 44;

// 3) 新增4.8—4.9企业数据清单。
const s09 = wb.worksheets.getOrAdd("09_多目标企业交流清单");
const old09 = s09.getUsedRange(); if (old09) old09.clear({ applyTo: "all" });
s09.deleteAllDrawings(); s09.showGridLines = false;
styleTitle(s09, "A1:L1", "4.8—4.9 多目标分析企业交流/数据取数清单");
styleNote(s09, "A2:L2", "本表只列公开资料不能替代、必须向企业/业主/设计院/承购方获取或确认的数据。公开资料用于方法、标准、行业先验和占位区间；合同价格、项目成本、故障与恢复、服务等级、BOM/EPD及运维实绩须按NDA分级管理。 ");
s09.getRange("A4:L4").values = [["取数ID","目标","对象/数据所有者","必须获取的数据/文件","映射公式参数/KPI","最小粒度/周期","为什么公开资料不能替代","可公开替代/先验","保密建议","关联章节","优先级","状态"]];
styleHeader(s09.getRange("A4:L4"));
const optRows = [
  ["OPT-COM-01","通用","项目公司/财务/设计院","投资与运营核算边界、币值年、含税/不含税、建设期、寿命、退役边界、共用资产分摊规则","全部目标的系统边界与functionalUnit","项目级；版本冻结","边界不同会造成三目标不可比","IEC/ISO方法框架","可只提供口径和比例","4.1、4.8、4.9","P0","未发起"],
  ["OPT-COM-02","通用","项目公司/调度/承购方","单一外送基准与协同方案的同边界配置、装机、投运年、利用率/可用率假设","baselineId、scenarioId、提升幅度","方案/年度","没有真实基准就无法回答“相比单一外送提升多少”","公开示范项目作外部参照","基准可匿名化","4.1、4.9.4","P0","未发起"],
  ["OPT-COM-03","通用","业主/EMS/数据平台","预测、实测、调度指令、事件/故障、价格和合同履约的统一时间轴及版本快照","scenario、forecastError、state、price","1min/15min/1h；≥1年","多目标需同场同周期联合计算，拼接数据会破坏相关性","再分析数据可作基线","安全沙箱或脱敏时间序列","4.3—4.9","P0","未发起"],
  ["OPT-ECO-01","经济","项目公司/EPC/设计院","风光潮、浮体/系泊、海上平台、储能、制氢/制氨、算力、海缆、港口及EMS分项CAPEX与工程量清单","C_cap、CRF、LCOX","设备/系统/建设年度","公开造价口径和边界差异大，不能代表项目投标价","行业报告/上市公告区间","分项指数化或区间化","4.5—4.8","P0","未发起"],
  ["OPT-ECO-02","经济","运维公司/业主/OEM","固定/变动OPEX、船舶/直升机/港口、巡检、保险、租赁、备件、清洗防腐和故障抢修实绩","C_om、C_repair、availabilityCost","月/年+工单事件；≥3年优先","海上运维受距离和天气窗强烈影响","公开行业均值","工单匿名、金额指数化","4.3、4.5、4.8","P0","未发起"],
  ["OPT-ECO-03","经济","财务/融资方","资本金与债务结构、WACC/贴现率、贷款期、税率、折旧、补贴、通胀与汇率口径","r、CRF、NPV、IRR、tax","方案/年度","融资条件决定资本密集项目结果","央行/政策利率作情景","仅给区间/目标收益率","4.8、4.9","P0","未发起"],
  ["OPT-ECO-04","经济","OEM/业主/财务","各设备寿命、退化、检修大修与更换计划、残值、退役和海上拆除成本","C_deg、C_replace、EOL、salvage","设备/年度/循环","公开设计寿命不能替代实绩和质保条款","厂家公开质保/文献曲线","匿名化型号和质保条件","4.3、4.5、4.8","P0","未发起"],
  ["OPT-ECO-05","经济","电网/售电/承购方","外送电价、容量/辅助服务收入、偏差/考核、限发补偿、购电价、结算周期和合同上下限","R_elec、C_buy、C_curt、penalty","逐时/结算周期/合同期","公开标杆价不等于项目结算合同","政府价格/市场规则","金额可归一化；保留机制","4.7、4.8、4.9","P0","未发起"],
  ["OPT-ECO-06","经济","储能OEM/业主","储能效率图、寿命/退化、循环与日历老化、最低备用SOC、扩容/更换及质保罚则","C_deg、η_ch/dis、SOC、C_replace","功率/SOC/温度工况；循环级","额定效率无法生成边际退化成本","公开电芯曲线作先验","可提供拟合系数和包络","4.5、4.8、4.9","P0","未发起"],
  ["OPT-ECO-07","经济","制氢/制氨OEM、EPC、业主","电解槽/空分/合成氨效率与负荷曲线、启停、辅机、寿命、堆更换、纯度与产量","C_start、C_replace、P2H、H2/NH3产量","秒/分钟动态+小时能耗+年度更换","铭牌效率不能代表部分负荷和海上辅机","标准/论文曲线","降阶模型+匿名参数","4.5、4.7、4.8","P0","未发起"],
  ["OPT-ECO-08","经济","氢氨承购方/港口/物流商","绿氢/绿氨承购价、最低交付、质量、take-or-pay、储罐/装卸/船期、损耗、港口与运输费用","R_H2、R_NH3、C_logistics、penalty","批次/航次/合同期","公开现货价不能替代长期承购和物流约束","市场价格作敏感性","合同条款分级脱敏","4.7、4.8、4.9","P0","未发起"],
  ["OPT-ECO-09","经济","算力运营商/设备商/客户","IT及海底舱CAPEX/OPEX、实测PUE、可延期/迁移范围、作业队列、SLA、服务单价与违约罚则","R_compute、PUE、C_SLA、workload","1min/15min；作业级；合同期","算力收益和柔性来自真实业务/SLA，不是额定功率","公开云价/PUE作上限基线","作业匿名、价格指数化","4.6、4.8、4.9","P0","未发起"],
  ["OPT-ECO-10","经济","海缆/电气总包/保险方","动态海缆/集电/外送系统CAPEX、损耗、可用率、故障修复和保险免赔/停运损失","C_cable、loss、C_repair、availability","线路/年度+故障事件","深远海距离、路由与抢修资源使公开单价失真","典型造价区间","路由与金额脱敏","4.4、4.7、4.8","P0","未发起"],
  ["OPT-ENV-01","环保","设备OEM/EPC/供应链","主要设备BOM、材料/质量、EPD/PCF、制造能源、原产地和运输距离","E_emb、EF_material、EF_transport","设备/批次/供应商","通用数据库无法反映国产具体设备和供应链","ecoinvent/行业EPD作先验","BOM可只给材料汇总和EPD","4.3、4.5—4.8","P0","未发起"],
  ["OPT-ENV-02","环保","施工/运维公司/船东","安装、打桩/系泊、拖航、运维船舶/直升机的燃料、航次、距离、负载和天气等待","E_fuel、E_logistics","航次/工单/年度","海上活动是项目特定清单项","船型排放因子作先验","船名/航线匿名","4.3、4.5、4.8","P0","未发起"],
  ["OPT-ENV-03","环保","OEM/回收/退役承包商","备件更换、废弃物、回收率、再制造、危废处理和退役路径","E_replace、E_recycle、E_EOL","设备/材料/年度","回收信用高度依赖实际去向与合同","法规/行业回收率区间","去向和比例可脱敏","4.5、4.8","P1","未发起"],
  ["OPT-ENV-04","环保","电网/售电/业主","购电来源、逐时或分时排放因子、绿证/合同属性及避免重复核算规则","E_grid、EF_grid(t)","小时/月/年度","平均电网因子不能替代实际购电属性与边际时段","生态环境部门/电网公开因子","合同名称可隐去","4.4、4.8","P0","未发起"],
  ["OPT-ENV-05","环保","制氢/制氨OEM/业主","纯水/海水处理、压缩、储运、空分、合成、放空/泄漏、催化剂/冷媒及辅助电耗","E_process、leakage、auxEnergy","工艺单元/负荷点/批次","主设备效率遗漏大量边界过程","论文/标准流程先验","工艺参数区间化","4.5、4.7、4.8","P0","未发起"],
  ["OPT-ENV-06","环保","算力运营商/冷却设备商","PUE分解、冷却/泵/通信能耗、冷媒种类与补充量、设备更换和报废路径","E_compute、E_refrig、PUE","1min/小时+年度维护","目标PUE不能代表全寿命环境清单","公开PUE/冷媒GWP","只需汇总能耗和冷媒量","4.6、4.8","P1","未发起"],
  ["OPT-ENV-07","环保","项目公司/第三方LCA/承购方","电、氢、氨、算力多产品功能单位、分摊规则、系统扩展和避免排放基准","allocation、functionalUnit、avoidedBaseline","方案/年度","分摊规则是管理和合同选择，不能由模型擅定","ISO 14040/14044/14067","经审查的口径文件","4.1、4.8、4.9","P0","未发起"],
  ["OPT-REL-01","可靠性","各OEM/业主/保险/运维","风光潮、储能、电解槽、算力舱、变压器/变流器/开关、海缆的故障率、降额率、MTTR与可用率","λ、MTTR、FOR、availability","部件/故障模式；≥3年优先","公开平均值不能反映海洋环境和具体型号","OREDA/论文先验","故障模式编码、厂家匿名","4.3—4.7、4.8","P0","未发起"],
  ["OPT-REL-02","可靠性","业主/海洋预报/运维物流","台风、极端浪流/盐雾引发的共因失效、停机范围、天气可达窗口、船舶/备件动员和恢复序列","scenario、commonCause、recoveryTime","事件级；完整恢复链","独立故障假设会低估深远海风险","公开气象/台风路径","事件匿名、时刻平移","4.3、4.5、4.9","P0","未发起"],
  ["OPT-REL-03","可靠性","电网/海缆业主/调度","外部电网与外送通道停运、N-1方式、检修计划、并离网切换和恢复时间","gridState、cableState、N-1、MTTR","事件/计划级","能源岛可靠性受单一海缆和陆网状态显著影响","公开停电统计作先验","拓扑和事件脱敏","4.4、4.7、4.9","P0","未发起"],
  ["OPT-REL-04","可靠性","负荷业主/算力客户/制氢/海洋用能方","负荷等级、可中断时长、最低供能、SLA、VOLL/违约罚则和恢复优先级","P_unserved、EENS、VOLL、criticality","负荷/作业/合同级","没有服务等级就无法定义“未供能”及其后果","行业VOLL/SLA作敏感性","客户匿名、罚则指数化","4.6—4.8","P0","未发起"],
  ["OPT-REL-05","可靠性","并网方/构网储能OEM/业主","备用标准、N-1、短路比、频率最低点/ROCOF/稳态偏差、电压恢复、黑启动验收与最低SOC/H2库存","reserveReq、f_nadir、ROCOF、SOC_min","典型/故障工况；试验报告","标准给原则但项目整定和验收阈值不同","GB/IEC/IEEE标准框架","提供包络和通过/失败结论","4.5、4.8、4.9","P0","未发起"],
  ["OPT-REL-06","可靠性","业主/预测服务商/EMS","风光潮及负荷预测误差的联合分布、空间/时间相关、极端分位、场景削减与实际偏差考核","forecastError、π_s、CVaR、reserveReq","发布时间×预测时域；≥1年","公开气象无法复现生产预测与调度误差","再分析+公开预测作基线","模型匿名，仅交误差与分位","4.3、4.9","P0","未发起"],
  ["OPT-REL-07","可靠性","EMS/通信/网络安全方","测控通信可用率、延迟、丢包、时钟失步、降级控制、人工接管和网络安全事件边界","commState、latency、fallbackMode","秒级事件+年度统计","通信故障会使可用设备无法被调度","标准测试场景","网络拓扑脱敏","4.3—4.6、4.9","P1","未发起"],
  ["OPT-REL-08","可靠性","运维/仓储/供应链","关键备件库存、补货周期、专用船舶/吊装资源、维修人员与港口可用性","repairDelay、spareState、recoveryTime","备件/故障/季节","MTTR若忽略物流会严重偏低","行业维修时长区间","库存和港口匿名","4.3、4.5、4.9","P1","未发起"],
  ["OPT-REL-09","可靠性","第三方检测/业主/调度","历史独立事故/演练、黑启动、孤网运行、负荷切除和恢复测试记录及验收结论","validationSet、passRate、recoveryKPI","事件/演练级","用于验证优化器可靠性目标确实对应工程表现","标准测试用例","安全沙箱，仅输出KPI","4.5、4.9","P0","未发起"]
];
s09.getRange(`A5:L${4 + optRows.length}`).values = optRows;
styleBody(s09.getRange(`A5:L${4 + optRows.length}`));
for (let r = 5; r <= 4 + optRows.length; r++) {
  const obj = s09.getRange(`B${r}`).values[0][0];
  const fill = obj === "经济" ? paleGold : obj === "环保" ? paleGreen : obj === "可靠性" ? paleRed : paleBlue;
  s09.getRange(`A${r}:L${r}`).format.fill = (r % 2 === 1) ? fill : "#F7FBFD";
  s09.getRange(`K${r}`).format.fill = paleGold;
}
s09.getRange(`A5:L${4 + optRows.length}`).format.rowHeight = 62;
s09.getRange(`K5:K${4 + optRows.length}`).dataValidation = { rule: { type: "list", values: ["P0","P1","P2"] } };
s09.getRange(`L5:L${4 + optRows.length}`).dataValidation = { rule: { type: "list", values: ["未发起","沟通中","已获取","不可获取","用公开替代"] } };
s09.freezePanes.freezeRows(4);

// 统一列宽和字体。
const widths06 = [14,22,48,42,25,25,30,28,10,12];
widths06.forEach((w,i)=>s06.getRangeByIndexes(0,i,32,1).format.columnWidth=w);
const widths08 = [13,18,52,25,28,30,18,30,26,30,34,18];
widths08.forEach((w,i)=>s08.getRangeByIndexes(0,i,47,1).format.columnWidth=w);
const widths09 = [14,10,24,48,30,26,42,32,28,20,10,12];
widths09.forEach((w,i)=>s09.getRangeByIndexes(0,i,4+optRows.length,1).format.columnWidth=w);
s08.getRange("A1:L47").format.font = { name: "Microsoft YaHei", size: 10 };
s09.getRange(`A1:L${4 + optRows.length}`).format.font = { name: "Microsoft YaHei", size: 10 };
s08.freezePanes.freezeRows(4);

// 视觉预览与导出。
for (const name of ["06_企业交流清单","08_4.8-4.9目标架构","09_多目标企业交流清单"]) {
  const png = await wb.render({ sheetName: name, autoCrop: "all", scale: 0.75, format: "png" });
  await fs.writeFile(`${outputDir}/previews/${name}.png`, new Uint8Array(await png.arrayBuffer()));
}
const out = await SpreadsheetFile.exportXlsx(wb);
await out.save(outputPath);
const check = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, maxChars: 4000 });
console.log(check.ndjson);
console.log(outputPath);
