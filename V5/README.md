# C4/V5 协同调度与目标优化模型

## 状态

V5 是在 V4 物理模块和冻结接口基础上形成的**自包含完整候选模型**，当前状态为
`V5_CANDIDATE_FOR_SCENARIO_VALIDATION`。V5 已复制 V4 的 4.1—4.8 边界、接口、物理模型、
高保真子模型、独立评价和证据文件。4.3在 `foundation/modules/4.3_source` 中只保留一份，
由 `source/v5_source_adapter.m` 转换为V5输入。运行、校验和公式追溯均不依赖外部
`V4整合/` 目录。

V5 核心模型与场景验证层保持分离；`foundation/` 中保留的 V4 测试、文档和图像只作为
来源快照，不是 V5 新结果。当前场景验证层包括：

- `scenarios/v5_build_all_channel_weather_task_scenario.m`：48 h、5 min 气象驱动的场景输入；
- `validation/run_v5_all_channel_sequence.m`：V5 求解、20 项自动判据和结果导出；
- `06_48h全出口气象任务场景设计.md`：场景边界和阶段定义；
- `07_48h全出口序列仿真分析.md`：本轮模型仿真结果与异常解释。

## V5 解决了什么

| V4 现状 | V5 处理 |
|---|---|
| 4.9 是确定性优先级可行性规则，不是最优调度 | 建立含整数启停的小时级 MILP |
| 4.8 评价发生在调度之后 | 经济、净温室气体、确定性 ENS 直接进入优化表达式 |
| 确定性未供能被命名为 EENS | 单场景改称 ENS；仅概率场景集才能汇总 EENS |
| 初始库存机会成本读取配置初值 | V5 使用输入包的真实窗口初态，并支持循环、期末目标或终端价值 |
| 氢回发电没有进入联合优化 | 增加可选氢发电及氢耗闭合；默认关闭 |
| 任意加权可能造成量纲和权重主导 | 默认采用 ε 约束法；权重未获决策者确认前不使用 |
| 小时层容易被误解为构网认证 | 只保留构网功率/能量裕度；频率、电压、限流、黑启动另设动态验收门 |

## 保持不变的责任边界

- V5 foundation中的唯一4.3模块负责风、光、潮设备曲线、可用率、切入/切出和源侧聚合，向优化层
  提供 `pSourceAvailableMW`；优化层不复制或改写源侧设备公式。
- V5 是唯一跨模块分配器；所有实际功率在同一个母线账本闭合。
- V5 `foundation/` 内的 4.4 保留独立母线账本，用于交叉复核，不参与第二次调度。
- 4.5 的 BESS、电解槽、储氢物理边界进入 V5 MILP；复制的 REGFM 动态模型用于后续秒级
  验收门。
- 4.6 的 PUE、任务、SLA 和算力模型已复制；小时 MILP 使用聚合边界，高保真任务模型可
  独立复核。
- 4.7 的海缆、氢交付及海洋用能模型已复制；V5 不把氨合成或真实船期伪装成已完成能力。
- 4.8 已复制为独立评价依据；V5 原生 KPI 不能取代生命周期财务、LCA 和随机可靠性分析。
- V4 4.9 不复制，防止启发式调度器与 V5 MILP 形成双重责任。

## 入口

MATLAB R2025b 与 Optimization Toolbox：

```matlab
addpath('V5模型')
result = run_v5_model(input);
```

`input` 可采用两种供能入口。

入口 A：直接功率边界，至少包含：

| 字段 | 单位 | 含义 |
|---|---:|---|
| `timeH` | h | 严格递增、固定步长时轴 |
| `pSourceAvailableMW` | MW | 4.3 在 MP-03 给出的区间平均可用功率 |

入口 B：内置供能引擎，提供：

```matlab
input.sourceCase.mode = 'device_inputs';
input.sourceCase.wind.input = windInput;
input.sourceCase.wind.parameters = windParameters;
% PV 和潮流能使用同样的 input/parameters 结构，可按场景启用。
result = run_v5_model(input);
```

内置引擎也保留 `v4_public_baseline_snapshot` 模式用于接口和机制验收。该模式全部环境、
功率曲线和容量扩展参数均为 **[假设值，待企业/OEM/场址数据校准]**，不得作为资源评估。

下一轮场景可选字段包括：

- `pComputeBaseDemandMW`、`pComputeFlexibleMaxMW`；
- `pMarineDemandMW`；
- `cableSendLimitMW`、`gridAcceptLimitMW`；
- `h2PipeLimitKgPerH`、`h2ShipLimitKgPerH`；
- `h2PipeMinimumKgPerH`、`h2ShipMinimumKgPerH`；
- 四类价格时序及各设备 `availability`；
- `initial` 中的 BESS 电量、氢库存、上一时段电解槽/算力/氢发电状态。

功率字段是区间平均 MW；BESS 电量和氢库存是区间末状态。滚动窗口必须将上一窗口末状态
原样传给下一窗口，不能重置为配置初值。

## 配置模式

- `mechanism_test`：可运行的机制检验参数，全部项目化数值均视为
  **[假设值，待企业调研校准]**，不得形成工程投资结论。
- `engineering_base`：关键参数留空；没有企业/OEM/接入批复签认时会拒绝运行。

V5 默认规模仍为 800 MW 源侧、80 MW/160 MWh BESS、100 MW 电解槽、120 MW 算力设施和
200 MW 海缆，作用只是复现 V4 联调边界和触发多出口竞争，**不是国能典型项目设计值**。

## 输出

- `result.dispatch`：逐时源、储、氢、算、海缆、海洋用能、弃电和未供能总账；
- `result.kpi`：经济净成本、项目排放、避免排放、净排放、ENS、消纳率及多形态交付量；
- `result.audit`：母线、BESS、储氢、海缆和服务账本的独立数值残差；
- `result.investmentGate`：独立投资阶段门；未提供企业签认阈值和全寿命现金流时不评价。
- `result.foundation`：4.1—4.9 在 V5 中的位置、执行模式和唯一责任登记表。
- `result.foundationBusCrosscheck`：适用时调用复制的 V4 4.4 账本独立复算母线残差。

`result.audit.pass=true` 只说明小时级代数可行，不能证明电压、频率、故障穿越、黑启动、
台风生存性、海洋腐蚀寿命或船运可执行性。

## 目录

```text
config/                         参数与证据状态
model/v5_build_problem.m        唯一 MILP 建模入口
model/v5_solve_dispatch.m       求解、逐时总账和 KPI
model/v5_validate_solution.m    独立残差检查
model/v5_run_epsilon_frontier.m ε 约束网格
model/v5_evaluate_investment_gate.m 投资阶段门
source/v5_source_adapter.m        V5自有V3源侧适配器，不复制设备模型
scenarios/                         V5机制测试场景构造器
validation/                        场景运行、自动判据和结果导出
foundation/library/               复制的 4.1 边界和 4.2 冻结接口
foundation/modules/4.3_source/    唯一风、光、潮物理模型与证据
foundation/modules/               4.4—4.8完整物理/评价模块
foundation/integration/common/    V2 公共适配工具
somedata/                         4.3 公开资源代理的本地输入
outputs/                           V5生成结果，不属于物理模型实现
manifests/v5_foundation_manifest.csv 4.1—4.8 复制文件哈希清单
tools/sync_v4_foundation.ps1      明确授权时更新物理基线
tools/verify_v5_foundation.ps1    V5 自包含基线普通校验
```

审查结论、参数证据、公式符号、下一轮接口和供能快照说明分别见本目录 `01`～`05` 文档。
