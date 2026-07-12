defmodule Zongzi.Timeline.TimeSig do
  @moduledoc """
  拍号系统的领域模型。
  """

  alias Zongzi.Timeline.Record

  # 标准拍子
  @type standard ::
          {numerator :: pos_integer(), denominator :: pos_integer()}
          | {:standard, numerator :: pos_integer(), denominator :: pos_integer()}

  # 复拍子
  @type compound :: {:compound, groupings :: [pos_integer()], denominator :: pos_integer()}

  # 散拍子
  @type free :: :san

  @typedoc "拍编号。"
  @type bar :: pos_integer()

  @typedoc "拍号。"
  @type t :: standard() | compound() | free()

  @typedoc "节拍变化事件"
  @type time_sig_event :: {bar(), t()}

  @type time_sig_events :: [time_sig_event()] | {[time_sig_event()], Record.end_position()}

  @doc "获取一个完整小节的 Tick 长度"
  def ticks_per_bar({num, den}, tpqn) when is_integer(num) and is_integer(den),
    do: ticks_per_bar({:standard, num, den}, tpqn)

  def ticks_per_bar({:standard, num, den}, tpqn), do: div(total_notes(num, tpqn), den)

  def ticks_per_bar({:compound, groupings, den}, tpqn),
    do: div(total_notes(Enum.sum(groupings), tpqn), den)

  def ticks_per_bar(:san, _tpqn), do: nil

  defp total_notes(num, tpqn), do: tpqn * 4 * num
end
