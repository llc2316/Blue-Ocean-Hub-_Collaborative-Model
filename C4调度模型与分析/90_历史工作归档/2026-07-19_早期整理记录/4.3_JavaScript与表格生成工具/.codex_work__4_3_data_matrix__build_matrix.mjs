import fs from "node:fs/promises";
import path from "node:path";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const outputDir = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_data_freeze";
const outputPath = path.join(outputDir, "蓝海枢纽_4.3数据冻结与证据矩阵.xlsx");
const previewDir = path.join(outputDir, "previews");

const wb = Workbook.create();

const C = {
  navy: "#17365D", blue: "#1F4E78", teal: "#0F6B78", lightBlue: "#D9EAF7",
  paleBlue: "#EAF3F8", lightGreen: "#E2F0D9", lightAmber: "#FFF2CC",
  lightRed: "#FCE4D6", gray: "#E7E6E6", darkGray: "#666666", white: "#FFFFFF"
};

function colName(n) {
  let s = "";
  while (n > 0) { n--; s = String.fromCharCode(65 + (n % 26)) + s; n = Math.floor(n / 26); }
  return s;
}

function addDataSheet(name, title, note, headers, rows, widths = []) {
  const sh = wb.worksheets.add(name);
  sh.showGridLines = false;
  const last = colName(headers.length);
  sh.getRange(`A1:${last}1`).merge();
  sh.getRange("A1").values = [[title]];
  sh.getRange(`A1:${last}1`).format = {
    fill: C.navy, font: { bold: true, color: C.white, size: 15 },
    verticalAlignment: "center", rowHeight: 30
  };
  sh.getRange(`A2:${last}2`).merge();
  sh.getRange("A2").values = [[note]];
  sh.getRange(`A2:${last}2`).format = {
    fill: C.paleBlue, font: { color: "#404040", italic: true }, wrapText: true,
    verticalAlignment: "center", rowHeight: 36
  };
  sh.getRange(`A4:${last}4`).values = [headers];
  sh.getRange(`A4:${last}4`).format = {
    fill: C.blue, font: { bold: true, color: C.white }, wrapText: true,
    horizontalAlignment: "center", verticalAlignment: "center", rowHeight: 38,
    borders: { preset: "outside", style: "medium", color: C.navy }
  };
  if (rows.length) {
    sh.getRange(`A5:${last}${rows.length + 4}`).values = rows;
    sh.getRange(`A5:${last}${rows.length + 4}`).format = {
      font: { size: 10, color: "#222222" }, verticalAlignment: "top", wrapText: true,
      borders: { insideHorizontal: { style: "thin", color: "#D9E1F2" } }
    };
    const table = sh.tables.add(`A4:${last}${rows.length + 4}`, true, `${name.replace(/[^A-Za-z0-9]/g, "") || "T"}Table`);
    table.style = "TableStyleMedium2";
  }
  sh.freezePanes.freezeRows(4);
  sh.freezePanes.freezeColumns(Math.min(2, headers.length));
  widths.forEach((w, i) => { sh.getRange(`${colName(i + 1)}:${colName(i + 1)}`).format.columnWidth = w; });
  return sh;
}

function addClassFormatting(sh, range, values) {
  // Keep category columns visibly distinct without renderer-dependent conditional rules.
  sh.getRange(range).format.fill = C.lightAmber;
}

// 00 使用说明
const s0 = wb.worksheets.add("00_使用说明");
s0.showGridLines = false;
s0.getRange("A1:H1").merge();
s0.getRange("A1").values = [["蓝海枢纽｜4.3数据冻结与证据矩阵"]];
s0.getRange("A1:H1").format = { fill: C.navy, font: { bold: true, color: C.white, size: 17 }, rowHeight: 34 };
s0.getRange("A3:H3").merge();
s0.getRange("A3").values = [["用途：冻结源侧测点与损耗边界，管理变量、国产参考设备、同场同步数据和证据闭环。公开资料只能建立基线，真实设备参数必须用企业数据校准。"]];
s0.getRange("A3:H3").format = { fill: C.paleBlue, wrapText: true, rowHeight: 38, font: { color: "#333333" } };
s0.getRange("A5:B10").values = [
  ["关键统计", "数量"],
  ["变量总数", null],
  ["公开可获取", null],
  ["必须企业交流", null],
  ["公开基线+企业校准", null],
  ["证据条目", null]
];
s0.getRange("B6").formulas = [["=COUNTA('02_统一变量字典'!$A$5:$A$200)"]];
s0.getRange("B7").formulas = [["=COUNTIF('02_统一变量字典'!$L$5:$L$200,\"公开可获取\")"]];
s0.getRange("B8").formulas = [["=COUNTIF('02_统一变量字典'!$L$5:$L$200,\"必须企业交流\")"]];
s0.getRange("B9").formulas = [["=COUNTIF('02_统一变量字典'!$L$5:$L$200,\"公开基线+企业校准\")"]];
s0.getRange("B10").formulas = [["=COUNTA('05_证据矩阵'!$A$5:$A$200)"]];
s0.getRange("A5:B5").format = { fill: C.blue, font: { bold: true, color: C.white } };
s0.getRange("A6:A10").format = { fill: C.paleBlue, font: { bold: true } };
s0.getRange("B6:B10").format = { fill: C.lightGreen, font: { bold: true }, horizontalAlignment: "center", numberFormat: "0" };
s0.getRange("D5:H5").merge();
s0.getRange("D5").values = [["数据获取分级"]];
s0.getRange("D5:H5").format = { fill: C.teal, font: { bold: true, color: C.white } };
s0.getRange("D6:H9").values = [
  ["公开可获取", "标准目录/公开全文", "企业官网/公告", "政府示范项目", "再分析/开放科学数据"],
  ["公开基线+企业校准", "公式结构", "额定值/公开型号", "资源长期序列", "最终用于模型前必须同场校准"],
  ["必须企业交流", "真实功率曲线", "P-Q能力与保护阈值", "辅机/损耗分解", "SCADA、故障、运维及控制器参数"],
  ["不可直接采用", "新闻稿增益数字", "无测点说明的效率", "不同场址拼接序列", "把项目容量比例当逐时出力权重"]
];
s0.getRange("D6:H9").format = { wrapText: true, verticalAlignment: "top", borders: { preset: "all", style: "thin", color: "#D9E1F2" } };
s0.getRange("D6:D9").format = { font: { bold: true } };
s0.getRange("D6:H6").format.fill = C.lightGreen;
s0.getRange("D7:H7").format.fill = C.lightAmber;
s0.getRange("D8:H8").format.fill = C.lightRed;
s0.getRange("D9:H9").format.fill = C.gray;
s0.getRange("A13:H13").merge();
s0.getRange("A13").values = [["冻结结论（用于4.3）"]];
s0.getRange("A13:H13").format = { fill: C.blue, font: { bold: true, color: C.white } };
s0.getRange("A14:H19").values = [
  ["1", "统一发电测点", "source_collection_bus：扣除源内集电/变压损耗后的发电注入；不扣源侧辅机。", null, null, null, null, null],
  ["2", "辅机口径", "pSourceAux作为4.4消耗端口单列，禁止在单源模型和4.4重复扣除。", null, null, null, null, null],
  ["3", "损耗边界", "4.3只负责设备端至source_collection_bus；公共母线后变压器/海缆损耗归4.4/4.9。", null, null, null, null, null],
  ["4", "设备基准", "风电：三峡引领号5.5MW运行基准+明阳OceanX 16.6MW前沿情景；光伏：半岛南3号500kW系统+隆基海光专用组件候选；潮流能：LHD奋进号1.6MW。", null, null, null, null, null],
  ["5", "数据原则", "公开再分析用于长期资源与先验场景；同场传感器和SCADA用于设备校准、状态机和验证。", null, null, null, null, null],
  ["6", "当前状态", "本表冻结的是字段、测点、来源类别和取数路线；未取得企业数据的数值仍为[假设值，待企业调研校准]。", null, null, null, null, null]
];
for (let r = 14; r <= 19; r++) s0.getRange(`C${r}:H${r}`).merge();
s0.getRange("A14:H19").format = { wrapText: true, verticalAlignment: "top", borders: { insideHorizontal: { style: "thin", color: "#D9E1F2" } } };
s0.getRange("A14:A19").format = { fill: C.paleBlue, font: { bold: true }, horizontalAlignment: "center" };
s0.getRange("B14:B19").format = { font: { bold: true } };
s0.freezePanes.freezeRows(3);
[7,20,19,17,17,17,17,17].forEach((w,i)=>s0.getRange(`${colName(i+1)}:${colName(i+1)}`).format.columnWidth=w);

