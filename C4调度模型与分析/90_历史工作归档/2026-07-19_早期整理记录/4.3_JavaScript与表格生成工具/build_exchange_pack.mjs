import fs from "node:fs/promises";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const outDir = "C:/Users/llcqc/Desktop/多源能源/outputs/4_3_enterprise_exchange_pack";
await fs.mkdir(`${outDir}/previews`, { recursive: true });

const wb = Workbook.create();
const navy = "#17365D";
const blue = "#1F4E78";
const teal = "#0F6B78";
const paleBlue = "#DDEBF7";
const paleTeal = "#DDEBF7";
const paleGold = "#FFF2CC";
const paleGreen = "#E2F0D9";
const paleRed = "#FCE4D6";
const paleGray = "#F2F2F2";
const white = "#FFFFFF";
const border = { preset: "all", style: "thin", color: "#B4C6E7" };

function title(sheet, range, text) {
  const r = sheet.getRange(range); r.merge(); r.values = [[text]];
  r.format = { fill: navy, font: { bold: true, color: white, size: 16 }, verticalAlignment: "center" };
  r.format.rowHeight = 30;
}
function note(sheet, range, text) {
  const r = sheet.getRange(range); r.merge(); r.values = [[text]];
  r.format = { fill: "#EAF2F8", font: { italic: true, color: "#404040" }, wrapText: true, verticalAlignment: "center" };
  r.format.rowHeight = 38;
}
function header(range, fill = blue) {
  range.format = { fill, font: { bold: true, color: white }, wrapText: true, verticalAlignment: "center", horizontalAlignment: "center", borders: border };
  range.format.rowHeight = 30;
}
function body(range) {
  range.format = { wrapText: true, verticalAlignment: "top", borders: border, font: { name: "Microsoft YaHei", size: 10 } };
}
function styleQuestionSheet(sheet, rows, companyNote) {
  sheet.showGridLines = false;
  title(sheet, "A1:J1", `${companyNote}｜4.3多能源供给建模定向交流清单`);
  note(sheet, "A2:J2", "交流原则：P0优先现场确认；问题不要求企业必须交付原始敏感数据，可接受匿名化时间序列、分箱曲线、能力包络、参数区间或安全沙箱验证。公开已知内容不重复询问。 ");
  sheet.getRange("A4:J4").values = [["问题ID","主题","定向问题","期望回答/交付物","对应4.3变量或证据","最低可接受替代","建议回答部门","优先级","会后责任/时限","状态"]];
  header(sheet.getRange("A4:J4"));
  sheet.getRange(`A5:J${4 + rows.length}`).values = rows;
  body(sheet.getRange(`A5:J${4 + rows.length}`));
  for (let r = 5; r <= 4 + rows.length; r++) {
    sheet.getRange(`A${r}:J${r}`).format.fill = r % 2 ? "#F7FBFD" : paleBlue;
    sheet.getRange(`H${r}`).format.fill = sheet.getRange(`H${r}`).values[0][0] === "P0" ? paleGold : paleGreen;
  }
  sheet.getRange(`A5:J${4 + rows.length}`).format.rowHeight = 60;
  const widths = [14,16,48,38,28,34,22,10,20,12];
  widths.forEach((w,i)=>sheet.getRangeByIndexes(0,i,4+rows.length,1).format.columnWidth=w);
  sheet.getRange(`H5:H${4+rows.length}`).dataValidation = { rule: { type: "list", values: ["P0","P1","P2"] } };
  sheet.getRange(`J5:J${4+rows.length}`).dataValidation = { rule: { type: "list", values: ["未询问","已确认","待提供","不可提供","用替代数据"] } };
  sheet.freezePanes.freezeRows(4);
}

