# Focus-Split 载荷越界

**Status**: Accepted (`Declaration.on_rebase/3` added; `Anchor.rebase_all` wired)

## 问题

pitch 曲线 intervention 挂在 note A 上。A 被 split 成 A1 + A2。
- 结构层: triplet rebase 2/3 match -> {:ok, :preserve}
- 语义层: 曲线 tick 边界跨到 A2 身上

## 已落地的修复

`Intervention.Declaration` behaviour 已加 `on_rebase/3` (optional callback):
- `{:ok, intervention}` -> 原样或收缩后
- `{:split, [intervention, ...]}` -> 拆成多条
- `{:conflict, reason}` -> semantic conflict

`Anchor.rebase_all` 在策略决策成功后, 若 `Intervention.declaration` 非 nil, 调用 `on_rebase/3`.
缺失 declaration 或模块未实现 -> 按原 intervention 进入 survived.

## 非目标

不在 Timeline / Anchor 层改数据结构.
