defmodule Zongzi.Windowing do
  @moduledoc """
  渲染切片（post-rebase 瞬态闭包）的入口命名空间。

  契约见 `Windowing.Strategy`；默认策略 `Windowing.RestSplit3Beats`。
  决策全文：`docs/zh/spec/decisions/windowing-post-rebase.md`。

  本层**不**修改 Timeline、**不**做 Declaration.resolve。
  """
end
