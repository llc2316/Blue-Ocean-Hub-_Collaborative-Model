# 蓝海枢纽第四章4.1—4.9 V4整合

本包采用“原模块不改动、必要代码快照、V4适配器对接、4.4唯一总账、4.8只评价、4.9唯一调度”的方式整合4.1—4.9。公共接口固定使用`BLUE_HUB_CH4_SCHEMA_V2 / 2.0.0 / common_case_v2`。联合入口只读取本目录内的`library/`和`modules/`，不依赖项目根目录中的原模块代码。

当前执行顺序为：4.3/4.6发布边界→4.9下发逐时算力、储氢、海洋用能和外送请求→4.3—4.7返回响应→4.9依据实际响应确认弃电与缺供→4.4核验物理总账→4.8评价。未供能只作为可靠性统计量，不作为母线虚拟注入。

## 原模型调用关系

| 模块 | V4处理 | 原模型是否改动 |
|---|---|---|
| 4.3 | 调用`4.3多源能源/v2/公共基线模型_v2`的风、光、潮设备模型与聚合链，转换为MW/h标准包 | 否 |
| 4.4 | 使用冻结功率平衡式建立纯LEDGER函数；历史设备类与隐式备用逻辑不进入联合入口 | 否 |
| 4.5 | 按既有脚本的SOC、SEC和氢库存关系拆分为响应与状态提交适配器 | 否 |
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

开发目录中重新纳入源快照：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1
```

若V4不位于源项目根目录下一层，可显式指定源项目根目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1 -SourceRoot "源项目根目录"
```

打包或移动后进行包内自校验：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_v4_snapshot.ps1 -VerifyOnly
```

`-VerifyOnly`只读取`manifests/v4_package_manifest.csv`中的包内相对路径，不访问V4父目录或原始4.1—4.7目录。运行代码同样以入口脚本自身位置动态定位`library/`、`modules/`、`integration/`和`outputs/`。

全部联调数值来自`interface_smoke`，均为 **[假设值，待企业调研校准]**，不得形成工程经济结论。

## 运行

MATLAB R2019b及以上版本：

```matlab
cd('文件所处位置')
out = run_v4_integration();
report = run_all_tests_v4();
```

成功标志：

```text
BLUE HUB CH4 V4 INTEGRATION: PASSED
BLUE HUB CH4 V4: ALL TESTS PASSED
```

结果写入`outputs/v4_integration_result.mat`、`outputs/v4_hourly_summary.csv`和`outputs/v4_objective_summary.csv`。

开发构建时仍检查4.1、4.2、4.4—4.7及4.8—4.9目标架构原文与V4副本的一致性；交付运行时改为核验包内运行/文档文件的相对路径、大小和SHA-256，不依赖原始项目目录。4.3属于择优合并后的V4派生模块，以来源说明和动态验收保证可追溯性。详细统计见`V4模块纳入与匹配检查报告.md`。

## 重要边界

- 4.9当前是`FEASIBILITY_RULE_V4_4_9`可行性调度器，不宣称Pareto、随机或滚动优化已经完成。
- 算力当前按已冻结的在线最低功率请求优先保障；海洋需求按刚性/柔性边界接受供能，不足量进入EENS。
- 4.8当前使用未校准联调系数，不宣称完成项目NPV、IRR、LCOE、LCOH或产品碳足迹评价。
- V4不宣称完成容量优化、频率稳定性或构网控制。
- 4.6内部量通过其既有`equivalent_gpu_it_power_kw`转换为标准化服务量；当前接口归一化仍是 **[假设值，待企业调研校准]**。
- 未核验的专业公式继续沿用原模块证据状态；V4不改变其文献等级。