// 01 测点损耗边界
const boundaryHeaders = ["ID","层级/测点","冻结变量","正方向","包含内容","不包含内容","损耗/辅机处理","归属章节","数据获取","冻结状态","核验/备注"];
const boundaryRows = [
  ["MP-00","环境资源面","wind/solar/current/wave fields","按各物理量约定","风、光、流、浪、温度、姿态原始观测","任何发电效率或损耗","只做资源输入，不在此扣损","4.3输入","公开基线+企业同场观测","已冻结","统一UTC、坐标、垂向基准"],
  ["MP-01","设备变流器/发电机交流端","pAvailableGross,pActualGross","向集电网为正","单台设备端毛发电功率","源内集电损耗、源侧辅机、公共母线损耗","功率曲线若已是交流电功率，不再重复乘发电机/变流器效率","4.3单源模型","公开基线+企业校准","已冻结","设备端真实曲线通常为企业数据"],
  ["MP-02","源内集电网","pCollectionLoss","损耗取非负","阵列电缆、源侧升压设备及约定到公共汇集点的损耗","源侧辅机、岛级公共辅机、外送海缆损耗","pAvailableAtPOI=pAvailableGross-pCollectionLoss","4.3适配层","必须企业交流","已冻结","V2三源扣损顺序不一致，V3必须统一"],
  ["MP-03","源侧公共汇集点 source_collection_bus","pAvailableAtPOI,pAccepted,pActualAtPOI","发电注入母线为正","已扣MP-02损耗的逐源发电注入","pSourceAux、公共辅机、储能、负荷端口及POI后损耗","4.3标准输出测点","4.3输出/4.4输入","设计单线图+企业计量","已冻结","不要称为“净发电”，因尚未扣源侧辅机"],
  ["MP-04","源侧辅机负荷","pSourceAux","消耗为正","风机/光伏/潮流装置运行与待机辅机","岛级公共辅机","作为4.4负荷端口单列，只扣一次","4.4输入","必须企业交流","已冻结","需分运行/待机/停机状态"],
  ["MP-05","能源岛公共母线","pSourceActual,pStorageActual,pOtherInjection","注入为正、消耗端口取正","源侧注入、储能、其他电源与各价值端口","设备内部损耗明细","建立守恒，不替代设备状态机","4.4","设计院+EMS/SCADA","已冻结","储能正放电、负充电需全文统一"],
  ["MP-06","公共母线后网络/外送链路","pPostPOILoss,pExport","外送与损耗为正消耗","公共变压器、变流、动态电缆/海缆损耗","源内集电损耗","采用随负载变化模型或分段线性近似","4.4/4.9","公开公式+企业线路参数","已冻结","禁止以固定百分比重复扣损"],
  ["MP-07","价值端口计量","pElectrolyzer,pCompute,pMarine,pExport","各用能端口消耗为正","已服务负荷/外送功率","未供电需求","未供电量单列pUnservedLoad","4.4/4.8-4.9","企业计量/合同","已冻结","算力需明确IT功率与设施总功率/PUE"],
  ["EQ-01","4.4功率守恒","balanceMismatch","注入-消耗","source+storage+other+import 与 served demand+loss+spill","pUnservedLoad不得重复进入servedDemand","闭合误差应接近零","4.4","项目定义","已冻结","失负荷采用“原始需求-已服务需求”口径"]
];
const s1 = addDataSheet("01_测点损耗边界","测点及损耗边界冻结表","红色项通常必须与企业/设计院获取；冻结后，任何模型不得自行改变扣损顺序。",boundaryHeaders,boundaryRows,[10,24,25,15,29,28,34,16,22,14,34]);
addClassFormatting(s1,"I5:I13",[["必须企业交流",C.lightRed],["公开基线+企业",C.lightAmber],["项目定义",C.lightBlue]]);

