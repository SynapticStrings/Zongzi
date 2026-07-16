defmodule Zongzi.Windowing do
  @moduledoc """
  渲染切片（post-rebase 瞬态闭包）的入口命名空间。

  契约见 `Windowing.Strategy`；默认策略 `Windowing.RestSplit3Beats`。
  决策全文：`docs/zh/spec/decisions/windowing-post-rebase.md`。

  本层**不**修改 Timeline、**不**做 Declaration.resolve。
  """

  alias Zongzi.Windowing.{Context, RestSplit3Beats}

  @doc """
  对同一 Context 依次跑多个 windowing 策略，前一个的 ctx 传入后一个。

  首个失败即短路。

  ## 用例

      # 默认单策略（RestSplit3Beats）：
      #   {:ok, segments} = Windowing.run_stages(ctx)

      # 链式多策略：
      #   {:ok, segments} = Windowing.run_stages(ctx, [RestSplit3Beats, WholeTrack])
  """
  @spec run_stages(Context.t(), [module()]) :: {:ok, [Zongzi.Windowing.Segment.t()]} | {:error, term()}
  def run_stages(%Context{} = ctx, strategies \\ [RestSplit3Beats]) do
    with {:ok, %Context{current_segments: segments}} <- do_run(strategies, ctx) do
      {:ok, segments}
    end
  end

  defp do_run([], ctx), do: {:ok, ctx}

  defp do_run([strategy | rest], ctx) do
    case strategy.window(ctx) do
      {:ok, %Context{} = ctx2} -> do_run(rest, ctx2)
      {:error, _} = err -> err
    end
  end
end
