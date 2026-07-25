# 4.8 多目标评价模块

4.8只读取4.3—4.7已经提交的实际量，计算经济、环保、可靠性目标和KPI，不参与功率分配或状态更新。

- `model/v4_objective_parameters_4_8.m`：集中保存公开市场情景锚点与未校准联调系数。
- `model/v4_evaluate_objectives_4_8.m`：生成三目标原始向量及能源、产品和消纳KPI。
- `model/v4_validate_evaluation_4_8.m`：校验评价数据包。
- `model/v4_public_generation_cost_benchmarks_4_8.m`：保存不同口径的公开成本参考点及不可比声明。
- `model/v4_levelized_source_cost_4_8.m`：在币值年、边界和共享成本已统一时，按NREL ATB公式计算逐源LCOE。
- `docs/4.8多目标评价说明.md`：说明公式边界、当前可输出内容与待补数据。

当前结果仅用于接口联调，不能作为NPV、IRR、LCOE、LCOH或产品碳足迹结论。
4.3现已向4.8提供风、光、潮逐源小时电量明细；但默认成本仍使用聚合回退值。
只有`sourceVariableOMCNYPerMWhByType`完成同口径校准后，评价器才启用逐源变动
运维成本，否则审计字段返回`AGGREGATE_FALLBACK_UNCALIBRATED`。
