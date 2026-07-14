defmodule Zongzi.Windowing.Slice do
  @moduledoc """
  瞬态渲染闭包。

  时间轴为左闭右开区间 `[start_tick, end_tick)`。
  权威成员是 `seq_ids`（active SeqID）；不持久化、无稳定 id。
  """

  alias Zongzi.Score.Tick
  alias Zongzi.Timeline.SeqID

  @type t :: %__MODULE__{
          start_tick: Tick.numeric_tick(),
          end_tick: Tick.numeric_tick(),
          seq_ids: [SeqID.t()]
        }

  defstruct [:start_tick, :end_tick, seq_ids: []]

  @doc "构造 Slice；要求 `start_tick < end_tick`（允许空成员，用于纯 pad 边界，默认不使用）。"
  @spec new(Tick.numeric_tick(), Tick.numeric_tick(), [SeqID.t()]) ::
          {:ok, t()} | {:error, term()}
  def new(start_tick, end_tick, seq_ids)
      when is_integer(start_tick) and is_integer(end_tick) and is_list(seq_ids) do
    cond do
      start_tick < 0 or end_tick < 0 ->
        {:error, {:negative_tick, start_tick, end_tick}}

      start_tick >= end_tick ->
        {:error, {:empty_or_inverted_range, start_tick, end_tick}}

      true ->
        {:ok, %__MODULE__{start_tick: start_tick, end_tick: end_tick, seq_ids: seq_ids}}
    end
  end
end