// 02 统一变量字典
const varHeaders = ["变量ID","模块","V3字段","符号","中文名称","角色","数据类型/维度","单位","正方向/取值域","测点","公开来源/依据","获取分类","企业交流内容","当前状态","备注"];
const varRows = [
  ["COM-001","公共","time","t","统一时间戳","外生索引","N×1 datetime/秒","UTC","严格递增","全系统","项目定义/原始数据时间戳","公开基线+企业校准","SCADA时钟、NTP/PTP同步精度","字段冻结","统一保存UTC，展示时转北京时间"],
  ["COM-002","公共","sourceId","—","电源唯一标识","静态参数","字符串","—","唯一","元数据","项目定义","公开可获取","最终设备/场站编码规则","字段冻结","禁止用中文简称作主键"],
  ["COM-003","公共","sourceType","i","电源类型","静态参数","枚举","—","wind/pv/tidal","元数据","项目定义","公开可获取","EMS类型编码映射","字段冻结",""],
  ["COM-004","公共","meterPoint","—","统一测点","静态参数","字符串","—","source_collection_bus","MP-03","设计单线图","必须企业交流","单线图和计量点清单","字段冻结","不一致则禁止聚合"],
  ["COM-005","公共","parameterSetId","—","参数版本","静态参数","字符串","—","唯一版本号","元数据","项目管理","公开可获取","OEM参数版本/固件版本","字段冻结","支撑可追溯复现"],
  ["COM-006","公共","qualityFlag","qf","数据质量标志","外生/输出","N×S枚举","—","valid/missing/outlier/extrapolated","各测点","数据质量规则","公开基线+企业校准","SCADA质量码和检修标志","待细化","不能仅用逻辑true/false"],
  ["COM-007","公共","availabilityState","a_state","物理可用状态","外生状态","N×M逻辑","—","0/1","设备级","SCADA/运维记录","必须企业交流","故障、检修、通信中断标记","字段冻结","与连续可用率分开"],
  ["COM-008","公共","availabilityFactor","a_factor","可用容量比例","外生状态","N×M数值","—","0—1","设备级","公开可靠性先验","公开基线+企业校准","真实可用率与降容记录","字段冻结",""],
  ["COM-009","公共","derateFactor","d","降额系数","控制/状态","N×M数值","—","0—1","设备级","厂家公开原则","必须企业交流","环境/温度/电气降额曲线","字段冻结","统一替代derate字段"],
  ["COM-010","公共","operatingState","z","物理运行状态","状态变量","N×S枚举","—","normal/standby/protected/restart/unavailable/transition","设备/源级","OEM控制逻辑","必须企业交流","状态机与复归计时","待统一编码","不得混入EMS限发原因"],
  ["COM-011","公共","constraintCode","c","受限原因","诊断输出","N×S枚举","—","resource/rated/ramp/EMS/environment/PQ等","MP-03","项目定义+设备反馈","公开基线+企业校准","控制器限幅与告警码映射","字段冻结","与operatingState分开"],
  ["SRC-001","统一源接口","pAvailableGross","P_av,gross","设备端可用毛功率","物理输出","N×S","W","向集电网为正","MP-01","设备曲线/模型","公开基线+企业校准","现场功率曲线、环境修正","字段冻结","不扣集电损耗与辅机"],
  ["SRC-002","统一源接口","pCollectionLoss","P_loss,col","源内集电损耗","物理输出","N×S","W","非负","MP-02","I²R/潮流模型","必须企业交流","电缆/变压器参数、负载损耗","字段冻结","禁止固定比例作为最终模型"],
  ["SRC-003","统一源接口","pAvailableAtPOI","P_av","公共汇集点可用发电注入","物理边界","N×S","W","非负","MP-03","守恒定义","公开基线+企业校准","测点核对与损耗校准","字段冻结","'=gross-collection loss，不扣辅机"],
  ["SRC-004","统一源接口","pRequested","P_req","EMS请求功率","决策输入","N×S","W","非负","MP-03","EMS模型","必须企业交流","AGC/EMS接口、刷新周期","字段冻结","保留原始请求"],
  ["SRC-005","统一源接口","pAccepted","P_acc","设备接受功率","设备反馈","N×S","W","0≤acc≤available","MP-03","状态机/能力边界","必须企业交流","控制器接受逻辑","字段冻结","聚合函数不得静默裁剪"],
  ["SRC-006","统一源接口","pActualAtPOI","P_act","实际发电注入","测量/输出","N×S","W","非负","MP-03","SCADA/计量","必须企业交流","高频功率与计量对账","字段冻结","不扣源侧辅机"],
  ["SRC-007","统一源接口","pSourceAux","P_aux","源侧辅机负荷","负荷输出","N×S","W","消耗取正","MP-04","厂用电设计/SCADA","必须企业交流","运行/待机/停机辅机曲线","字段冻结","在4.4只扣一次"],
  ["SRC-008","统一源接口","pForecastAvailable","P_fcst","可用功率点预测","预测输入","N×S","W","非负","MP-03","预测模型","公开基线+企业校准","历史预测与实绩","字段冻结","不得由actual加噪声反推"],
  ["SRC-009","统一源接口","scenarioAvailable","P_scen","联合可用功率场景","不确定性输入","N×S×K","W","非负","MP-03","场景生成文献","公开基线+企业校准","同场历史与预测误差","字段冻结","必须保持源间和时间相关性"],
  ["SRC-010","统一源接口","scenarioProbability","π_k","场景概率","参数","K×1","—","非负且和为1","场景层","统计模型","公开基线+企业校准","历史频率/校准结果","待加入代码",""],
  ["SRC-011","统一源接口","qMinAtPOI","Q_min","无功下界","物理边界","N×S","var","≤Q≤","MP-03","P-Q能力图","必须企业交流","变流器能力图、并网试验","字段冻结","不能长期用视在功率圆替代"],
  ["SRC-012","统一源接口","qMaxAtPOI","Q_max","无功上界","物理边界","N×S","var","≥Q","MP-03","P-Q能力图","必须企业交流","变流器能力图、并网试验","字段冻结","需网络电压/电流校核"],
  ["SRC-013","统一源接口","pUpCapability","R_up","上调能力","能力输出","N×S","W","非负","MP-03","控制与资源边界","必须企业交流","AGC实测与响应时间","字段冻结",""],
  ["SRC-014","统一源接口","pDownCapability","R_down","下调能力","能力输出","N×S","W","非负","MP-03","控制与资源边界","必须企业交流","AGC实测与保护动作","字段冻结","资源骤降不受普通rampDown阻挡"],
  ["W-001","漂浮式风电","windSpeed","v_hub","轮毂高度风速","外生时序","N×M","m/s","沿转子轴定义","MP-00","ERA5/测风标准","公开基线+企业校准","激光雷达/机舱测风原始数据","字段冻结","再分析不得替代场址校准"],
  ["W-002","漂浮式风电","windDirection","θ_w","风向","外生时序","N×M","deg/rad","统一气象/数学方向","MP-00","ERA5/测风","公开基线+企业校准","同场风向与偏航角","待加入代码",""],
  ["W-003","漂浮式风电","surgeVelocity","ẋ_surge","平台纵荡速度","外生时序","N×M","m/s","机组坐标系","平台传感/OpenFAST","耦合仿真方法","必须企业交流","6DOF传感与平台模型","字段冻结",""],
  ["W-004","漂浮式风电","pitchRate","θ̇_pitch","平台纵摇角速度","外生时序","N×M","rad/s","机组坐标系","平台传感/OpenFAST","耦合仿真方法","必须企业交流","IMU与平台模型","字段冻结",""],
  ["W-005","漂浮式风电","powerCurveWind","v_pc","功率曲线风速断点","设备参数","B×1","m/s","递增","MP-01","IEC 61400-12-1/OEM","必须企业交流","经密度/湍流/控制版本修正的曲线","字段冻结","公开额定点只能作占位"],
  ["W-006","漂浮式风电","powerCurveP","P_pc","功率曲线电功率","设备参数","B×1","W","非负","MP-01","IEC 61400-12-1/OEM","必须企业交流","实际型号曲线及不确定度","字段冻结",""],
  ["W-007","漂浮式风电","ratedPower","P_w^r","额定有功","设备参数","标量/台","W","正值","MP-01","企业官网/认证","公开可获取","合同冻结值","字段冻结",""],
  ["W-008","漂浮式风电","cutOutWind/restartWind","v_co/v_re","切出与复归阈值","设备参数","标量","m/s","v_re<v_co","状态机","OEM控制规范","必须企业交流","高风速停机/再启动逻辑","字段冻结","不能凭通用值冒充"],
  ["W-009","漂浮式风电","rampUp/rampDown","R_w","受控爬坡限值","设备参数","标量","W/s","非负","MP-03","并网试验/OEM","必须企业交流","不同工况下动态限值","字段冻结",""],
  ["PV-001","漂浮式光伏","dni/dhi/ghi","G_DNI/G_DHI/G_GHI","三分量辐照","外生时序","N×1","W/m²","非负","MP-00","ERA5/NASA POWER","公开基线+企业校准","同场辐照站原始数据","字段冻结","三个分量需闭合检查"],
  ["PV-002","漂浮式光伏","sunVector","s_sun","太阳向量","派生输入","N×3","—","ENU单位向量","MP-00","太阳位置算法","公开可获取","现场坐标/时间核对","字段冻结",""],
  ["PV-003","漂浮式光伏","roll/pitch/yaw","φ/θ/ψ","平台姿态","外生时序","N×3","rad","右手系","平台IMU","必须企业交流","IMU、浮体/系泊模型","字段冻结","决定动态POA"],
  ["PV-004","漂浮式光伏","ambientTemp","T_a","环境温度","外生时序","N×1","°C","实测","MP-00","ERA5/NASA POWER","公开基线+企业校准","同场温湿度","字段冻结",""],
  ["PV-005","漂浮式光伏","moduleTemperature","T_m","组件温度","外生/派生","N×M","°C","实测优先","组件背板","IEC 61853-2","必须企业交流","组件温度传感器数据","字段冻结","用于校准U0/U1"],
  ["PV-006","漂浮式光伏","powerMatrixPu","f(G,T)","辐照-温度功率矩阵","设备参数","I×J","p.u.","非负","组件DC侧","IEC 61853-1/OEM","公开基线+企业校准","实际组件矩阵/Flash test","可选优先","优于单一线性温度系数"],
  ["PV-007","漂浮式光伏","gammaP","γ_P","最大功率温度系数","设备参数","标量","1/°C","通常为负","组件DC侧","组件数据表","公开可获取","批次实测/海上校准","字段冻结",""],
  ["PV-008","漂浮式光伏","U0/U1","U0/U1","温度模型系数","校准参数","标量","模型单位","按模型定义","组件热模型","IEC 61853-2/论文","公开基线+企业校准","同场温度拟合","字段冻结","不能直接沿用陆地默认值"],
  ["PV-009","漂浮式光伏","soilingFactor","f_soil","污损/盐沉积系数","时变参数","N×M","—","0—1","组件面","公开论文/试验","必须企业交流","清洗前后I-V/盐沉积监测","字段冻结",""],
  ["PV-010","漂浮式光伏","invEfficiencyCurve","η_inv","逆变器效率曲线","设备参数","B×2","—","0—1","逆变器交流端","厂家数据表","公开基线+企业校准","海上温度/功率实测","字段冻结",""],
  ["PV-011","漂浮式光伏","maxOperatingWind/Wave","v_max/Hs_max","环境停机边界","设备参数","标量","m/s,m","安全边界","状态机","支撑系统/认证","必须企业交流","浮体、连接、系泊安全文件","字段冻结","公开抗极限不等于运行阈值"],
  ["TC-001","潮流能","axialVelocity","u","有符号轴向流速","外生时序","N×M","m/s","涨/落潮有符号","MP-00","ADCP/资源数据","公开基线+企业校准","机位ADCP剖面与坐标","字段冻结","必须穿越静水"],
  ["TC-002","潮流能","flowDirection","θ_c","流向","外生时序","N×M","deg/rad","统一坐标","MP-00","Copernicus/ADCP","公开基线+企业校准","同场流向与机组朝向","待加入代码",""],
  ["TC-003","潮流能","turbulenceIntensity","TI_c","流场湍流强度","外生/派生","N×M","—","非负","转子面","现场测试/论文","必须企业交流","ADCP高频数据","待加入代码","影响功率与载荷"],
  ["TC-004","潮流能","floodCurveSpeed/PowerPu","f_flood(u)","涨潮功率曲线","设备参数","B×2","m/s,p.u.","非负","MP-01","GB/T 41342/IEC 62600-200","必须企业交流","现场实测曲线和不确定度","字段冻结",""],
  ["TC-005","潮流能","ebbCurveSpeed/PowerPu","f_ebb(u)","落潮功率曲线","设备参数","B×2","m/s,p.u.","非负","MP-01","GB/T 41342/IEC 62600-200","必须企业交流","现场实测曲线和不确定度","字段冻结","不能假定与涨潮相同"],
  ["TC-006","潮流能","directionDeadband","u_db","换向死区","设备参数","标量","m/s","非负","状态机","OEM/现场试验","必须企业交流","换向控制逻辑","字段冻结",""],
  ["TC-007","潮流能","reorientationDelay","T_ori","换向时间","状态参数","标量","s","非负","状态机","OEM/现场试验","必须企业交流","双向换向实测","字段冻结",""],
  ["TC-008","潮流能","wakeVelocityFactor","f_wake","阵列尾流速度系数","校准参数","N×M","—","0—1","机组入流","CFD/水池试验","公开基线+企业校准","阵列实测/布置参数","字段冻结","最终不宜用固定常数"],
  ["TC-009","潮流能","biofoulingFactor","f_bio","生物附着降额","时变参数","N×M","—","0—1","设备级","运维研究","必须企业交流","检修前后曲线/清洗记录","字段冻结",""],
  ["AGG-001","互补聚合","sourceCapacity","C_i","逐源装机容量","规划参数","1×S","W","正值","容量层","规划/OEM","公开基线+企业校准","合同容量与台数","字段冻结","风电85%+仅作为容量情景"],
  ["AGG-002","互补聚合","metricWindowsSeconds","τ_l","互补评价窗口","研究参数","1×L","s","正值","指标层","研究设计","公开可获取","按调度/储能时间尺度确认","待敏感性分析","[假设值，待校准]"],
  ["AGG-003","互补聚合","lowOutputFraction","α_low","低出力阈值比例","研究参数","标量","—","0—1","指标层","研究设计","公开可获取","专家确认/敏感性分析","待敏感性分析","不得包装为设备参数"],
  ["AGG-004","互补聚合","firmPowerP05","Q0.05","经验低分位出力","诊断指标","时段/窗口","W","非负","MP-03","统计定义","公开可获取","—","需重命名","不得称容量信用/可靠容量"],
  ["BUS-001","4.4接口","pStorageActual","P_st","储能实际功率","外部输入","N×1","W","正放电、负充电","公共母线","4.5定义","必须企业交流","储能控制与计量","接口冻结",""],
  ["BUS-002","4.4接口","pExport","P_exp","电力外送功率","决策/测量","N×1","W","消耗端取正","MP-07","外送计划/计量","必须企业交流","海缆计量与计划","接口冻结",""],
  ["BUS-003","4.4接口","pElectrolyzer","P_el","制氢用电","决策/测量","N×1","W","消耗端取正","MP-07","设备/计量","必须企业交流","电解槽交流侧测点","接口冻结",""],
  ["BUS-004","4.4接口","pCompute","P_comp","算力设施用电","决策/测量","N×1","W","消耗端取正","MP-07","设施计量","必须企业交流","区分IT功率与设施总功率","接口冻结",""],
  ["BUS-005","4.4接口","pUnservedLoad","P_uns","未供电需求","可靠性量","N×1","W","非负","MP-07","项目定义","公开基线+企业校准","SLA/负荷优先级","接口待校正","不得与servedDemand重复计量"],
  ["BUS-006","4.4接口","pPostPOILoss","P_loss,post","公共母线后损耗","网络输出","N×1","W","非负","MP-06","I²R/潮流模型","必须企业交流","海缆/变压器/变流器参数","接口冻结",""],
];
const s2 = addDataSheet("02_统一变量字典","统一变量字典（4.3—4.4—4.5—EMS）","获取分类是本表的核心：公开资料可定义结构和先验，红色“必须企业交流”项在校准前不得填成真实设备数值。",varHeaders,varRows,[11,18,24,14,24,16,18,11,22,20,30,20,32,16,32]);
s2.getRange("N5:N68").format.fill = C.paleBlue;
addClassFormatting(s2,"L5:L68",[["必须企业交流",C.lightRed],["公开基线+企业校准",C.lightAmber],["公开可获取",C.lightGreen],["项目定义",C.lightBlue]]);

