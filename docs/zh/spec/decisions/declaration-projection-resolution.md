# Declaration → 投影 → Resolve

**Status**: Accepted  
**In-tree**: `Intervention.Declaration`、`Engine` check 路径

## 决策

凡**可被引擎/管线生成、又可被用户修改**的数据，走同一生命周期：

```text
Declaration（约束 / scope / snapshot / resolve 策略）
    → 投影（引擎预测或上游生成）
    → resolve（snapshot 比对 + 应用 delta，或 conflict）
    →（可选）render 消费已决议结果
```

- `scope/2`：切窗前静态保守上界，**不得**依赖本次投影结果。  
- `snapshot/2`：挂载时从投影取**原始值**。  
- `resolve/2`：check 时比对；落在 **check_***，不是「必须先出 final audio」。

## 与 Engine

见 `Engine`：`check_*` 产出 check_artifact（含 conflicts）；`render_*` 才是重产物。

## 非目标

- 不规定 continuous vs event_sequence 的 Caller 存储 layout。  
- 具体 channel 实现不进核。
