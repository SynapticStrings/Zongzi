defmodule Zongzi.Windowing.Segment do
  @moduledoc """
  引擎 check/render 消费的**瞬态批处理闭包**（本轮「这一锅」）。

  时间轴为左闭右开 `[start_tick, end_tick)`。权威成员仅包括
  `seq_ids`（active SeqID），`note_ids` 若需要由 Caller 派生。

  由 `Windowing.Strategy.window/1` 产出。
  """

  alias Zongzi.Score.Tick
  alias Zongzi.Timeline.SeqID
  import Tick

  @type t :: %__MODULE__{
          start_tick: Tick.numeric_tick(),
          end_tick: Tick.numeric_tick(),
          seq_ids: [SeqID.t()]
        }

  # 函数本质上不需要 update/2，所以没有 use Zongzi.Util.Object
  defstruct [:start_tick, :end_tick, seq_ids: []]

  @doc "构造 Segment。"
  @spec new(Tick.numeric_tick(), Tick.numeric_tick(), [SeqID.t()]) ::
          {:ok, t()} | {:error, term()}
  def new(start_tick, end_tick, seq_ids)
      when is_numeric_tick(start_tick) and is_numeric_tick(end_tick) and start_tick < end_tick and
             is_list(seq_ids) do
    {:ok, %__MODULE__{start_tick: start_tick, end_tick: end_tick, seq_ids: seq_ids}}
  end

  def new(start_tick, end_tick, _seq_ids)
      when is_numeric_tick(start_tick) and is_numeric_tick(end_tick) and start_tick >= end_tick,
      do: {:error, {:empty_or_inverted_range, start_tick, end_tick}}

  def new(start_tick, end_tick, _seq_ids)
      when is_integer(start_tick) and is_integer(end_tick),
      do: {:error, {:negative_tick, start_tick, end_tick}}
end
