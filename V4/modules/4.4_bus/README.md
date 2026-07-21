# 4.4 公共母线功率平衡

- `integration/v4_bus_ledger.m`：V4唯一正式入口，只读取4.3、4.5、4.6、4.7的`actual`并计算冻结总账。
- `reference_model/`：原Python设备类、场景和可视化参考，不进入V4联合运行。

已移除仅用于重新生成工程的`builder.py`、`gen_all.py`、`fix_imports.py`、`report_gen.py`和冗余`run_model.py`。原文件仍保留在项目根模块。

