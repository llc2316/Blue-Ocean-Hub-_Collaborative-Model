# 4.6 V4 适配器

## 文件

- `v4_compute_boundary_4_6.m`：在 4.9 请求前发布无条件功率范围、条件在线最低功率和主模型模式。
- `v4_compute_bridge.py`：把 4.9 的逐时请求写入原 4.6 求解器，并统一输出 V4 字段。

## 调用

主集成模式：

```text
python v4_compute_bridge.py ... --mode sla
```

吸纳上界对照：

```text
python v4_compute_bridge.py ... --mode power_following
```

默认模式为 `sla`。`power_following` 不读取外生任务到达、队列或 SLA，不得用于任务缺供和可靠性结论。

请求功率为 0 或不低于逐时 `dc_online_min_mw`。现有核心求解器收到低于在线最低功率的正请求会报错，4.9 应先调用储能保供或将设施置为停机，再进行第二次请求。
