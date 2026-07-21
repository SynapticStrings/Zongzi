defmodule Zongzi.Anchor.Context do
  @moduledoc """
  Caller 注入的只读领域上下文。

  **Caller** 不是本库模块，而是任意库外编排者。
  它在调用 `Anchor.rebase_all/4` 时组装本 map：持有 Note 快照、可选窗映射等。

  Timeline 查询原语不依赖本结构。Strategy 用此访问 Note **静态**字段
  以辅助选宿主——不得读投影输出（投影判断是 `Declaration.resolve` 的事）。

  与 `Anchor.ScoredHost` / `choose_host` 中的「host」（新 focus seq）不是同一概念。

  ## 键

  本 Context 仅携带策略无关的批级共享快照。策略/渠道级旋钮放在各自 `Options` struct 中，
  通过 `Intervention.strategy` 的 `{module(), options}` 元组传递。

  - `:notes_by_seq` — `%{SeqID.t() => Note.t()}`，Caller 在 rebase 调用时给的快照
  - `:seq_to_window` — 可选，`%{SeqID.t() => window_id}`；rebase 时若提供，应为**上一轮**窗映射（启发式）。本轮最终切片在 rebase **之后**由 `Windowing.Strategy.window/1` 重算
  - `:focus_note` — 孤儿 relocate 时原始 focus 的 Note（已删时可从旁路恢复）
  - `:channel` — atom
  - `:extra` — map，引擎/插件私货
  """

  @type t :: %{optional(atom()) => term()}

  def new(attrs \\ %{}), do: Map.new(attrs)
end
