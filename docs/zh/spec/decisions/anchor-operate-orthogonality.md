# 结构锚 ⊥ 语义 operate

**Status**: Accepted  
**In-tree**: `Anchor.Strategy`、`Intervention.Declaration`、`Anchor.rebase_all`

## 决策

干预存活有两维，**禁止揉进同一回调**：

| 维 | 时机 | 模块 | 问题 |
|---|---|---|---|
| **结构锚** | 编辑后 | `Anchor.Strategy.rebase/3` | 锚还指得准吗？ |
| **语义 operate** | check 时 | `Declaration.resolve/2` | base 还对得上 snapshot 吗？如何叠 delta？ |

- Strategy **不得**读投影、比 snapshot。  
- Declaration **不得**改 Timeline 邻接。  
- `Intervention.strategy` 字段挂的是 **Anchor.Strategy** 模块（结构），与 Declaration 模块正交。

## 默认与扩展

- 默认结构策略：`NoteTriplet`（2-of-3 exact）。  
- 可选：`ScoredHost` 等。  
- 更宽锚/自定义结构策略：加 Strategy 实现，不塞进 resolve。

## 非目标

- 不在 Domain 发明第三种「模糊匹配」锚（避免静默错绑）。  
- 不规定 Frame 等具体 channel 的 identity 形状（适配器不透明 id）。
