defmodule Zongzi.Score.Record do
  @moduledoc """
  General record abstraction based on tick/bar.

  Record event model:

  - Every record is an event on the timeline at a specific location (tick or bar)
  - Records are compiled by `RecordMap` into interval tuples for binary search
  """

  alias Zongzi.Score.Tick

  @typedoc """
  Record 的位置是从 0 开始的非负整数。

  对于 Tempo 表示 Tick 刻，对于 TimeSig 表示 Bar 小节号。
  """
  @type position :: non_neg_integer()

  @typedoc """
  用于表示乐谱末端边界。

  可能是已知的某个结果，也用于表示乐谱末端边界。
  """
  @type end_position :: position() | :open_end

  def open_end, do: :open_end

  @typedoc "Payload contained with record"
  @type value :: term()

  @typedoc "单个时间线的事件"
  @type t :: {position(), value()}

  @typedoc """
  List of records.

  可以是有限列表，也可以带上一个动态终点 `{records, last}`。

  当最后一个片段没有明确的结束位置时使用 `Tick.dynamic_tick()`。
  """
  @type records :: [t()] | {[t()], last :: Tick.t()}
end
