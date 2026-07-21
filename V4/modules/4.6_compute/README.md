# 4.6 绿色算力负荷

- `DC_model_v2_1/`：原DC-only模型的源码、配置、测试和当前运行必需数据。
- `integration/v4_compute_boundary_4_6.m`：在4.9运行前发布设施功率可行边界。
- `integration/v4_compute_bridge.py`：接收4.9逐时功率请求，调用原求解器并返回设施功率、IT/辅助功率、队列和MWh-CS字段。
- `docs/`：模块数学说明。

已删除当前模型明确不读取的`trace_seren.csv`、`EQCAM_Dataset.csv`和根级`data_stream` NetCDF。当前运行仍保留任务聚合表、设备参数、冷却参数、价格接口及实际使用的CMEMS海温文件。
