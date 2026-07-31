# V5公开代理数据与年度场景输入说明

本目录存放 V5/4.7 的公开代理数据、年度场景原始输入、派生输入、派生输出和来源清单。  
它们适合做接口联调、示例和参数追踪，不是工程实测、SCADA、OEM 或合同数据。

## 文件说明

- `nasa_power_hourly_gd_offshore_20250601_20250607_utc.csv`：NASA POWER 公开小时气象数据，含 50 m 风速、10 m 风速、2 m 气温和逐小时短波辐照。
- `nasa_power_hourly_gd_offshore_20250601_20250607.csv`：NASA POWER 首次拉取的本地太阳时版本，仅保留作追溯。
- `open_meteo_marine_gd_offshore_20250601_20250607.csv`：Open-Meteo 公开海况数据，含波高、波向和波周期。
- `public_reference_v4_output_bridge_input_168h.csv`：168 小时派生输入表，可直接给 `integration/v4_output_bridge.py` 使用。
- `public_reference_v4_output_bridge_result_168h.csv`：按同一套公式计算得到的 168 小时派生输出表。
- `public_reference_parameters.yaml`：生成派生输入时使用的公开代理参数和假设。
- `public_data_manifest.csv`：数据来源、网址、覆盖范围和工程状态清单。
- `字段说明_中文.csv`：桥接输入和输出字段的中文对照说明。
- `ff31187b331bcb4c38a793470892d53e.nc`：ERA5 2025全年逐小时10 m风速
  `u10/v10` 再分析数据，共8,760小时、12个网格点，无缺测；属于公共再分析代理。
- `cmems_mod_glo_phy_my_0.083deg_P1D-m_1785375573011.nc`：Copernicus Marine
  2025全年日均海水位温，包含47.37 m和55.76 m两层；陆地区域为缺测掩码。
- `场景测试1_2025全年正常运行基准场景设计报告.md`：年度场景的时间、区域、正常运行和
  算力任务扩展边界。

## 2025年度场景入口

V5年度场景由以下构造器读取上述NetCDF和4.6内部168小时任务形状：

```matlab
addpath(fullfile(pwd,'V5模型','scenarios'));
scenario=v5_build_annual_2025_normal_scenario();
```

当前年度构造边界包括：

- 按场景报告原口径将ERA5 10 m风速直接送入V5功率曲线，未做轮毂高度外推；
  该处理 **[需查证文献支撑]**，不能作为可研资源评估；
- 选择最接近113.0°E、21.2°N、50 m且全年有效的海温网格，日值线性插值到小时；
- 以固定随机种子2025扩展168小时内部任务形状；周间5%和小时3%扰动幅度为
  **[假设值，待企业调研校准]**；
- V5使用随海温变化的满载PUE代理；负载—PUE耦合尚未内生进入联合MILP，
  相关公式 **[需查证文献支撑]**。

## 桥接输入字段

派生输入表包含以下给 4.7 桥接脚本直接使用的字段：

- `export_requested_mw`
- `marine_available_mw`
- `marine_requested_mw`
- `h2_available_kg`
- `h2_requested_kg`
- `compute_served_mwh_cs`
- `compute_delivery_cap_mwh_cs`

其余资源列和估算列仅用于追溯，不代表工程实测值。

## 数据来源网址

- NASA POWER Hourly API：<https://power.larc.nasa.gov/docs/services/api/temporal/hourly/>
- Open-Meteo Marine API：<https://open-meteo.com/en/docs/marine-weather-api>

## 使用边界

这些文件只能作为公共代理数据使用。正式报告前应替换为：

- 风机 OEM 功率曲线和项目 SCADA
- 4.9 调度请求
- 4.5 制氢可用量、产品状态和库存实测
- 4.6 算力服务量和价格接口
- 海缆、管道、船运和并网合同数据
- 市场价格和运维证据

## 注意

nasa_power_hourly... 和 open_meteo_marine... 是从官方公开接口拉下来的，来源真实，但它
们只是公共参考点数据，不是项目场址的实测。

public_reference_v4_output_bridge_input_168h.csv、
public_reference_v4_output_bridge_result_168h.csv、public_reference_parameters.yaml 里有
不少是按仓库示例参数和规则派生/估算出来的，不能当作真实工程数据。
