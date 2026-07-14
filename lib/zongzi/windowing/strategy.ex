defmodule Zongzi.Windowing.Strategy do
  @moduledoc """
  分窗策略 behaviour：一次算出本轮全部 `Slice`。

  不是 Phoenix atom plug 管道。需要多步时在实现模块**内部**私有组合。

  ## 约束（见 decisions/windowing-post-rebase）

  - 只读 `Context`；不得改 Timeline
  - 不得做 `Declaration.resolve`（语义层）
  - 不得分配持久 window/slice id
  - intervention 按 `channel` pattern match 决定是否撑窗（见各实现 moduledoc）
  """

  alias Zongzi.Windowing.{Context, Slice}

  @callback window(Context.t()) :: {:ok, [Slice.t()]} | {:error, term()}
end
