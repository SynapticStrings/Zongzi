# Changelog

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
