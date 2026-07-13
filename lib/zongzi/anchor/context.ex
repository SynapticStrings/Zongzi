defmodule Zongzi.Anchor.Context do
  @moduledoc """
  Host 注入的只读领域上下文。

  Timeline 查询原语不依赖本结构。Strategy 用此访问 Note 静态字段
  以辅助选宿主——不得读投影输出（投影判断是 Declaration.resolve 的事）。

  ## 常用键

  - `:notes_by_seq` — %{SeqID.t() => Note.t()}，Host 在 rebase 调用时给的快照
  - `:seq_to_window` — 可选，分窗后注入（Windowing 层完成后可用）
  - `:channel` — atom
  - `:extra` — map，引擎/插件私货
  """

  @type t :: %{optional(atom()) => term()}

  def new(attrs \\ %{}), do: Map.new(attrs)
end
