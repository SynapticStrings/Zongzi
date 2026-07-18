# Changelog

## Unreleased — 2026/07/18

Caller 集成反馈（zongzi_feasibility 落地）驱动的契约修订：

### 破坏性变更

- **`Declaration.on_rebase/3` → `on_rebase/4`**：新增第 4 参 `context`（Caller 注入
  `rebase_all` 的 `Anchor.Context`，含 `notes_by_seq`），declaration 可据此做 payload 的
  tick 级维护，不再需要 Caller 预注入切分信息。relocate 时 strategy 的 meta
  （from/to/method/打分）并入 meta 透传，不再丢弃。
- **`Timeline.gc/2` 返回 `{:ok, t()}`**（原为裸 struct），与库内其他写操作一致。
  同时修复 gc 误读 `int.declaration.referenced_seqs/1` 的 bug——正确来源是
  `int.strategy || NoteTriplet`（declaration 契约上根本没有该回调）。

### 新增

- `Anchor.rebase_all/4` 返回值新增 `:decisions` 键：
  `%{intervention_id => :preserve | :rebase | :relocate | :split | :conflict}`，
  结构决策可被 Caller 消费（指标/日志），无需事后对比 anchor 重推。
- `Timeline.split_note/5`：新增可选 `attrs` 参数，透传 `Note.split/4`
  （如给后半音符不同 lyric）。
- `Score.TrackBuilder`：纯文档模块，固化 Caller 侧「持轨」组件清单、
  notes_by_seq 逐写操作同步契约与编辑回路；`Timeline` moduledoc 已交叉引用。

### 文档

- `RestSplit3Beats` 补充 caveat：intervention scope 是保守上界且会撑窗，
  余量过宽会把本应切开的 gap 粘连成一窗。
- 明确 `on_rebase` split 的子干预不再过 strategy.rebase，锚正确性由 declaration 负责。

## 0.1.0 — 2026/07/14

初始版本。Zongzi 作为 SVS 领域的函数式组件库，提供 Score 基础、Timeline 写路径、
Anchor 结构 rebase、Intervention 数据契约与 Engine/Windowing behaviour 定义。

### Score 基础

- Note / Tempo / TimeSig / Grid 数据结构与合并逻辑
- Key 行为（含 TwelveET 实现）与 Note merge 语义
- 可配置 TPQN（ticks per quarter note）
- RecordMap / TempoMap / TimeSigMap
- `Helpers.normalize_attrs/1`

### Timeline

- SeqID 永久位置标识，由 Timeline 自持 counter 生成
- note_order 有序链表 + tombstone（merge / delete 两类）
- 写操作：insert / delete / split / merge / drag
- `Timeline.Query` 读原语：`status/2`、`scan/4`、`neighborhood/3`、`scrub_triplet/2`、`hops/3`
- `gc/2` 回收无引用墓碑

### Anchor 与 Intervention

- `Intervention` 结构：anchor、payload、snapshot、strategy、declaration、on_rebase 回调
- `Anchor.Context`：携带 orphan_direction、策略参数等上下文
- `Anchor.rebase_all/4`：编辑后批量结构 rebase
- `Anchor.NoteTriplet` 策略：3-of-3 exact match → preserve；2-of-3 → rebase；0–1/3 → conflict
- `Anchor.ScoredHost`：deleted/orphan notes 的 relocate 打分策略（同 key / 同窗）
- `Intervention.Declaration` behaviour：`scope/2`、`snapshot/2`、`resolve/2`、`on_rebase/3`

### Engine 与 Windowing

- `Engine` behaviour：`check/1` + 可选 `render/1`，只消费 `[Segment]`
- `Windowing.Strategy` behaviour：`window/1` → `[Segment]`
- `Windowing.WholeTrack`：整轨策略
- `Windowing.RestSplit3Beats`：按 3 拍切窗策略
- `Windowing.Context` / `Windowing.Segment`

### Curve

- Adapter behaviour（替代原 Protocol）
- Bezier / CatmullRom 适配器
- Chunk / ControlPoint 结构

### 重构与文档

- 模块命名统一：Slice → Segment，Host → Caller
- Timeline 相关模块归入 Score 命名空间
- SeqID 生成从 Note 移入 Timeline
- Model.new/1 要求显式传 id（纯函数原则）
- 完整的心智模型文档、设计决策记录、黄金场景（`docs/zh/spec/`）
