# 4.8 多目标评价模块

4.8只读取4.3—4.7已经提交的实际量，计算经济、环保、可靠性目标和KPI，不参与功率分配或状态更新。

- `model/v4_objective_parameters_4_8.m`：集中保存未校准的联调系数。
- `model/v4_evaluate_objectives_4_8.m`：生成三目标原始向量及能源、产品和消纳KPI。
- `model/v4_validate_evaluation_4_8.m`：校验评价数据包。
- `docs/4.8多目标评价说明.md`：说明公式边界、当前可输出内容与待补数据。

当前结果仅用于接口联调，不能作为NPV、IRR、LCOE、LCOH或产品碳足迹结论。
