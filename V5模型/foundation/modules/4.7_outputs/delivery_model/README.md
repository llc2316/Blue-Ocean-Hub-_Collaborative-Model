# 蓝海枢纽4.7用能与外送子模型代码包

本目录是4.7用能与外送的可审计原型代码，覆盖电力外送、算力服务、氢能交付、海洋综合用能、功率平衡、目标函数、约束、单元测试和24小时示例。它用于跑通参数、公式和接口，不是第四章统一优化求解器。

> **V4运行边界：** 本目录是原生独立工程。V4正式桥接器只调用`power_export.py`和
> `marine_load.py`；`compute_load.py`、`hydrogen_output.py`、`balance.py`、
> `objectives.py`和`scenario.py`不进入V4联合结果。

## 与其他模块的接口

- 独立原型从上游接收可分配功率；V4正式运行中由4.9下发请求，4.4只做事后实际总账。
- 从4.5接收制氢量、储氢可用量和产品状态；本模块只处理氢能交付通道，不重复建立电解槽、SOC或储氢库存调度。
- V4从4.6接收已经完成的算力服务量，只施加光缆交付上限。
- V4向4.9返回交付量、海洋服务和缺供状态；总收入与成本由4.8统一评价。

## 目录结构

```text
submodules/
├─ configs/parameters.yaml
├─ examples/run_example.py
├─ src/bluehub_submodules/
│  ├─ power_export.py
│  ├─ compute_load.py
│  ├─ hydrogen_output.py
│  ├─ marine_load.py
│  ├─ balance.py
│  ├─ objectives.py
│  ├─ constraints.py
│  ├─ parameters.py
│  └─ scenario.py
├─ tests/
├─ pyproject.toml
├─ uv.lock
└─ 目标函数与约束条件.md
```

## 运行

在当前`delivery_model`目录执行：

```powershell
$env:UV_CACHE_DIR = Join-Path $PWD '.uv-cache'
uv run python -m unittest discover -s tests
uv run python examples/run_example.py
```

不使用`uv`时，系统Python必须显式加入`src`源码路径：

```powershell
$env:PYTHONPATH = (Resolve-Path '.\src').Path
python -m unittest discover -s tests
```

如已安装pytest，也可执行：

```powershell
uv run pytest
```

## Python调用示例

```python
from bluehub_submodules import default_parameters, simple_greedy_dispatch, summarize_results

params = default_parameters()
results = simple_greedy_dispatch(params)
print(summarize_results(results))
```

单独调用电力外送、算力和氢能交付函数时，应从`configs/parameters.yaml`或经审批的公共参数表读入参数，不应把示例数值写入正式算例：

```python
from bluehub_submodules.power_export import evaluate_power_export
from bluehub_submodules.compute_load import evaluate_compute_load
from bluehub_submodules.hydrogen_output import evaluate_hydrogen_output

# params_* 由统一配置或公共参数适配器生成。
power_result = evaluate_power_export(requested_power_mw, params_power)
compute_result = evaluate_compute_load(requested_compute_mw, params_compute)
hydrogen_result = evaluate_hydrogen_output(
    requested_hydrogen_output_kg,
    requested_pipe_output_kg,
    requested_ship_output_kg,
    available_hydrogen_start_kg,
    params_hydrogen,
)
```

## 当前模型边界

- 不做详细电网潮流，只做海缆容量、陆上接纳能力和损耗约束。
- 不做真实光通信网络路由，光缆只作为算力服务交付能力约束。
- 不做船舶逐航次调度，船运暂用等效`kg/h`能力表达。
- 不重复模拟4.5内部制氢、储能和储氢状态。
- 不做完整投资优化，当前目标函数以运行期收入、成本和约束为主。

所有默认参数均为`[假设值，待企业调研校准]`；写入报告或公共基线前必须替换为有来源、测点、单位和版本记录的参数。公式缺少已核验来源时标注`[需查证文献支撑]`。

## 接入4.9优化器

- `evaluate_power_export`：电力外送链路。
- `evaluate_compute_load`：算力负荷与光缆交付。
- `evaluate_hydrogen_output`：氢能交付通道。
- `evaluate_marine_load`：海洋综合用能。
- `evaluate_integrated_hour`：综合功率平衡检查。

接入Pyomo、CVXPY或MATLAB优化框架时，应保持4.2变量字典规定的变量名、单位、测点与正方向，并由4.9统一决定跨模块调度，不在本模块复制调度逻辑。
