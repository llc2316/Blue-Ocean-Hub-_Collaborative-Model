# V5 自包含物理基线

本目录是 V4 已验收物理、接口和证据模块在 V5 内的可追溯快照。V5 运行时不再需要读取
外部 `V4整合/`。

## 迁入范围

- `library/4.1*`：边界、计量点和口径；
- `library/4.2*`：冻结 V2 公共配置、交换包和校验器；
- `modules/4.3_source`：风、光、潮设备模型及源侧聚合；
- `modules/4.4_bus`：独立母线总账；
- `modules/4.5_storage_hydrogen`：BESS、PEM、储氢及构网动态代理；
- `modules/4.6_compute`：算力、PUE、任务和 SLA 模型；
- `modules/4.7_outputs`：海缆、氢交付和海洋用能模型；
- `modules/4.8_objectives`：独立评价和生命周期参数；
- `integration/common`：V2 公共端口填充工具。

V4 的 4.9 启发式调度器没有迁入。V5 的 `model/v5_build_problem.m` 是唯一跨模块优化和
调度责任主体。

## 唯一实现原则

`modules/4.3_source` 是 V5 唯一的4.3物理实现。`source/v5_source_adapter.m` 只负责把
4.3结果转换为V5 Schema V3输入，不保存第二份设备模型。

4.4—4.8 的复制模块用于：

1. 保存公式、参数、测试和高保真模型的完整依据；
2. 支持母线、动态构网、任务/SLA、交付和生命周期评价的独立复核；
3. 为后续把高保真响应边界回传 V5 MILP 提供本地接口。

小时级功率分配、SOC、氢库存、算力和输出通道仍只由 V5 MILP 求解，不调用第二套调度器。

## 哈希与同步

`manifests/v5_foundation_manifest.csv` 记录复制文件的来源相对路径、V5 相对路径、大小和
SHA-256。

普通校验：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify_v5_foundation.ps1
```

只有明确要求更新物理基线时才执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sync_v4_foundation.ps1
```

同步脚本不复制 `outputs`、缓存和 V4 4.9。复制文件保留原 `v4_` 函数名用于来源追溯，
不表示 V5 仍依赖外部 V4。
