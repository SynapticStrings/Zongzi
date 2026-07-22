defmodule Zongzi do
  @moduledoc """
  Lightweight functional components and adaptation contracts in the SVS domain are designed to
  preserve as many user-defined parameters as possible.

  ## Components

  - **Stage Data (`Zongzi.Score`)**
    * Includes pitch system, time system (stage, ticks, and physical time), and note structure.
  - **Note Timeline (`Zongzi.Timeline`)**
    * Maintains note sequences and provides query primitives for anchoring structures related to note sequences.
  - **Anchoring Strategies (`Zongzi.Anchor`)**
    * Rebase the structure after editing operations (`rebase_all` / Strategy / NoteTriplet / ScoredHost)
  - **Intervention Data (`Zongzi.Intervention`)**
    * Modifiable shape of upstream generated results + `Declaration` semantic contract
  - **Windowing (`Zongzi.Windowing`)**
    * Post-rebase transient `Segment` (`Strategy.window/1`, default `RestSplit3Beats`)
  - **Engine Behavior (`Zongzi.Engine`)**
    * Accepts single or multiple... `Zongzi.Windowing.Segment` performs an inspection or rendering operation.

  ## 在您的系统中的角色

  - **Caller** 是任意编排者：持 Note 表、组 Context、串联 rebase → window → check/render、上浮 conflict
  - 编辑器操作面（曲线手绘等）不进系统
  - Declaration 具体 channel、真模型推理 — 引擎或旁路适配层

  ## Caller 相关

  Caller 侧「持轨」组件的文档锚点。

  Zongzi 只负责纯数据与校验，不替 Caller 选型其状态形态（GenServer / LiveView assigns
  / 纯数据管道），因此即 Caller 管理的一组随编辑共同演进的状态——无法也不应由库实现。
  以下把 Caller 必须自己维护的事项写成契约；若未来 Caller 形态收敛，可再长出共享 helper。

  ## Caller 需要自持的组件

  - `timeline` — `Zongzi.Timeline.t()`，seq 全序真实源
  - `notes_by_seq` — `%{SeqID.t() => Note.t()}`，note 实体快照，
    是 Windowing / Engine 的直接输入
  - `interventions` — `[Zongzi.Intervention.t()]`，AI 锚点集合，
    gc 与 rebase 的参照
  - tempo / beat 上下文 — tick ↔ ms 换算、播放头定位（Caller 业务自行决定）

  ## 同步契约

  每次 Timeline 写操作后，Caller 必须按下表同步 `notes_by_seq`。
  漏同步是最常见的踩坑点（见下节 Windowing 约束）。

  - `insert_note/2`、`insert_note_before/3`、`insert_note_after/3`
    → `{:ok, tl, note}`：`Map.put(notes, note.seq_id, note)`
  - `split_note/5` → `{:ok, tl, before, after}`：before 保留原 seq、after 占新 seq，
    两个都要写回
  - `merge_notes/4` → `{:ok, tl, merged}`：seq_a 写回 merged，删 seq_b
    （seq_b 成为 merge 墓碑）
  - `delete_note/2` → `{:ok, tl}`：删该 seq
  - `move_note/4` → `{:ok, tl}`：仅链序变化，`notes_by_seq` 不动
  - `splice_after/3` → `{:ok, tl, notes}`：逐个写回
  - `delete_range/3` → `{:ok, tl}`：逐个删除
  - `gc/2` → `{:ok, tl}`：物理移除无引用墓碑；`notes_by_seq` 本就不该含墓碑，
    无需动作
  - Note 层修改（`Note.drag_note/2`、`drag_duration/2`、`update_lyric/2`、
    `update_annotation/2`、`update_metadata/2`）→ `{:ok, note}`：
    不经过 Timeline，Caller 自行按原 seq 写回

  ## Windowing 约束

  `Zongzi.Windowing.Context.new/1` 要求 `notes_by_seq` 覆盖全部 active seq，
  缺任何一个都会返回 `{:error, {:missing_notes_for_seq, seqs}}`。
  该错误几乎总是上表某一步漏同步所致。

  ## 编辑回路

  一次编辑的完整回路：

      {:ok, tl, note} = Timeline.insert_note(tl, note)
      notes = Map.put(notes, note.seq_id, note)
      %{ survived: ..., conflicts: ..., decisions: ...} = Anchor.rebase_all(ints, tl, ctx)
      wctx = Windowing.Context.new(...)
      {:ok, results} = Windowing.run_stages(wctx, stages)
      # → Engine.check / Engine.render ...

  新 Note 的 ID 由 Caller 注入：`Zongzi.Util.ID.generate_id("Note_")`。
  """
end