const shenzhenRows = [
  ["SZ-P0-01","交流边界","本次可讨论哪些新能源项目、设备型号和运行阶段？哪些数据由集团、项目公司、运维单位、设计院或OEM分别持有？","项目—设备—数据所有者—授权人的对应表","sourceId、assetConfigId、parameterSetId","只确认可讨论范围和责任单位，不要求披露项目名称","新能源管理/项目公司/科技管理","P0","会后2个工作日确认联系人","未询问"],
  ["SZ-P0-02","保密与交付","原始SCADA、设备参数、故障记录分别适用何种保密等级？能否采用NDA、匿名化、时间平移、归一化或安全沙箱？","数据交付等级、审批路径和预计时间","全部企业校准证据","仅提供曲线、包络、统计分布或验证KPI","法务/数据平台主管/项目公司","P0","会后形成数据交付矩阵","未询问"],
  ["SZ-P0-03","测点与单线图","请确认设备交流端、源内集电网、source_collection_bus、源侧辅机及公共母线的实际测点和单线图边界。","脱敏单线图、测点表、CT/PT/电表信息","meterPoint、pCollectionLoss、pSourceAux","只提供测点编号、上下游关系和损耗归属","电气设计/生产技术/计量","P0","会后1周提供边界表","未询问"],
  ["SZ-P0-04","SCADA字段","能否提供一份脱敏SCADA通道样例及字段字典，包括时间、P/Q/V/I/f、状态码、告警、限发和质量码？","字段字典+短周期样例数据","pActualAtPOI、qActual、operatingState、qualityFlag","仅提供字段名、单位、采样周期和状态码映射","集控中心/数字化/运维","P0","会后3个工作日确认字段","未询问"],
  ["SZ-P0-05","同场环境数据","项目是否具备同场风、浪、流、温度、气压和平台姿态数据？测点位置、采样周期、时间同步和有效期如何？","环境测点元数据+可用时间段","windSpeed、wave、current、platformMotion","提供已聚合的10min/小时序列或统计分布","项目公司/海洋监测/运维","P0","确认可提供变量和年份","未询问"],
  ["SZ-P0-06","功率与损耗闭合","设备端毛功率、汇集点净功率、源内集电损耗和辅机耗电能否在相同时间轴闭合？现有计量误差多大？","至少一周同步P/Q/辅机数据+损耗核对规则","pAvailableGross、pCollectionLoss、pAvailableAtPOI、pSourceAux","提供负载—损耗分段曲线和月度损耗率","计量/电气/生产运行","P0","会后提供闭合样例","未询问"],
  ["SZ-P0-07","调度链路","EMS/AGC指令中requested、设备accepted和实际actual能否区分？刷新周期、延迟、质量码和拒绝原因是什么？","三联量同步样例+接口说明","pRequested、pAccepted、pActualAtPOI、constraintCode","只提供接口时序、延迟分布和接受率","调度/集控/EMS厂商","P0","会后形成接口时序图","未询问"],
  ["SZ-P0-08","事件标签","如何区分资源不足、主动限发、电网限送、设备故障、检修、环境保护、通信丢失和降额？","统一事件分类、状态码交叉表和起止规则","operatingState、constraintCode、availabilityFactor","匿名事件清单或各类持续时间分布","生产运行/运维/数字化","P0","会议现场冻结分类框架","未询问"],
  ["SZ-P0-09","预测数据","是否保留日前、日内、超短期风功率及资源预测的发布时间、版本、预测值和实测值？","生产预测档案和误差评估口径","pForecastAvailable、scenarioAvailable、forecastError","分预测时域的误差分布和分位数","调度/预测服务商/数字化","P0","会后确认可用年份与粒度","未询问"],
  ["SZ-P0-10","并网能力","项目P-Q运行包络、AGC/AVC性能、爬坡限制、短路比、故障穿越及保护整定如何确定？","验收报告或脱敏能力包络","qMin/qMax、pUp/pDownCapability、rampLimit","提供通过/失败结论及关键边界区间","生产技术/电气/并网调度","P0","会后提供能力边界","未询问"],
  ["SZ-P0-11","台风与恢复","能否选取一次典型台风或极端海况，说明预警、降额、停机、复归、恢复和人工干预全过程？","完整事件时间轴+状态/功率/天气","extremeEventId、operatingState、recoveryTime","提供匿名化事件序列和恢复阶段持续时间","安监/运维/项目公司","P0","会后确认一个案例","未询问"],
  ["SZ-P0-12","故障与运维","可否按部件或故障模式提供故障率、降额率、MTTR、天气等待、备件及船舶动员时间？","故障模式统计与维修链条","availabilityState、availabilityFactor、MTTR","只提供分布区间和主要故障排序","运维/保险/供应链","P0","会后1周提供统计口径","未询问"],
  ["SZ-P0-13","独立验证","企业通常用哪些KPI验收功率模型、预测模型和控制响应？能否划定独立验证时段？","RMSE/MAE/bias/coverage等阈值及验证数据窗","validationSet、modelKPI","在企业侧运行模型，只返回KPI","科技管理/数字化/第三方检测","P0","会议现场确认验证方式","未询问"],
  ["SZ-P1-01","数据质量","计量精度、校准周期、时钟同步、缺失插补、漂移和质量码规则是什么？","校准证书摘要和质量控制规则","uMeasurement、qualityFlag","提供精度等级、有效期和缺失比例","计量/数据平台主管","P1","会后补充元数据","未询问"],
  ["SZ-P1-02","源储接口","源侧向构网型储能提供哪些实时量和备用需求？SOC安全边界、黑启动预留和新能源降额如何协同？","源—储接口及备用判据","pUp/pDownCapability、reserveRequirement","提供现行控制逻辑流程图","调度/储能平台主管/EMS","P1","转交4.5建模负责人","未询问"],
  ["SZ-P1-03","单一外送基准","企业如何定义单一外送模式的装机、送出限额、弃电和损耗口径？","与协同方案同边界的基准场景","baselineId、exportLimit、curtailment","确认基准定义，不要求提供财务数据","规划/投资/生产技术","P1","会议现场冻结口径","未询问"],
  ["SZ-P1-04","光伏适用性","若集团拥有海上/漂浮式光伏实证，能否提供组件、逆变器、浮体姿态、组串拓扑、故障和海洋环境数据？","确认是否存在适用项目及数据责任方","PV相关变量和证据","仅提供项目联系人或可用公开材料","新能源管理/光伏项目公司","P1","若无则转向其他业主","未询问"],
  ["SZ-P1-05","潮流能适用性","集团是否参与潮流能、海洋能或海上综合能源示范？若无，能否推荐设备/项目合作方？","确认数据可得性或推荐联系人","TC相关变量和证据","只确认无数据并推荐外部主体","科技管理/海洋能源团队","P1","若无则对接LHD/舟山项目方","未询问"],
  ["SZ-P1-06","联合研究方式","企业更接受提供数据、联合建模、企业侧验证还是只提供专家判断？","后续协作方式和技术接口人","evidenceStatus、calibrationStatus","一次技术复核会+匿名参数区间","科技管理/项目公司/法务","P1","形成下一步工作单","未询问"]
];

