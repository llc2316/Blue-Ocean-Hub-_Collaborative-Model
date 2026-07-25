# 4.3 多能源供给模块（V4正式结构）

本目录只保留V4完整项目模型实际调用、独立验收或解释模型所需的代码与正式文档。原`runtime/`与`validation/`已经合并，不再维护两套同名代码。

## 目录职责

- `model/wind`：漂浮式风电设备出力模型。
- `model/pv`：漂浮式光伏设备出力模型。
- `model/tidal`：潮流能设备出力模型。
- `model/aggregation`：设备端口适配、源侧聚合、互补性指标、组合比较及联合场景校验。
- `model/demo_support`：仅供4.3独立基线演示生成源侧数据的平衡辅助函数；V4正式功率平衡由4.4模块负责，其下游输出不会进入V4接口。
- `integration`：将4.3的5分钟、W制结果转换为4.1—4.2冻结口径下的1小时、MW数据包。
- `tests`：4.3自动验收入口。
- `demos`：4.3公共基线和Version3演示入口。
- `docs`：模型说明、参数可识别性清单、完整报告和验收说明。
- `docs/assets`：报告使用的Version3合成数据图，文件哈希与历史索引记录的原始图一致；不作为当前V4联合结果图。

## 正式入口

- V4联合运行：`integration/v4_source_adapter.m`
- 公开代理资源审计：`integration/load_public_reference_resource_4_3.m`
- 4.3模块验收：`tests/run_all_tests_4_3_v3.m`
- 4.3完整演示：`demos/demo_version3_4_3.m`
- `somedata`审计演示：`demos/demo_public_resource_audit_4_3.m`

`v4_source_adapter.m`除聚合源功率外，现向4.8提供风、光、潮逐源小时能量、
辅机和集电损耗明细；这些字段只供核算，不在4.3引入价格或收益。
`load_public_reference_resource_4_3.m`只标准化NASA POWER风速、气温、短波辐照
和Open-Meteo波浪数据，不擅自外推轮毂风速、拆分DNI/DHI、合成潮流流速或计算
电功率。完整替代判断见`docs/4.3公开数据替代与证据清单.md`。

## 去重规则

风、光、潮设备模型以及设备适配、源侧聚合函数保留公共基线V2中的一份；互补性指标采用Version3增强实现，并保留Version3新增的组合比较、场景覆盖、状态字典和联合场景校验。已删除重复镜像、4.3初稿、报告图表生成脚本和旧的两套目录说明。

所有未完成工程校准的数值继续按`[假设值，待企业调研校准]`管理；尚未锁定文献依据的公式按`[需查证文献支撑]`管理。
