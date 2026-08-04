# C4 workspace scope

- Start with `00_项目导航.md`, then read `V5模型/README.md`; for Chapter-5 tests read the sibling `../C5/00_C5导航.md`.
- The sole active joint-model implementation is `V5模型`; C5 owns scenarios, test data, runners and results.
- `V4整合` and `external` are archived under `90_历史工作归档/2026-07-31_V4与external归档` and are not runtime dependencies.
- Do not recursively scan `90_历史工作归档`. For traceability tasks, search `90_历史工作归档/历史文件索引.csv` or `历史资料索引.md` first, then open only matched files.
- Ignore `.git`, generated outputs, previews, render caches, inspection logs, `node_modules`, `__pycache__`, and large-data ZIP contents unless explicitly required.
- Keep 4.3 source aggregation, 4.4 bus balance, 4.5 storage/hydrogen, 4.6 compute load, 4.7 output channels, 4.8 evaluation, and 4.9 dispatch separated through the frozen 4.2 interfaces.
- Do not read `企业调研问题清单.md` unless the task concerns data acquisition, parameter identification, or enterprise interviews.
- Use `V5模型/tools/verify_v5_foundation.ps1` for ordinary model-package verification. Do not rebuild from archived V4 unless explicitly requested.
- Mark unverified engineering parameters `[假设值，待企业调研校准]` and unverified formulas `[需查证文献支撑]`.