const mingyangRows = [
  ["MY-P0-01","型号冻结","本项目应选用MySE5.5-155、MySE7.25-158、OceanX/MySE16.6(T)中的哪一型作为运行基准和前沿情景？当前有效控制/参数版本是什么？","推荐型号、适用场景和parameterSetId","sourceId、parameterSetId、rated parameters","只确认推荐基准及版本生效时间","浮式产品/系统工程/研发","P0","会议现场冻结基准","未询问"],
  ["MY-P0-02","功率曲线","能否提供选定型号的完整交流端功率曲线及空气密度、湍流、偏航、海况和控制版本条件？","风速分箱功率曲线+不确定度","pAvailableGross、powerCurve","匿名化或归一化功率曲线及适用范围","气动/控制/测试认证","P0","会后1周提供曲线或包络","未询问"],
  ["MY-P0-03","低风与额定区","切入、并网、最低稳定运行、额定功率控制、桨距调节及停机判据如何转换？","运行状态机和关键阈值","operatingState、cutIn、rated control","只给状态转移图和阈值区间","控制系统/整机研发","P0","会议现场确认状态机","未询问"],
  ["MY-P0-04","台风策略","高风速、台风、极端浪况下如何执行降额、停机、顺桨、偏航、锁定和复归？是否存在分阶段策略？","台风控制状态机、延时与复归条件","derateFactor、extremeEventState、recoveryTime","提供匿名策略流程和边界区间","控制/载荷/安全设计","P0","会后提供流程摘要","未询问"],
  ["MY-P0-05","双转子计量","OceanX两个转子/发电链是否分别计量P/Q、状态、故障和辅机？平台总功率如何聚合并扣除损耗？","双转子—平台—汇集点测点图","pRotor1/2、pAvailableGross、pCollectionLoss","只提供测点层级和聚合公式结构","OceanX总体/电气/控制","P0","会议现场画出测点关系","未询问"],
  ["MY-P0-06","双转子耦合","双转子尾流、V形塔架遮挡、自动顺风偏航、平台运动及单点系泊如何影响有效入流和功率？","可用于调度模型的降阶修正关系","effectiveWind、interactionFactor、yawFactor","提供查表维度、修正系数区间或代理模型输入输出","气动/水动/控制/OceanX团队","P0","会后确认降阶接口","未询问"],
  ["MY-P0-07","单转子故障","OceanX单侧机组、变流器或传感器故障时，是否允许另一侧继续运行？降额、偏航和平台载荷约束是什么？","故障降额状态机和可用容量比例","availabilityFactor、operatingState","提供故障模式—可用比例矩阵","OceanX控制/可靠性","P0","会后提供匿名矩阵","未询问"],
  ["MY-P0-08","平台运动","能否提供6DOF、RAO、系泊刚度及相对风速修正的降阶模型？调度尺度需要保留哪些姿态特征？","RAO/典型海况响应或已验证代理模型","surge/pitch/yaw、relativeWind","只提供典型海况响应包络和关键输入输出","浮体/系泊/水动力团队","P0","会后确认可交付层级","未询问"],
  ["MY-P0-09","P-Q能力","选定型号在不同有功、电压和温度工况下的P-Q包络是什么？是否包含动态海缆和平台变压器限制？","设备端及平台端P-Q能力图","qMin/qMax、apparentPowerLimit","匿名化能力包络或典型工况边界","变流器/电气/并网","P0","会后提供包络","未询问"],
  ["MY-P0-10","爬坡与调度响应","AGC/AVC、功率限幅、上/下调能力、刷新周期、延迟、死区和跟踪误差是多少？","request—accepted—actual响应试验","pUp/pDownCapability、ramp、latency","提供归一化阶跃响应和误差统计","控制/SCADA/并网","P0","会后提供试验摘要","未询问"],
  ["MY-P0-11","保护与故障穿越","低/高电压穿越、频率保护、短路比适应、保护整定及故障后恢复逻辑是什么？","保护包络和通过/失败试验结论","protectionState、v/f envelope","不披露整定值，仅给边界区间和结论","电气/并网认证","P0","会后确认可公开范围","未询问"],
  ["MY-P0-12","辅机耗电","液压、润滑、冷却、偏航、泵、控制、平台公共辅机在运行/待机/停机/台风模式下耗电如何变化？","状态—辅机功率矩阵","pSourceAux","提供归一化辅机率和状态排序","电气/控制/运维","P0","会后提供区间","未询问"],
  ["MY-P0-13","状态码与版本","能否提供控制器状态、告警、降额、限发和故障码到统一状态机的映射，以及版本变更生效时间？","状态码交叉表+版本历史","operatingState、constraintCode、parameterSetId","只提供一级分类和版本日期","SCADA/控制软件/运维","P0","会后3个工作日确认映射","未询问"],
  ["MY-P0-14","验证方法","功率曲线、平台耦合、P-Q和台风控制分别采用哪些试验/仿真验证KPI？能否由企业侧运行我们的模型？","验收KPI和企业侧验证流程","RMSE、bias、coverage、passRate","模型不出企业环境，只返回KPI与修改意见","测试认证/研发/数字化","P0","会议现场确定验证方式","未询问"],
  ["MY-P0-15","数据交付","原始数据无法提供时，企业可接受匿名时序、分箱曲线、能力包络、参数区间或安全沙箱中的哪种方式？","交付等级、审批人和预计时间","evidenceStatus、calibrationStatus","专家复核签字+区间参数","项目管理/法务/数据平台主管","P0","形成数据责任矩阵","未询问"],
  ["MY-P1-01","尾流与阵列","多机阵列坐标、偏航/尾流控制和阵列损失是否有可供调度模型使用的降阶方法？","风向风速分箱损失矩阵或代理模型","wakeFactor、layoutId","开源尾流模型由明阳确认适用区间","风场设计/控制/数字化","P1","会后确认方法","未询问"],
  ["MY-P1-02","预测接口","机组/场站是否输出可用功率预测、置信区间和上/下调能力？OEM与业主预测边界如何划分？","预测与能力接口定义","pForecastAvailable、scenarioAvailable","只提供接口字段和刷新周期","数字化平台/控制/场站设计","P1","转交EMS集成负责人","未询问"],
  ["MY-P1-03","可靠性","可否按主要子系统提供可用率、降额率、MTBF/MTTR和台风后的检查恢复时间？","故障模式统计和恢复链","availabilityState、availabilityFactor、MTTR","只提供排序、区间和典型恢复过程","可靠性/运维/售后","P1","会后提供匿名统计","未询问"],
  ["MY-P1-04","源储接口","明阳风机、储能和EMS在构网/弱网场景中如何分工？风机侧可以提供哪些快速有功、无功和降载能力？","风—储控制接口和时间尺度分工","pUp/pDown、qCapability、reserve","提供功能清单和接口时序","储能/EMS/并网控制","P1","转交4.5建模负责人","未询问"],
  ["MY-P1-05","光储氢扩展","明阳光伏、储能、氢能和数字化平台中哪些设备/接口可作为蓝海枢纽参考？是否存在可共享的多能协同示范数据？","可适用产品、示范场景和后续联系人","跨模块接口参数","仅提供产品资料和责任部门","综合能源/光伏/储能/氢能","P1","建立后续专题交流","未询问"],
  ["MY-P1-06","模型审查","能否由整机、浮体、电气、控制专家对4.3风电子模型的输入、状态机、输出接口和假设逐项审查？","专家审查意见和需修改项","公式—参数—设备—来源状态","一次技术评审会，不要求数据交付","研发/产品/科技管理","P1","交流后安排技术复核","未询问"]
];

