defmodule Zongzi.Windowing.Segment do
  @moduledoc """
  引擎 check/render 消费的**瞬态批处理闭包**（本轮「这一锅」）。

  ## 语义（新，不是历史持久 Segment/Utterance）

  - **不是** Timeline 上的持久短语实体，无稳定 id，不进工程序列化。
  - **不是** 结构锚目标；锚仍在 SeqID / Strategy 上。
  - 时间轴：左闭右开 `[start_tick, end_tick)`。
  - 权威成员：`seq_ids`（active SeqID）；`note_ids` 若需要由 Host 派生。

  由 `Windowing.Strategy.window/1` 产出；`WholeTrack` 产出单段即「整轨」。
  引擎 facade **只**认 `[Segment]`，不再区分 whole/partial 回调。
  """

  alias Zongzi.Score.Tick
  alias Zongzi.Timeline.SeqID

  @type t :: %__MODULE__{
          start_tick: Tick.numeric_tick(),
          end_tick: Tick.numeric_tick(),
          seq_ids: [SeqID.t()]
        }

  defstruct [:start_tick, :end_tick, seq_ids: []]

  @doc "构造 Segment；要求 `start_tick < end_tick`。"
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
