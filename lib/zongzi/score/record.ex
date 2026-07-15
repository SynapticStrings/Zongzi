defmodule Zongzi.Score.Record do
  @moduledoc """
  通用的、基于 Tick/Bar 的 Record 抽象。

  将 Tempo 和 TimeSig 的共同模式提取为统一的 Record 事件模型：

  - 每个 Record 是一个位于特定位置（Tick 或 Bar）的时间线事件
  - Record 列表通过 `RecordMap` 编译为可二分查找的区间元组
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

  @typedoc "Record 携带的对应值"
  @type value :: term()

  @typedoc "单个时间线的事件"
  @type t :: {position(), value()}

  @typedoc """
  Record 列表。

  可以是有限列表，也可以带上一个动态终点 `{records, last}`。

  当最后一个片段没有明确的结束位置时使用 `Tick.dynamic_tick()`。
  """
  @type records :: [t()] | {[t()], last :: Tick.t()}
end
