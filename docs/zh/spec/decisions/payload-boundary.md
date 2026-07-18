# Focus-Split 载荷越界

**Status**: Accepted (`Declaration.on_rebase/4` added; `Anchor.rebase_all` wired)

## 问题

pitch 曲线 intervention 挂在 note A 上。A 被 split 成 A1 + A2。
- 结构层: triplet rebase 2/3 match -> {:ok, :preserve}
- 语义层: 曲线 tick 边界跨到 A2 身上

## 已落地的修复

`Intervention.Declaration` behaviour 已加 `on_rebase/4` (optional callback):
- `{:ok, intervention}` -> 原样或收缩后
- `{:split, [intervention, ...]}` -> 拆成多条
- `{:conflict, reason}` -> semantic conflict

`Anchor.rebase_all` 在策略决策成功后, 若 `Intervention.declaration` 非 nil 且实现了
`on_rebase/4`, 以 `(int, meta, timeline, context)` 调用:
- meta 含 `%{decision, old_anchor, new_anchor}`; relocate 时并入 strategy 的 meta
  (from/to/method/打分等), 不再丢弃.
- context 即 Caller 注入 `rebase_all` 的 `Anchor.Context` (含 `notes_by_seq`),
  declaration 可据此做 payload 的 tick 级维护 (平移 / 按 split_tick 切分).

缺失 declaration 或模块未实现 -> 按原 intervention 进入 survived.

## 约束

- `{:split, children}` 的子干预**不再过 strategy.rebase**——子干预锚的正确性由
  declaration 负责.
- `rebase_all` 返回值的 `:decisions` 键记录每条 intervention 的结构决策
  (`:preserve | :rebase | :relocate | :split | :conflict`), 供 Caller 做指标/日志.

## 非目标

不在 Timeline / Anchor 层改数据结构.