const s1 = wb.worksheets.add("01_深圳能源定向清单");
styleQuestionSheet(s1, shenzhenRows, "深圳能源集团");
const s2 = wb.worksheets.add("02_明阳风电定向清单");
styleQuestionSheet(s2, mingyangRows, "明阳风电");

const knownRows = [
  ["PUB-W-01","明阳浮式风机","MySE5.5-155额定功率5.5MW、叶轮直径155m、额定风速10m/s、湍流强度0.14、公开生存风速70.1m/s","企业官网","https://en.myse.com.cn/wind-turbine/index.aspx","运行型基准候选","不要重复询问额定容量、叶轮直径等公开参数","仍需完整功率曲线、控制版本和实测适用条件"],
  ["PUB-W-02","明阳浮式风机","MySE7.25-158额定功率7.25MW、叶轮直径158m、额定风速10m/s、湍流强度0.14、公开生存风速84m/s","企业官网","https://en.myse.com.cn/wind-turbine/index.aspx","深水浮式备选基准","不要重复询问上述额定参数","仍需设备曲线、状态机、P-Q和平台响应"],
  ["PUB-W-03","OceanX","OceanX/MySE16.6(T)公开额定功率16.6MW、叶轮直径182m、额定风速10m/s、湍流强度0.135、参数页生存风速72.24m/s","企业官网","https://en.myse.com.cn/wind-turbine/index.aspx","双转子前沿情景","不要重复询问公开额定参数","需确认双转子测点、耦合、控制和参数版本"],
  ["PUB-W-04","OceanX结构","公开采用双转子、V形塔架、混凝土浮体、单点系泊和自动顺风偏航","企业官网","https://en.myse.com.cn/wind-turbine/index.aspx","确定模型需增加双转子/平台聚合层","不要询问是否采用这些结构","需询问结构如何影响功率、状态和降额"],
  ["PUB-W-05","三峡引领号","公开为明阳5.5MW抗台风漂浮式风机，可作为国产运行实证基准","企业官网/业主官网","https://www.ctg.com.cn/sxjt/xwzx55/zhxw23/2024081106422712573/index.html","验证浮式状态机和平台接口","不要再问项目是否存在及额定容量","需项目级SCADA、平台和控制数据"],
  ["PUB-SZ-01","深圳能源研发方向","深圳能源公开披露风—光—氢—储综合能源系统高效耦合、规模化电解海水制氢、储能监控与新能源智慧运营研发","上市公司年度报告","https://oss.sec.com.cn/202504181512094591.pdf","说明交流可延伸至源储接口和EMS","不要泛问是否关注风光氢储或海水制氢","应问具体示范、数据接口和工程约束"],
  ["PUB-PV-01","海上漂浮光伏基准","山东半岛南3号实证系统公开容量500kW、2×250kW环形浮体、770块组件并接入同场风机平台","上市公司/项目官网","https://www.chinapower.hk/sc/media/news-p221115a.php","作为4.3漂浮光伏系统级公开基准","不要向深圳能源或明阳询问该项目公开容量","仍需向项目业主询问设备型号、姿态、功率和损耗"],
  ["PUB-TC-01","潮流能基准","LHD第四代奋进号公开容量1.6MW、水平轴、变桨、双向发电和10kV并网","政府/项目公开资料","https://zjic.zj.gov.cn/ywdh/nyhj/202604/t20260415_24035056.shtml","作为潮流能主参考设备","不要向非数据所有者询问公开额定容量","应向LHD/舟山项目方询问涨落潮曲线和状态机"],
  ["PUB-STD-01","风机功率曲线标准","IEC 61400-12-1:2022规定风电机组功率性能测量框架","国际标准","https://webstore.iec.ch/en/publication/68499","定义功率曲线数据元和不确定度要求","不要询问企业是否知道该标准","应确认企业试验是否按该标准及偏离项"],
  ["PUB-STD-02","浮式设计边界","GB/Z 44047-2024提供漂浮式海上风电场设计要求框架","国家标准","https://std.samr.gov.cn/gb/search/gbDetailed?id=DB44E046AA194E6FE05397BE0A0A72F4","用于场址、结构、控制和保护边界","不要询问标准的一般性要求","应询问具体项目设计阈值和试验结果"],
  ["PUB-DATA-01","公开环境数据","ERA5、Copernicus Marine、NASA POWER可作为长期风、浪、流、温度和辐照先验","开放科学数据","https://cds.climate.copernicus.eu/","在企业数据到位前构建同场公共基线","不要要求企业提供可公开下载的长期再分析数据","应询问现场测点和再分析偏差校准"],
  ["PUB-BND-01","模型测点边界","4.3统一输出测点已冻结为source_collection_bus；源内集电损耗由4.3扣除，pSourceAux在4.4单列","项目内部冻结规则","项目数据冻结与证据矩阵","避免重复扣损和章节重叠","不要重新讨论是否将辅机重复扣除","只需请企业确认该边界能否映射到实际计量点"]
];
const s3 = wb.worksheets.add("03_公开已知_无需再问");
s3.showGridLines = false;
title(s3, "A1:H1", "公开已知—无需再问清单");
note(s3, "A2:H2", "用途：把会议时间留给非公开参数、运行边界和数据可得性。公开信息仍需确认是否适用于本次选定设备/项目，但不应从企业介绍性问题重新开始。 ");
s3.getRange("A4:H4").values = [["已知ID","对象","公开已知事实","来源类型","公开来源URL","建模用途","会议中无需再问","仍需企业确认"]];
header(s3.getRange("A4:H4"), teal);
s3.getRange(`A5:H${4+knownRows.length}`).values = knownRows;
body(s3.getRange(`A5:H${4+knownRows.length}`));
for (let r=5;r<=4+knownRows.length;r++) s3.getRange(`A${r}:H${r}`).format.fill = r%2?paleGreen:"#F7FBFD";
s3.getRange(`A5:H${4+knownRows.length}`).format.rowHeight=62;
[14,18,50,18,44,28,38,38].forEach((w,i)=>s3.getRangeByIndexes(0,i,4+knownRows.length,1).format.columnWidth=w);
s3.freezePanes.freezeRows(4);

