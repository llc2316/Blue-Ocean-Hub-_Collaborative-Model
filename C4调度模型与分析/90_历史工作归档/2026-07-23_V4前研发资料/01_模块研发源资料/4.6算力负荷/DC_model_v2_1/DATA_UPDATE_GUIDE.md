# UDC_data 最终修改说明（V1.1）

## 一、无需修改的文件

- `01_Workload/green_compute_v1_168h.csv`：保留老师原始168小时任务曲线及原时间戳。代码自动映射到配置中的仿真日期。
- `01_Workload/task_type_parameters.csv`：可继续使用。
- `03_Cooling_PUE/cooling_parameters.csv`：可继续使用。
- `04_Economics_Interface/power_interface.csv`：在默认 `power_interface_mode=constant` 下被忽略，可保留也可移入参考文件夹。
- ERA5和风力文件：DC-only V1.1不读取，放入可选参考文件夹。

## 二、必须做的修改

### 1. 替换Copernicus海温文件

把2025-06-01至2025-06-21、区域20.8–21.7°N/112.4–113.4°E的有效 `.nc` 放入：

```text
UDC_data/03_Cooling_PUE/
```

该目录根部只保留一个海温 `.nc`。不需要打开、裁剪或转换。代码根据：

```json
"simulation_start": "2025-06-01 00:00:00",
"simulation_hours": 168
```

自动提取6月1日至7日，并从区域中选取最接近目标坐标和50 m深度的有效格点，再将日数据插值成小时数据。

### 2. 修改IT等效GPU功率参数

在 `02_IT_System/it_system_parameters.csv` 中删除：

```csv
equivalent_resource_count,8192,...
resource_unit_type,equivalent_accelerator,...
```

增加：

```csv
equivalent_gpu_it_power_kw,0.90,kW/GPU,一个可计费等效GPU连同CPU/内存/网络分摊后的IT功率,场景假设（敏感性0.60~1.20）
```

V1.1仍兼容旧的8192参数，但建议改成0.90 kW/GPU，使MW-IT到GPU·h的换算更透明：

```text
GPU·h = MWh-IT × 1000 / equivalent_gpu_it_power_kw
```

### 3. 修改算力价格列名

把 `04_Economics_Interface/compute_price.csv` 改为：

```csv
task_type,price_yuan_per_gpu_h,source_type
rigid_inference,8.0,market_reference_scenario
flexible_batch,4.0,market_reference_scenario
continuous_training,6.0,market_reference_scenario
optional_job,2.5,market_reference_scenario
```

价格仍是市场常见的元/GPU·h，不改成元/MWh-IT。

## 三、电价和功率上限不再需要逐时CSV

默认配置为：

```json
"power_interface_mode": "constant",
"constant_dc_power_cap_mw": 8.20,
"constant_electricity_price_yuan_per_mwh": 372.70
```

含义是在整个168小时基准场景中采用广东2025年6月月度综合价372.70元/MWh，以及8.20 MW的DC输入上限。代码自动生成168小时向量，不需要手工复制168行。

后期若能源系统给出真实逐时接口，再设置：

```json
"power_interface_mode": "file"
```

并提供与仿真期同长度的 `power_interface.csv`。

## 四、老师168小时任务与21天环境数据如何对应

老师任务文件只提供一条168小时相对负荷曲线。V1.1不修改其数值，只将它映射到选择的环境周：

- 第一周：`simulation_start = 2025-06-01 00:00:00`
- 第二周：`simulation_start = 2025-06-08 00:00:00`
- 第三周：`simulation_start = 2025-06-15 00:00:00`

每次仍运行168小时。这样可以在相同任务需求下比较不同海温周的PUE、耗电和利润，而不是复制成504小时连续业务数据。

## 五、避免PUE再次恒定

默认：

```json
"spot_workload_scale": 0.00,
"use_workload_spot_price": false
```

基础场景关闭现货任务自动补满，使IT负载随刚性/柔性任务变化。后续可建立现货场景，将 `spot_workload_scale` 改为0.01、0.03等。
