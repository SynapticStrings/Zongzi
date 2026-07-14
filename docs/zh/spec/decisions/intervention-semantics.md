# Intervention 语义

**Status**: Accepted  
**In-tree**: `Intervention`、`Engine` params

## 是 Intervention

上游（模型/管线）**生成的、且允许用户修改**的局部结果，例如：

- 曲线参数（控制点 + 边界 + 原始值 → snapshot）  
- timing 偏移  
- **可编辑的 G2P 音素序列**（锚在 note / 序列上）

## 不是 Intervention

全局/音色类旋钮（Gender、Energy…）：

- 不进 `Intervention` struct，不走 Timeline 结构 rebase  
- 放在 Engine Request 的 `params`（或等价物）  
- check 时做**类型与范围约束**；非法 → 引擎 error，不伪装成 anchor conflict

## 两个判死时机

| 时机 | 层 | 结果 |
|---|---|---|
| 编辑后 | `Anchor.Strategy` | preserve / rebase / relocate / 结构 conflict |
| check 时 | `Declaration.resolve` | apply / 语义 conflict |

snapshot 优于输入指纹：输入变了但 base 投影不变 → 不应判死。

## 非目标

- 不规定 UI 如何展示 conflict。  
- 不规定 History 条目粒度（Caller）。