// 一页4.3模型接口图。
const s4 = wb.worksheets.add("04_4.3模型接口图");
s4.showGridLines = false;
title(s4, "A1:P1", "4.3 多能源供给模型接口图（会议版）");
note(s4, "A2:P2", "边界原则：4.3生成各类电源在source_collection_bus处的可用功率、无功与调节能力；不负责储能平抑和价值端口分配。pSourceAux在4.4作为负荷单列，避免重复扣除。 ");

function block(range, text, fill, fontColor="#17365D") {
  const r=s4.getRange(range); r.merge(); r.values=[[text]];
  r.format={fill,font:{bold:true,color:fontColor,size:11},wrapText:true,verticalAlignment:"center",horizontalAlignment:"center",borders:{preset:"outside",style:"medium",color:"#5B9BD5"}};
}
block("A4:D7","输入层 A｜同场环境与海况\n风速/风向、辐照/温度、潮流剖面\n波高/周期、空气密度、平台6DOF\ntime + qualityFlag","#E2F0D9");
block("E4:H7","输入层 B｜设备与参数版本\n型号、功率/效率曲线、平台/系泊\n阵列布局、电气拓扑、P-Q包络\nassetConfigId + parameterSetId","#DDEBF7");
block("I4:L7","输入层 C｜运行状态与事件\n可用/降额、故障/检修、台风策略\n事件标签、控制版本、恢复过程\navailability + operatingState","#FFF2CC");
block("M4:P7","输入层 D｜预测与EMS指令\n日前/日内/超短期预测及场景\nrequested / accepted / actual\nforecastError + scenarioProbability","#FCE4D6");

