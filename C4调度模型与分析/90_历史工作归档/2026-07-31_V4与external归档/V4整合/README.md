# 蓝海枢纽第四章4.1—4.9 V4整合

本包采用“原模块不改动、必要代码快照、V4适配器对接、4.4唯一总账、4.8只评价、4.9唯一调度”的方式整合4.1—4.9。公共接口固定使用`BLUE_HUB_CH4_SCHEMA_V2 / 2.0.0 / common_case_v2`。联合入口只读取本目录内的`library/`和`modules/`，不依赖项目根目录中的原模块代码。

当前24 h/48 h机制场景统一使用800 MW源侧、80 MW/160 MWh BESS、100 MW电解槽、
16单元算力集群和200 MW/320 kV/200 km海缆。配置同时区分`interfaceLimit`、
`installed`和`dispatchRequest`三层容量。E/H/C/M资产开关已接入调度和全生命周期资产账；
未启用资产CAPEX、固定运维和替换成本强制为0。该统一规模为
**[假设值，待企业调研校准]**，正式四方案8760 h比较留待第5章。

可直接用于报告整合的章节正文见`V4第四章整体章节文案.md`；各模块功能完成度、当前结果、
重复职责和未完成能力见`V4模块任务完成度与去重审查.md`。
第5章典型场景、四方案对比口径和可复跑就绪度审计见
`chapter5_preparation/第5章典型场景验证与四方案对比准备.md`。

当前执行顺序为：4.3/4.5/4.6发布边界→4.9读取显式储能状态并下发逐时电池、电解槽、算力、提氢、海洋用能和外送请求→4.3—4.7返回响应→算力实际功率低于请求时按“海洋缺口→海缆余量→同小时直通制氢→弃电”再分配→4.9依据实际响应确认弃电与缺供→4.4核验物理总账→4.8评价。直通制氢的新增产量在同小时等量提取，不改变储氢库存轨迹或期末规则；未供能只作为可靠性统计量，不作为母线虚拟注入。

## 原模型调用关系

| 模块 | V4处理 | 原模型是否改动 |
|---|---|---|
| 4.3 | 调用`4.3多源能源/v2/公共基线模型_v2`的风、光、潮设备模型与聚合链，转换为MW/h标准包 | 否 |
| 4.4 | 使用冻结功率平衡式建立纯LEDGER函数；历史设备类与隐式备用逻辑不进入联合入口 | 否 |
| 4.5 | 唯一物理核心执行SOC、模块化制氢和储氢；另有REGFM_B1秒—分钟级正序代理、连续8760 h库存模型、显式BOUNDARY和期末硬约束 | 新增V4多时标模型与适配器 |
| 4.6 | 先发布设施功率边界，再接收4.9逐时功率请求并调用`load_inputs/solve_dc_only` | 否 |
| 4.7 | 区分海洋需求功率与可分配功率，返回实际服务、刚性负荷状态和未供能；旁路重复总控 | 否 |
| 4.8 | 在状态提交后读取实际量，计算经济、环保、可靠性原始目标及KPI | 新增V4评价入口 |
| 4.9 | 将原内嵌规则抽离为唯一跨模块可行性调度器，并执行容量、SOC及功率闭合校验 | 新增V4调度入口 |

## 自包含目录

```text
library/4.1边界与口径/        4.1冻结公共文档
library/4.2变量与接口/        4.2公共配置、数据包、校验器和测试
modules/4.3_source/          4.3唯一正式模型、验收、文档和源侧适配器
modules/4.4_bus/             4.4唯一总账和精简参考模型
modules/4.5_storage_hydrogen/ 4.5状态模型、参数资料和适配器
modules/4.6_compute/         4.6 DC模型、必要数据和Python桥
modules/4.7_outputs/         4.7交付模型、测试和Python桥
modules/4.8_objectives/      4.8三目标评价、参数和校验器
modules/4.9_dispatch/        4.9跨模块调度与约束校验器
integration/common/         跨模块公共端口填充工具
manifests/                   源目录与V4快照逐文件SHA-256清单
```

旧研发树仍位于V4同级目录时，可重新纳入源快照：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1
```

当前项目已将旧研发树移入历史归档。只有明确需要重建源快照时，才显式指定归档中的源项目快照：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1 -SourceRoot "..\90_历史工作归档\2026-07-23_V4前研发资料\01_模块研发源资料"
```

