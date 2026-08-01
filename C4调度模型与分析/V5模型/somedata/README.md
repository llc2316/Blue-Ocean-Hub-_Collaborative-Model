# V5源侧公开代理数据说明

本目录存放V5源侧公开代理数据、派生输入、派生输出和来源清单。  
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
2025年度ERA5、Copernicus、任务和PUE测试输入已迁至
`../../../C5/5.1场景设计/data/`；V5不再保存年度测试数据或场景构造器。

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