block("A10:E14","漂浮式风电子模型\n有效入流→功率曲线\n平台运动/双转子/尾流修正\n切入—额定—降额—停机—复归","#D9EAF7");
block("F10:K14","漂浮式光伏子模型\n动态POA辐照→组件温度→DC功率\n姿态/遮挡/失配/盐雾污损修正\n逆变器与组串状态","#E2F0D9");
block("L10:P14","潮流能子模型\n有符号流速剖面→涨/落潮功率曲线\n换向/死区/尾流/阻塞修正\n切入—额定—保护—复归","#DDEBF7");

block("A17:P20","统一适配层｜单机/组件/装置 → 阵列 → 设备交流端MP-01 → 源内集电MP-02 → source_collection_bus MP-03\n统一处理：状态与降额、阵列/拓扑损失、计量不确定度、质量码、预测误差和多场景相关性\n冻结关系：pAvailableAtPOI = pAvailableGross − pCollectionLoss；pSourceAux不在此重复扣除","#EAF2F8");

block("A23:P27","4.3标准输出接口\npAvailableGross ｜ pCollectionLoss ｜ pAvailableAtPOI ｜ pForecastAvailable ｜ scenarioAvailable/Probability\nqMinAtPOI / qMaxAtPOI ｜ pUpCapability / pDownCapability ｜ rampLimit\noperatingState ｜ constraintCode ｜ qualityFlag ｜ parameterSetId","#17365D","#FFFFFF");

