# Focus-Split 载荷越界（Caveat）

**Status**: Caveat（已知限制，开放等待 Declaration on_rebase 钩子）

## 问题

pitch 曲线 intervention 挂在 note A 上。A 被 split 成 A₁ + A₂。

- **结构层**：triplet rebase 2/3 匹配 → `{:ok, :preserve}`，无提醒
- **语义层**：曲线 tick 边界仍覆盖原来的 A 全范围，现已跨到 A₂ 身上

当前兜底：`Declaration.resolve` 在 check 时对 snapshot → mismatch → semantic conflict。
但此信号太晚——用户要到渲染那轮才发现，且已有的曲线数据边界本身仍未修正。

## 计划的修复

在 `Intervention.Declaration` behaviour 加结构层钩子：

```elixir
@callback on_rebase(Intervention.t(), rebase_meta, Timeline.t()) ::
  {:ok, Intervention.t()}
  | {:split_payload, [Intervention.t()]}
  | {:conflict, reason}
```

让 parameter 类 channel 在结构 rebase **时** 就拆分/收缩 payload 边界。

## 当前约束

- Declaration 实现不得假设 `on_rebase` 存在；缺失时按现状走 snapshot 兜底。
- 实现 `on_rebase` 后，新的子 interventions 需各自锚定 Split 后的音符。
- 本决策在 Declaration 实现落地时重审。

## 非目标

- 不在 Timeline / Anchor 层改数据结构。
- 不在此冻结 `on_rebase` 的确切签名。