// 03 国产参考设备
const devHeaders = ["设备ID","能源类型","国产参考设备/项目","单位/开发商","公开技术基线","建模用途","公开可获取内容","必须企业交流内容","建议定位","公开来源URL","核验状态"];
const devRows = [
  ["DEV-W-01","漂浮式风电","三峡引领号","三峡集团/三峡能源","5.5MW；三立柱半潜式；含系泊与动态电缆","运行型基准：验证漂浮状态机、平台运动与并网接口","容量、平台构成、项目投运信息","OEM型号全参数、功率曲线、P-Q图、保护阈值、SCADA、平台6DOF与系泊参数","首选运行实证基准","https://www.ctg.com.cn/sxjt/xwzx55/zhxw23/2024081106422712573/index.html","公开来源已核验"],
  ["DEV-W-02","漂浮式风电","明阳OceanX（明阳天成号）","明阳智能/中国船级社","总容量16.6MW；双转子；2×MySE8.3-180；漂浮平台","前沿容量与双机耦合敏感性情景","公开容量、结构形式、船级社审图/检验信息","完整功率曲线、双转子干扰、控制器、P-Q、辅机、系泊及实测运行数据","前沿情景，不替代运行基准","https://www.ccs.org.cn/ccswzen/articleDetail?columnId=201920000000000029&id=202407240311485089","公开来源已核验"],
  ["DEV-PV-01","漂浮式光伏","山东半岛南3号深远海漂浮式光伏实证系统","国家电投山东公司","500kW；2×250kW环形浮体；770块组件；离岸30km、水深30m；接入同场风机平台","风光同场拓扑、平台姿态和公共送出基准","系统容量、浮体数量、组件数量、接入方式、场址概况","组件/逆变器具体型号、I-V/效率矩阵、姿态时序、发电量、故障与损耗","首选系统级实证基准","https://www.chinapower.hk/sc/media/news-p221115a.php","公开来源已核验"],
  ["DEV-PV-02","漂浮式光伏","400kWp半潜式海上漂浮式光伏平台","中集来福士","4个浮体方阵；总装机400kWp；半潜式平台","不同浮体结构与深远海可扩展性对比","容量、平台系统组成、公开尺寸/场址信息","结构RAO、系泊、动态载荷、组件与逆变器型号、运行数据","平台替代情景","https://www.cimc.com/en/index.php?a=show&c=index&catid=17&id=2177&m=content","公开来源已核验"],
  ["DEV-PV-03","漂浮式光伏","Hi-MO 9龙渊/Sea-Shield海光专用组件","隆基绿能","海洋耐腐蚀场景产品；官方披露通过IEC 61701盐雾等级8级测试","组件候选与盐雾/湿热退化参数入口","产品定位、公开耐候说明、后续公开数据表","确切料号、Pmax、温度系数、IEC 61853矩阵、双面率、海上衰减与质保边界","组件候选，需招采前冻结料号","https://www.longi.com/cn/news/hi-mo-9-sea-shield/","公开来源已核验"],
  ["DEV-TC-01","潮流能","LHD第四代1.6MW“奋进号”","浙江LHD联合动能/舟山秀山项目","1.6MW；水平轴；变桨；双向发电；10kV并网公开报道","潮流能主参考设备：涨/落潮曲线、换向状态机和预测接口","额定容量、技术路线、项目连续运行信息","涨/落潮现场功率曲线、额定流速、切入/保护阈值、换向延迟、P-Q图、辅机、尾流和SCADA","首选潮流能运行基准","https://zjic.zj.gov.cn/ywdh/nyhj/202604/t20260415_24035056.shtml","公开来源已核验"],
  ["DEV-TC-02","潮流能","LHD第三代300kW水平轴机组","浙江LHD联合动能","300kW；水平轴；自研换向；双向发电（公开报道）","小容量/分布式阵列敏感性情景","代际与容量公开信息","完整设备曲线与运行数据","备选阵列单元","https://www.minge.gov.cn/n1/2026/0427/c415694-40709750.html","公开来源已核验"]
];
const s3 = addDataSheet("03_国产参考设备","国产参考设备与示范项目基线","“确定参考设备”不等于参数已齐全：公开页面仅冻结设备/项目身份和少量额定信息，工程模型仍需OEM、业主和设计院数据。",devHeaders,devRows,[12,16,31,24,33,28,31,40,24,48,18]);
addClassFormatting(s3,"K5:K11",[["已核验",C.lightGreen],["待核验",C.lightAmber]]);

