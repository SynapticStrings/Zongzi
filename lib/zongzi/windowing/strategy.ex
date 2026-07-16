defmodule Zongzi.Windowing.Strategy do
  @moduledoc """

  类似于 plug 管道，但不同点是直接载入函数而不是 atom 。

  ## 约束（见 decisions/windowing-post-rebase）

  - 只读 `Context`；不得改 Timeline
  - 不得做 `Declaration.resolve`（语义层）
  - 不得分配持久 window/slice id
  - intervention 按 `channel` pattern match 决定是否撑窗（见各实现 moduledoc）
  """

  alias Zongzi.Windowing.Context

  @callback window(Context.t()) :: {:ok, Context.t()} | {:error, term()}
end