打包或移动后进行包内自校验：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1 -VerifyOnly
```

`-VerifyOnly`只读取`manifests/v4_package_manifest.csv`中的包内相对路径，不访问V4父目录或原始4.1—4.7目录。运行代码同样以入口脚本自身位置动态定位`library/`、`modules/`、`integration/`和`outputs/`。

联调物理规模、负荷、初态及未签认成本来自`interface_smoke`，属于
**[假设值，待企业调研校准]**；氢价、电价等少量参数采用公开市场情景锚点，
但不是项目合同价。两类参数均不得直接形成工程经济结论。

## 运行

MATLAB R2019b及以上版本：

```matlab
cd('文件所处位置')
out = run_v4_integration();
addpath('modules/4.5_storage_hydrogen');
[storageOut, storageReport] = run_4_5_standalone_validation();
report = run_all_tests_v4();
addpath('chapter5_preparation');
[stressOut, stressReport] = run_all_channel_validation_v4();
```

生成“最终指标汇总”和“全周期指标变化过程”两套分离图：

```powershell
python .\chapter5_preparation\render_validation_figures.py
```

成功标志：

```text
BLUE HUB CH4 V4 INTEGRATION: PASSED
BLUE HUB CH4 V4: ALL TESTS PASSED
```

联合结果写入`outputs/v4_integration_result.mat`。其中：

- `v4_hourly_summary.csv`保留公共母线精简总账；
- `v4_hourly_detail.csv`保存4.3—4.9统一时轴下的源、储、氢、算、海缆、海洋用能、弃电、缺供和母线残差全过程；
- `v4_kpi_summary.csv`保存最终指标长表；
- `v4_economic_breakdown.csv`和`v4_environment_breakdown.csv`保存成本/收入及排放分项；
- `v4_capacity_audit.csv`保存各资产接口上限、建设容量、请求峰值、最大实际功率、利用小时、CAPEX占比和闲置率；
- `figures/final_kpi/`保存最终指标图，`figures/timeseries/`保存全周期变化图，二者不混放；
- 48 h场景在`outputs/chapter5_all_channel_48h/`中生成同构结果。

4.5独立三时标结果写入`modules/4.5_storage_hydrogen/outputs/multiscale_validation/`，并将72 h、秒级构网、黑启动和8760 h季节库存分别成图。

文档、代码、图片和附件的最新一致性核对见`V4文档代码图像一致性检查报告.md`。

只修改V4自有文档、图片或适配器后，可在不重建历史源快照的情况下刷新包清单：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1 -RefreshPackageManifestOnly
```

开发重建时仍检查4.1、4.2、4.4—4.7及4.8—4.9目标架构原文与V4副本的一致性；普通运行与交付校验只核验包内运行/文档文件的相对路径、大小和SHA-256，不依赖历史归档。4.3属于择优合并后的V4派生模块，以来源说明和动态验收保证可追溯性。文件—模块—入口—输出的完整关系见`V4第四章整体章节文案.md`附录；代码、文档和图像一致性见`V4文档代码图像一致性检查报告.md`。

## 重要边界

- 4.9当前是`FEASIBILITY_RULE_V4_4_9`可行性调度器，不宣称Pareto、随机或滚动优化已经完成。
- 4.4只核验各模块最终`actual`功率，不负责跨模块功率分配；“统筹调度”责任属于4.9。
- 算力默认是可削减、可停机的高价值柔性负荷；仅`computeFirmRequestMW`明确声明的部分才进入电气刚性需求。设施开机时功率不得落入0与在线最低功率之间，停机后的任务缺口由4.6队列/SLA口径记录。
- 4.8当前使用未校准联调系数，不宣称完成项目NPV、IRR、LCOE、LCOH或产品碳足迹评价。
- 4.5已有NREL/WECC REGFM_B1正序降阶代理、端口电压/限流闭合、20 s阶跃、120 s持续支撑和黑启动顺序检查；5 MW/1 MWh小时备用为 **[假设值，待PCS厂商校准]**。V4不宣称完成频率稳定性、构网或黑启动工程认证；涌流、谐波、不平衡、故障、保护和多机并联仍需EMT/HIL/现场验证。
- 4.6内部量通过其既有`equivalent_gpu_it_power_kw`转换为标准化服务量；当前接口归一化仍是 **[假设值，待企业调研校准]**。
- 4.6负责PUE、任务和算力服务生产，4.7只负责光缆交付；4.7原生工程中的重复算力、
  制氢、总账和目标函数不进入V4联合入口。
- 默认24小时`unified_24h_mixed`从0 kg储氢开始，当前产氢38,743.073 kg、交付38,355.642 kg，电池SOC严格回到50%、储氢期末为0 kg。虽然小时级跨时库存峰值为0 kg，仍按1 h额定产氢量配置1,761.494 kg工艺缓冲罐；1 h为 **[假设值，待企业调研校准]**。电池和储氢循环/最低期末规则只在末时刻施加；长期经济比较仍需统一采用相同初末规则和真实8760 h资源。
- `chapter5_preparation/run_all_channel_validation_v4.m`提供48小时全通道压力场景，容量和分段倍率均为 **[假设值，待企业调研校准]**，用于验证调度机制而非推荐工程规模。
- 未核验的专业公式继续沿用原模块证据状态；V4不改变其文献等级。