// 04 同场数据规范
const dataHeaders = ["数据ID","域","变量/数据组","原始建议频率","统一调度频率","空间/垂向要求","时间/坐标要求","公开数据基线","现场/企业数据","获取分类","质量控制","用途","优先级"];
const dataRows = [
  ["D-W-01","风","轮毂高度风速/风向","1s或更高[建议值]","1min、5/15min、1h多尺度","轮毂高度；转子前方或经校正","UTC；ENU/机组轴向","ERA5 10m/100m风场","浮式激光雷达、机舱测风、SCADA","公开基线+企业校准","缺测、密度、剪切、尾流和机舱传递函数","风功率曲线与预测","P0"],
  ["D-W-02","风","气温/气压/湿度","1min[建议值]","5/15min、1h","同场代表位置","UTC","ERA5/NASA POWER","海上气象站","公开基线+企业校准","量程、漂移、空气密度闭合","密度修正","P1"],
  ["D-W-03","风/平台","6DOF姿态、速度、加速度","10Hz或更高[建议值]","1s统计量+5/15min特征","统一平台参考点","UTC；右手系；明确欧拉角顺序","公开仿真基准/OpenFAST","IMU、GNSS、平台控制器","必须企业交流","零偏、漂移、坐标转换、传感器同步","相对风速与动态功率扰动","P0"],
  ["D-O-01","海况","有效波高Hs、峰值周期Tp、平均波向","10min统计/原始高频波面","5/15min、1h","同场浮标；明确水深","UTC；方向约定","ERA5/Copernicus Marine","波浪浮标/雷达","公开基线+企业校准","与风场/姿态同窗；极端值标记","环境停机、平台运动","P0"],
  ["D-PV-01","光","DNI/DHI/GHI","1min[建议值]","5/15min、1h","无遮挡同场辐照站","UTC；太阳位置一致","ERA5/NASA POWER","海上辐照站","公开基线+企业校准","三分量闭合、夜间归零、结露/盐污","POA与PV预测","P0"],
  ["D-PV-02","光/平台","组件roll/pitch/yaw","1—10Hz[建议值]","1s统计量+5/15min特征","每类浮体代表点","UTC；ENU；法向量定义","水动力模型先验","浮体IMU/结构监测","必须企业交流","角度跳变、坐标误差、相位同步","动态POA与失配","P0"],
  ["D-PV-03","光","组件温度、背板温度、海水温度","1min[建议值]","5/15min、1h","代表阵列/不同位置","UTC","ERA5 SST/Copernicus","组件温度传感器、海水温度","必须企业交流","传感器贴附、漂移、遮阴","海上热模型校准","P0"],
  ["D-PV-04","光","盐沉积/污损、清洗与腐蚀状态","事件+日/周巡检","日/周状态量","代表组件与材料试片","统一维护事件时间","公开耐候标准/论文","I-V测试、清洗记录、腐蚀监测","必须企业交流","清洗前后对照、工单一致性","退化与可用率","P1"],
  ["D-TC-01","潮流","有符号流速/流向剖面","1Hz或仪器原始[建议值]","1min、5/15min、1h","ADCP多深度；转子扫掠面","UTC；地理→机组轴向坐标","Copernicus Marine/公开潮汐产品","机位ADCP原始数据","公开基线+企业校准","磁偏角、侧叶、底回波、静水段","涨落潮功率曲线","P0"],
  ["D-TC-02","潮流","湍流强度、剪切、波流夹角","原始高频","10min统计+5/15min","转子扫掠面","UTC；与波浪同窗","公开论文/区域模型","ADCP高频、载荷监测","必须企业交流","有效样本比例与方向扇区","载荷、功率和尾流","P1"],
  ["D-SYS-01","电气","设备端P/Q、电压、电流、频率","100ms—1s[建议值]","1s、5/15min、1h","MP-01与MP-03同时计量","UTC；统一符号","无可替代公开实测","SCADA/电能质量记录","必须企业交流","时钟偏差、CT/PT倍率、坏点","曲线、P-Q、损耗与验证","P0"],
  ["D-SYS-02","控制","requested/accepted/actual、状态与告警","控制器原始周期","1s、5/15min","设备/源级","UTC；统一状态码","无公开替代","EMS/AGC/PLC日志","必须企业交流","请求—反馈时延、状态互斥","闭环模型与约束原因","P0"],
  ["D-SYS-03","损耗","辅机、分支电表、变压器/电缆损耗","1s—1min[建议值]","5/15min、1h","MP-01/02/03/04","UTC；计量边界一致","设计公式与典型值","分项电表、设计参数、试验报告","必须企业交流","能量对账、同期计量、重复扣损检查","冻结损耗模型","P0"],
  ["D-SYS-04","可靠性","故障、检修、复归、MTBF/MTTR","事件级","事件+小时状态","设备级","UTC；事件起止闭合","公开报告仅作先验","CMMS/工单/故障码","必须企业交流","重复工单、计划/非计划区分","可用率和状态机","P1"],
  ["D-QC-01","公共","统一时间主表与质量码","原始分辨率保留","多尺度派生表","同一场址/同一时间窗","UTC；WGS84+ENU；垂向基准","公开数据元数据","现场传感器元数据","公开基线+企业校准","禁止跨缺口插值计算爬坡；记录覆盖率","联合场景与互补性","P0"]
];
const s4 = addDataSheet("04_同场数据规范","同场同步环境与运行数据规范","频率栏为项目建议值，均标注[建议值]；最终采样频率、传感器精度和同步要求须由企业/场址试验方案冻结。公开再分析用于长期先验，不能替代设备校准。",dataHeaders,dataRows,[11,14,28,20,21,29,27,30,31,20,32,25,10]);
addClassFormatting(s4,"J5:J19",[["必须企业交流",C.lightRed],["公开基线+企业校准",C.lightAmber],["公开可获取",C.lightGreen]]);