block("A30:E34","→ 4.4 多端口耦合与功率平衡\n源侧注入 + 辅机 + 损耗账本\n校验balanceMismatch≈0","#DDEBF7");
block("F30:K34","→ 4.5 构网型混合储能中枢\n接收可用功率、P-Q、爬坡和备用\n输出平抑/调频/调压/黑启动能力","#E2F0D9");
block("L30:P34","→ 4.8—4.9 多目标优化与调度\n调用预测场景、物理可行域和状态\n进行经济/环保/可靠性Pareto优化","#FFF2CC");

for (const rr of ["A8:P8","A15:P15","A21:P21","A28:P28"]) {
  const r=s4.getRange(rr); r.merge(); r.values=[["▼"]];
  r.format={font:{bold:true,color:blue,size:18},horizontalAlignment:"center",verticalAlignment:"center"};
  r.format.rowHeight=22;
}
for(let c=0;c<16;c++) s4.getRangeByIndexes(0,c,34,1).format.columnWidth=10;
for (const row of [4,5,6,7,10,11,12,13,14,17,18,19,20,23,24,25,26,27,30,31,32,33,34]) s4.getRange(`${row}:${row}`).format.rowHeight=24;
s4.getRange("A1:P34").format.font={name:"Microsoft YaHei",size:10};

const xlsxPath = `${outDir}/4.3企业交流会前工作包.xlsx`;
const out = await SpreadsheetFile.exportXlsx(wb);
await out.save(xlsxPath);

for (const name of ["01_深圳能源定向清单","02_明阳风电定向清单","03_公开已知_无需再问","04_4.3模型接口图"]) {
  const png = await wb.render({ sheetName:name, autoCrop:"all", scale:name.startsWith("04_")?1.2:0.75, format:"png" });
  const path = name.startsWith("04_") ? `${outDir}/4.3模型接口图.png` : `${outDir}/previews/${name}.png`;
  await fs.writeFile(path,new Uint8Array(await png.arrayBuffer()));
}

console.log((await wb.inspect({kind:"sheet",include:"id,name",maxChars:4000})).ndjson);
console.log((await wb.inspect({kind:"match",searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",options:{useRegex:true,maxResults:100},maxChars:3000})).ndjson);
console.log(xlsxPath);
