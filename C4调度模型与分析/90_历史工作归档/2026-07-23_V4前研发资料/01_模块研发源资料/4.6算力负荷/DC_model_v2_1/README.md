# 深蓝海能源岛：DC-only算力中心模型 V1.1

## 模型边界

仅建模水下数据中心内部：

任务到达 → 刚性/柔性/可选任务调度 → IT功率 → 液冷辅助功率 → 动态PUE → DC总用电 → GPU·h收入、电费与电力边际利润。

不建立风电、光伏、电池、制氢、储氢或电力外送模型。外部能源侧只需提供DC可用功率上限和电价；基准场景可直接使用常量。

## 需要放置的数据

将用户自己的 `UDC_data` 放到项目根目录。代码不附带数据。

```text
UDC_DC_only_model_v1_1/
├── UDC_data/
│   ├── 01_Workload/
│   │   ├── green_compute_v1_168h.csv
│   │   └── task_type_parameters.csv
│   ├── 02_IT_System/
│   │   └── it_system_parameters.csv
│   ├── 03_Cooling_PUE/
│   │   ├── cooling_parameters.csv
│   │   └── Copernicus_20250601_20250621.nc
│   └── 04_Economics_Interface/
│       ├── compute_price.csv
│       └── power_interface.csv  # constant模式下可忽略
├── config/
├── scripts/
└── src/
```

具体修改见 `DATA_UPDATE_GUIDE.md`。

## V1.1关键变化

1. 老师168小时任务表不改时间戳；代码自动映射到 `simulation_start`。
2. 21天Copernicus NetCDF无需打开；代码自动截取对应7天、选择约50 m有效格点并插值到小时。
3. 月度电价和固定DC功率上限直接写在配置中，不需要复制168行。
4. 算力价格保留元/GPU·h。
5. 使用 `equivalent_gpu_it_power_kw` 将MWh-IT换算为GPU·h：

```text
GPU·h = MWh-IT × 1000 / equivalent_gpu_it_power_kw
```

6. 默认关闭现货任务补满，避免IT负载长期满载导致PUE近似常数。

## 默认基准场景

```json
"simulation_start": "2025-06-01 00:00:00",
"simulation_hours": 168,
"workload_scale": 0.20,
"spot_workload_scale": 0.00,
"power_interface_mode": "constant",
"constant_dc_power_cap_mw": 8.20,
"constant_electricity_price_yuan_per_mwh": 372.70
```

## 运行

Windows：

```bat
run_windows.bat
```

或：

```bash
python -m pip install -r requirements.txt
python scripts/check_data.py --data-root UDC_data
python scripts/run_model.py --data-root UDC_data --output outputs/base_case
```

## 输出

- `hourly_results.csv`：逐时任务、GPU·h、IT功率、冷却功率、PUE、总功率、收入和电费
- `summary.json`：总服务量、总GPU·h、能耗、平均PUE、收入和边际利润
- `audit.json`：任务守恒、队列、容量和功率约束残差
- `data_check.json`：海温选点、日期覆盖和输入警告
- 结果图PNG

利润口径为电力边际贡献，不含CAPEX、折旧和全部固定运维成本。