// 05 证据矩阵
const evHeaders = ["证据ID","模块","公式/参数/设备","当前表达/用途","证据类型","首选公开依据","公开URL","获取分类","公开证据状态","企业校准项","校准状态","可接受替代","正文标注","优先级"];
const evRows = [
  ["E-W-01","风电","实测功率曲线 P=f(v)","设备端可用毛功率","标准+OEM曲线","IEC 61400-12-1:2022","https://webstore.iec.ch/en/publication/68499","公开基线+企业校准","标准元数据已核验；全文待取得","实际型号曲线、空气密度/湍流/控制版本","待企业数据","公开参考机组曲线仅作占位","标准/厂家资料","P0"],
  ["E-W-02","风电","漂浮式耦合与相对风速","考虑纵荡/纵摇引起的入流变化","标准/耦合仿真","GB/Z 44047-2024；GB/T 47558-2026","https://std.samr.gov.cn/gb/search/gbDetailed?id=DB44E046AA194E6FE05397BE0A0A72F4","公开基线+企业校准","适用范围已核验","平台6DOF、控制器、系泊/水动力参数","待企业数据","OpenFAST公开参考模型","[需查证文献支撑]直至取得原文","P0"],
  ["E-W-03","风电","切出/复归状态机","环境超限停机与延时复归","OEM控制规范","GB/Z 44047-2024提供设计边界框架","https://std.samr.gov.cn/gb/search/gbDetailed?id=DB44E046AA194E6FE05397BE0A0A72F4","必须企业交流","公开标准不提供具体阈值","cut-out/restart/delay与台风策略","待企业数据","参数化状态机+敏感性分析","[假设值，待企业调研校准]","P0"],
  ["E-W-04","风电","P-Q能力与爬坡","向EMS提供可行域","并网试验/OEM","公开标准只能提供一般要求","","必须企业交流","缺口明确","P-Q图、AGC响应、动态限值","待企业数据","额定视在功率圆仅作初测","[需企业试验数据]","P0"],
  ["E-W-05","风电","三峡引领号5.5MW","运行型国产基准","业主官网","三峡集团项目页面","https://www.ctg.com.cn/sxjt/xwzx55/zhxw23/2024081106422712573/index.html","公开基线+企业校准","项目身份与容量已核验","OEM型号、曲线、SCADA与平台参数","待企业数据","公开NREL参考机组用于算法测试","政府/企业官网","P0"],
  ["E-W-06","风电","OceanX 16.6MW","前沿情景","船级社/企业官网","中国船级社","https://www.ccs.org.cn/ccswzen/articleDetail?columnId=201920000000000029&id=202407240311485089","公开基线+企业校准","容量和平台身份已核验","双转子耦合、曲线、控制器、运行数据","待企业数据","仅做容量/拓扑敏感性情景","船级社/企业官网","P1"],
  ["E-PV-01","光伏","POA辐照几何","太阳向量·动态法向量","几何定义+论文","IEC 61853-2涉及入射角与温度测量","https://webstore.iec.ch/en/publication/25811","公开基线+企业校准","标准范围已核验","平台姿态与遮挡/反射实测","待企业数据","公开太阳位置算法+现场校准","核心期刊/标准","P0"],
  ["E-PV-02","光伏","辐照-温度功率矩阵","Pdc=f(G,T)","国际标准+OEM","IEC 61853-1","https://webstore.iec.ch/en/publication/6035","公开基线+企业校准","标准范围已核验","实际料号功率矩阵/Flash数据","待企业数据","铭牌gammaP简化模型","标准/厂家资料","P0"],
  ["E-PV-03","光伏","组件温度模型","Tmodule=f(G,Ta,wind)","标准/论文+实测","IEC 61853-2","https://webstore.iec.ch/en/publication/25811","公开基线+企业校准","标准范围已核验","海水冷却条件下U0/U1或等价系数","待同场拟合","Faiman公开先验","[假设值，待企业调研校准]","P0"],
  ["E-PV-04","光伏","盐雾/污损/退化","时变降额因子","试验标准+企业实证","NB/T 11744-2024、NB/T 11814-2025及组件耐候资料","https://std.samr.gov.cn/hb/search/stdHBDetailed?id=2F81627D7762EED8E06397BE0A0A71A7","必须企业交流","公开标准提供要求而非现场降额函数","海上I-V、清洗、腐蚀和衰减记录","待企业数据","区间场景/敏感性","[需查证文献支撑]","P1"],
  ["E-PV-05","光伏","半岛南3号500kW系统","风光同场系统基准","业主/上市公司官网","中国电力国际/国家电投项目新闻","https://www.chinapower.hk/sc/media/news-p221115a.php","公开基线+企业校准","容量、结构和接入已核验","组件/逆变器型号、姿态、功率和故障数据","待企业数据","中集400kWp平台作结构对比","企业官网","P0"],
  ["E-PV-06","光伏","隆基Hi-MO 9龙渊组件","海光组件候选","企业官网/认证","隆基绿能官方产品介绍","https://www.longi.com/cn/news/hi-mo-9-sea-shield/","公开基线+企业校准","海光定位与公开耐候信息已核验","冻结具体料号、数据表、61853矩阵和海上衰减","待选型","同等级海光组件经招标替换","企业官网/认证报告","P1"],
  ["E-TC-01","潮流能","功率曲线评估","P=f(u)","国际/国家标准","IEC TS 62600-200；GB/T 41342-2022","https://std.samr.gov.cn/gb/search/gbDetailed?id=DAB8B40046FB896BE05397BE0A0A0B32","公开基线+企业校准","标准身份与范围已核验","现场涨/落潮功率曲线和不确定度","待企业数据","公开试验曲线仅作占位","国家标准/IEC","P0"],
  ["E-TC-02","潮流能","涨/落潮分曲线与换向","有符号流速、换向死区和延迟","设备控制+现场试验","LHD公开技术路线仅证明双向/变桨","https://zjic.zj.gov.cn/ywdh/nyhj/202604/t20260415_24035056.shtml","必须企业交流","项目能力公开，具体参数缺失","两向曲线、换向逻辑、静水段数据","待企业数据","参数化状态机+敏感性","[假设值，待企业调研校准]","P0"],
  ["E-TC-03","潮流能","尾流/阵列影响","u_eff=u×f_wake","CFD/试验/实测","核心期刊与IEC阵列研究","","公开基线+企业校准","文献检索待深化","阵列布置、ADCP、机组间功率","待检索/企业数据","CFD先验+实测校准","[需查证文献支撑]","P1"],
  ["E-TC-04","潮流能","生物附着降额","f_bio(t)","运维记录+试验","公开论文仅给机制","","必须企业交流","无可直接迁移的设备函数","清洗周期、检修前后曲线","待企业数据","区间假设","[假设值，待企业调研校准]","P2"],
  ["E-TC-05","潮流能","LHD奋进号1.6MW","国产运行基准","政府/权威报道","浙江省经济信息中心","https://zjic.zj.gov.cn/ywdh/nyhj/202604/t20260415_24035056.shtml","公开基线+企业校准","容量、水平轴/变桨/双向和并网信息已核验","设备全参数、SCADA、辅机、P-Q和故障数据","待企业数据","GB/T 41342标准代理曲线","政府官网","P0"],
  ["E-COM-01","公共","集电损耗","P_loss=f(I,R,U,拓扑)","电路守恒+设计模型","工程设计规范/潮流计算","","必须企业交流","公式结构明确，线路参数缺失","电缆R/X、长度、变压器空载/负载损耗、潮流","待企业数据","分段线性损耗+上下界","项目定义/设计院","P0"],
  ["E-COM-02","公共","源侧辅机","运行/待机状态相关负荷","计量+厂用电设计","公开资料仅给设备类别","","必须企业交流","缺少真实数值","分项电表、运行模式和温度相关性","待企业数据","占额定容量比例仅作假设","[假设值，待企业调研校准]","P0"],
  ["E-COM-03","公共","多源聚合守恒","Psrc=ΣPi","项目变量定义/守恒","同一测点定义","","公开可获取","已冻结","测点一致性与计量对账","待现场验证","无","项目定义","P0"],
  ["E-COM-04","公共","联合场景","保留时间持续性和源间相关性","核心期刊方法+同场数据","Copula/分位数/时序场景文献待定向检索","","公开基线+企业校准","方法未最终选定","同场风光流浪历史与预测误差","待数据","历史块重采样基线","[需查证文献支撑]","P1"],
  ["E-COM-05","公共","P05低分位出力","经验低分位诊断","统计定义","统计学定义/互补性文献","","公开可获取","定义可用","时间窗与阈值敏感性","待分析","不得替代ELCC","项目指标/核心期刊","P1"],
  ["E-DATA-01","数据","ERA5小时再分析","风、辐照、温度、波浪长期先验","开放数据","Copernicus Climate Data Store","https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels?tab=download","公开可获取","已核验","用同场观测作偏差订正","待场址","NASA POWER交叉核对辐照","开放科学数据","P0"],
  ["E-DATA-02","数据","Copernicus Marine","海流/波浪/水温长期先验","开放数据","Copernicus Marine Data Store","https://data.marine.copernicus.eu/","公开可获取","已核验","ADCP/浮标偏差订正","待场址","国家/科研海洋数据平台","开放科学数据","P0"],
  ["E-DATA-03","数据","NASA POWER","太阳辐照与气象交叉基线","开放数据","NASA POWER","https://power.larc.nasa.gov/","公开可获取","已核验","海上辐照站校准","待场址","ERA5","政府开放数据","P1"]
];
const s5 = addDataSheet("05_证据矩阵","公式—参数—设备—来源—校准状态证据矩阵","公开标准若只有目录/范围而无全文，只能记为“来源已核验”，不能声称公式已逐条核验；企业校准项未取得前统一标注待企业数据。",evHeaders,evRows,[12,15,29,31,22,31,48,20,25,34,18,28,23,10]);
s5.getRange("K5:K29").format.fill = C.paleBlue;
addClassFormatting(s5,"H5:H29",[["必须企业交流",C.lightRed],["公开基线+企业校准",C.lightAmber],["公开可获取",C.lightGreen]]);
addClassFormatting(s5,"K5:K29",[["已校准",C.lightGreen],["待",C.lightAmber]]);

