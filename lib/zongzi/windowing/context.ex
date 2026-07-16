defmodule Zongzi.Windowing.Context do
  @moduledoc """
  `Windowing.Strategy.window/1` 的只读输入。

  ## 必填

  - `timeline` — 编辑后的 Timeline
  - `notes_by_seq` — active（及策略需要的）`SeqID → Note`；Timeline 不持 Note 字段

  ## 可选

  - `time_sig_map` / `tempo_map` — 拍/秒换算；默认策略主要用拍
  - `interventions` — **结构 rebase 后存活** 的列表
  - `opts` 常用键：
    - `:tpqn` — 默认 `480`
    - `:beat_ticks` — 显式一拍 tick 数（覆盖从拍号/假定推导）
    - `:extra` — 策略私货

  Caller 负责在 `Anchor.rebase_all` 之后组装本结构。
  """

  alias Zongzi.{Timeline, Intervention, Score.Note, Score.TimeSigMap, Score.TempoMap}
  alias Zongzi.Timeline.SeqID
  alias Zongzi.Windowing.Segment

  @type t :: %__MODULE__{
          timeline: Timeline.t(),
          notes_by_seq: %{SeqID.t() => Note.t()},
          time_sig_map: TimeSigMap.t() | nil,
          tempo_map: TempoMap.t() | nil,
          interventions: [Intervention.t()],
          current_segments: [Segment.t()],
          opts: map()
        }

  defstruct [
    :timeline,
    notes_by_seq: %{},
    time_sig_map: nil,
    tempo_map: nil,
    interventions: [],
    current_segments: [],
    opts: %{},
  ]

  # `current_segments` 不从 new/1 被载入
  @doc "从 map/keyword 构造 Context。"
  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %__MODULE__{
      timeline: Map.fetch!(attrs, :timeline),
      notes_by_seq: Map.get(attrs, :notes_by_seq, %{}),
      time_sig_map: Map.get(attrs, :time_sig_map),
      tempo_map: Map.get(attrs, :tempo_map),
      interventions: Map.get(attrs, :interventions, []),
      opts: Map.get(attrs, :opts, %{})
    }
  end
end