// 06 企业交流清单
const askHeaders = ["访谈ID","对象","必须获取的数据/文件","为什么公开资料不能替代","最小时间/空间粒度","保密建议","可接受降级替代","对应变量/证据","优先级","状态"];
const askRows = [
  ["ASK-W-01","风机OEM","实际型号功率曲线及不确定度、空气密度/湍流/控制版本说明","公开页面通常只有额定容量，不含完整曲线和适用条件","风速分箱曲线+测试报告","NDA后数据室；可匿名化型号","公开参考机组曲线+区间敏感性","W-005/006,E-W-01","P0","未发起"],
  ["ASK-W-02","风机OEM/业主","P-Q能力图、AGC/AVC响应、爬坡和保护阈值","决定4.3可行域，无法由额定视在功率可靠推得","不同有功/电压工况","可仅提供包络和匿名试验结果","简化圆形边界并明确假设","SRC-011—014,E-W-03/04","P0","未发起"],
  ["ASK-W-03","浮体/系泊设计方","平台6DOF、RAO、系泊刚度、控制器及极端/运行海况边界","浮式耦合与环境停机的核心参数","频域RAO+典型时域工况","可提供降阶模型","OpenFAST公开平台先验","W-003/004,E-W-02","P0","未发起"],
  ["ASK-W-04","风场业主","同场风浪、机组SCADA、状态码、功率、辅机和故障工单","用于校准与独立验证","≥1年，原始1s/10min并保留事件","脱敏、仅输出统计或安全沙箱","公开再分析+合成状态","D-W/D-SYS,E-W-05","P0","未发起"],
  ["ASK-PV-01","漂浮光伏业主/EPC","半岛南3号或同类项目组件、逆变器、浮体和系泊具体型号","公开项目介绍没有设备料号","设备清单/竣工图/单线图","NDA；可隐去价格和供应商","同级公开产品数据表","DEV-PV-01","P0","未发起"],
  ["ASK-PV-02","组件厂家","IEC 61853矩阵、温度系数、IAM、双面率、盐雾/湿热试验及海上衰减","海光产品宣传不能直接变成时变降额函数","批次数据+试验报告","可提供认证摘要和参数区间","公开铭牌+IEC基线","PV-006—009,E-PV-02/04/06","P0","未发起"],
  ["ASK-PV-03","平台/业主","姿态、波浪、辐照、组件温度、DC/AC功率同步数据","海水冷却、动态POA和失配必须同场辨识","1s—1min原始，≥1年/典型季节","可提供代表浮体和匿名时间序列","水动力仿真+公开气象","D-PV,E-PV-01/03/05","P0","未发起"],
  ["ASK-PV-04","逆变器/EPC","效率曲线、削顶、无功能力、保护/复归与辅机","决定AC输出及P-Q边界","负荷率/温度二维曲线","参数包络即可","公开数据表","PV-010/011,SRC-011/012","P1","未发起"],
  ["ASK-TC-01","LHD/潮流能业主","涨潮/落潮功率曲线、额定流速、切入/切出和不确定度","公开报道只有容量与技术路线","按GB/T 41342分箱报告","NDA；可归一化p.u.曲线","IEC/GB测试方法+代理曲线","TC-004/005,E-TC-01/05","P0","未发起"],
  ["ASK-TC-02","LHD/控制器方","换向死区、换向时间、变桨控制、P-Q、爬坡和环境保护","状态机与EMS接口核心","事件日志+控制包络","可匿名化控制参数","参数化状态机敏感性","TC-006/007,E-TC-02","P0","未发起"],
  ["ASK-TC-03","潮流能业主/海洋测量方","机位ADCP剖面、波流、湍流、阵列布置和逐机功率","区域再分析分辨率不足以校准转子入流/尾流","原始ADCP+1min/10min产品","空间坐标可模糊化","Copernicus+公开潮汐模型","D-TC,E-TC-03","P0","未发起"],
  ["ASK-TC-04","潮流能运维方","辅机、故障、检修、生物附着和清洗前后性能","公开论文无法迁移成真实降额函数","事件级+月度性能","脱敏工单/统计分布","区间假设","TC-009,E-TC-04","P1","未发起"],
  ["ASK-E-01","设计院/电气总包","单线图、计量点、电缆R/X/长度、变压器空载/负载损耗和潮流结果","测点与损耗边界必须按工程拓扑确定","设备/分支级","NDA；可只给等值参数","典型参数+上下界","COM-004,SRC-002,BUS-006,E-COM-01","P0","未发起"],
  ["ASK-E-02","业主/SCADA","MP-01/03/04同期P/Q/电压/电流/辅机电量","用于能量对账并发现重复扣损","1s—1min+月度结算表","匿名时间序列/汇总","设计损耗模型","SRC-002/006/007,D-SYS-03","P0","未发起"],
  ["ASK-EMS-01","EMS/调度厂商","requested/accepted/actual协议、刷新周期、时延、质量码和限幅原因","V2字段无法形成真实闭环","控制器原始周期+统一1s","接口文档可脱敏","项目自定义接口","SRC-004—006/010/011","P0","未发起"],
  ["ASK-D-01","业主/场址勘测","同场同步风、光、流、浪、温度和潮位数据及传感器元数据","分别使用不同数据源会破坏源间相关性","至少完整一年；保留高频原始与小时产品","坐标模糊化、时间平移或安全沙箱","ERA5+Copernicus+NASA POWER联合先验","D-QC-01,E-DATA","P0","未发起"]
];
const s6 = addDataSheet("06_企业交流清单","企业交流/数据室取数清单","P0项决定模型能否从“通用代理”升级为“国产设备可落地模型”。如无法提供原始数据，可接受匿名化、归一化曲线、包络或安全沙箱，但必须保留测点和适用条件。",askHeaders,askRows,[12,22,42,38,25,27,30,28,10,14]);
s6.getRange("J5:J20").format.fill = C.paleBlue;
addClassFormatting(s6,"I5:I20",[["P0",C.lightRed],["P1",C.lightAmber],["P2",C.lightGreen]]);

// 07 公开资料清单
const pubHeaders = ["资料ID","类别","标准/项目/数据集","发布机构","可公开获取内容","不能解决的问题","状态（2026-07-15）","URL","建议用途","来源类型"];
const pubRows = [
  ["PUB-W-01","标准","IEC 61400-12-1:2022","IEC","风机功率性能测量方法与不确定度框架","不提供某国产型号真实曲线","现行；含2025勘误","https://webstore.iec.ch/en/publication/68499","风功率曲线证据框架","国际标准"],
  ["PUB-W-02","标准","GB/Z 44047-2024 漂浮式海上风力发电机组设计要求","国家标准委/全国标准信息平台","漂浮式机组工程完整性、场址与设计要求","不提供设备控制阈值/功率曲线","现行，但2026年修订计划已启动","https://std.samr.gov.cn/gb/search/gbDetailed?id=DB44E046AA194E6FE05397BE0A0A72F4","浮式边界与引用清单","政府官网/国家标准"],
  ["PUB-W-03","标准","GB/T 47558-2026 漂浮式海上风力发电机组一体化计算分析导则","国家标准委","耦合模型构建、工况与分析框架","不提供具体项目参数","2026-08-01实施；当前为即将实施","https://std.samr.gov.cn/gb/search/gbDetailed?id=511EBC5968E19318E06397BE0A0AFBD5","V3耦合仿真路线","政府官网/国家标准"],
  ["PUB-W-04","标准","NB/T 11910-2025 漂浮式海上风电场工程可研规程","国家能源局","可研资料与章节要求","不提供设备实测参数","2026-06-18已实施","https://std.samr.gov.cn/hb/search/stdHBDetailed?id=4D49CE8CA21C8559E06397BE0A0AA2EE","工程资料清单","政府官网/行业标准"],
  ["PUB-PV-01","标准","NB/T 11744-2024 海上光伏发电系统设计规范","国家能源局","100kWp及以上海上光伏设计要求","不提供特定平台动态性能","现行","https://std.samr.gov.cn/hb/search/stdHBDetailed?id=2F81627D7762EED8E06397BE0A0A71A7","海光系统边界与设备要求","政府官网/行业标准"],
  ["PUB-PV-02","标准","NB/T 11814-2025 漂浮式光伏支撑系统技术规程","国家能源局","海上/陆上漂浮支撑系统设计、检验与监测要求","不提供特定浮体RAO/运行阈值","现行","https://std.samr.gov.cn/hb/search/stdHBDetailedCNF?id=3B0C26114261E22FE06397BE0A0A3D18","支撑与监测参数清单","政府官网/行业标准"],
  ["PUB-PV-03","标准","NB/T 11352-2023 漂浮式光伏发电站运行维护规程","国家能源局","运行控制、巡检、维护、异常与故障要求","不提供海上退化曲线","现行","https://std.samr.gov.cn/hb/search/stdHBDetailed?id=2E1288291A780971E06397BE0A0ABFD2","状态机与运维字段","政府官网/行业标准"],
  ["PUB-PV-04","标准","IEC 61853-1/-2/-3","IEC","PV辐照/温度功率矩阵、入射角、温度与能量评级方法","不提供选定组件实测矩阵","现行系列","https://webstore.iec.ch/en/publication/6035","PV性能模型证据","国际标准"],
  ["PUB-TC-01","标准","GB/T 41342-2022 潮流能发电装置功率特性现场测试方法","国家标准委/自然资源部","现场功率曲线测试方法","不提供LHD真实曲线","现行","https://std.samr.gov.cn/gb/search/gbDetailed?id=DAB8B40046FB896BE05397BE0A0A0B32","涨/落潮功率曲线框架","政府官网/国家标准"],
  ["PUB-TC-02","标准","IEC TS 62600-200:2013","IEC","潮流能转换装置额定功率、额定流速和功率曲线评估方法","不提供特定设备参数","稳定日期至2026，后续版本需跟踪","https://webstore.iec.ch/en/publication/7242","潮流设备性能证据","国际标准"],
  ["PUB-DEV-01","项目","三峡引领号","中国三峡集团","5.5MW、半潜平台、系泊和动态电缆构成","不含OEM曲线/控制/SCADA","公开项目页面","https://www.ctg.com.cn/sxjt/xwzx55/zhxw23/2024081106422712573/index.html","运行型风电参考设备","央企官网"],
  ["PUB-DEV-02","项目","OceanX 16.6MW","中国船级社","平台身份、容量和检验信息","不含完整设备模型","公开项目页面","https://www.ccs.org.cn/ccswzen/articleDetail?columnId=201920000000000029&id=202407240311485089","前沿风电情景","行业机构/企业官网"],
  ["PUB-DEV-03","项目","半岛南3号500kW漂浮式光伏","中国电力国际/国家电投","500kW、两浮体、770组件、离岸/水深和接入方式","不含组件料号及运行数据","公开项目页面","https://www.chinapower.hk/sc/media/news-p221115a.php","风光同场系统基准","上市公司/央企官网"],
  ["PUB-DEV-04","项目","中集400kWp半潜式漂浮光伏平台","中集集团","容量、浮体数量与平台定位","不含RAO/系泊/运行数据","公开项目页面","https://www.cimc.com/en/index.php?a=show&c=index&catid=17&id=2177&m=content","漂浮平台对比","上市公司官网"],
  ["PUB-DEV-05","设备","隆基Hi-MO 9龙渊海光专用组件","隆基绿能","海光耐腐蚀产品定位与公开测试说明","不等于冻结料号和完整性能矩阵","公开产品介绍","https://www.longi.com/cn/news/hi-mo-9-sea-shield/","海光组件候选","上市公司/企业官网"],
  ["PUB-DEV-06","项目","LHD奋进号1.6MW","浙江省经济信息中心/项目方","容量、水平轴、变桨、双向与并网公开信息","不含功率曲线/阈值/SCADA","政府公开报道","https://zjic.zj.gov.cn/ywdh/nyhj/202604/t20260415_24035056.shtml","潮流能运行基准","政府官网"],
  ["PUB-DATA-01","开放数据","ERA5小时单层再分析","Copernicus/ECMWF","风、气温、气压、辐射、波浪等长期小时序列","分辨率不足以替代场址测量","持续更新","https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels?tab=download","长期资源先验/联合场景","国际开放科学数据"],
  ["PUB-DATA-02","开放数据","Copernicus Marine Data Store","Copernicus Marine","海流、波浪、水温和海洋物理产品","近岸/机位误差需ADCP/浮标校准","持续更新","https://data.marine.copernicus.eu/","潮流/波浪长期先验","国际开放科学数据"],
  ["PUB-DATA-03","开放数据","NASA POWER","NASA","太阳辐照与气象数据、参数字典和API","海上局地效应仍需实测校准","持续更新","https://power.larc.nasa.gov/","辐照交叉基线","政府开放数据"],
  ["PUB-DATA-04","开放数据","青岛海洋科学资料共享服务中心","自然资源部第一海洋研究所等","海洋科学元数据与部分观测/共享数据","具体场址和高频数据可用性不保证","在线服务","https://www.nsfcodc.cn/","国内海洋数据补充检索","科研数据平台"]
];
const s7 = addDataSheet("07_公开资料清单","公开资料与标准清单","每条URL均用于证明“来源存在、标准/项目范围或公开设备事实”；若未取得标准全文，不得把目录页当作公式原文。",pubHeaders,pubRows,[12,15,35,25,37,35,26,52,28,22]);
addClassFormatting(s7,"G5:G24",[["现行",C.lightGreen],["已实施",C.lightGreen],["即将实施",C.lightAmber],["修订",C.lightAmber]]);

// Format all sheets and export
for (const sh of wb.worksheets.items) {
  const used = sh.getUsedRange();
  if (used) used.format.verticalAlignment = "top";
}

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

// Compact verification before export
const summaryInspect = await wb.inspect({ kind: "table", range: "00_使用说明!A1:H19", include: "values,formulas", tableMaxRows: 25, tableMaxCols: 10 });
console.log(summaryInspect.ndjson);
const errorScan = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "formula error scan" });
console.log(errorScan.ndjson);

const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(outputPath);
console.log(JSON.stringify({ outputPath, previewDir, sheets: wb.worksheets.items.map(s => s.name) }));
