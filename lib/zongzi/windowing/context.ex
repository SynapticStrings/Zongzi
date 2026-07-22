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

  require Zongzi.Score.Tick
  alias Zongzi.{Timeline, Intervention, Score.Note, Score.Tick, Score.TimeSigMap, Score.TempoMap}
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
    opts: %{}
  ]

  # `current_segments` 不从 new/1 被载入
  @doc "从 map/keyword 构造 Context。"
  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)

    # 等用 Zongzi.Util.Model 重构以规避 Map.fetch!/2
    %__MODULE__{
      timeline: Map.fetch!(attrs, :timeline),
      notes_by_seq: Map.get(attrs, :notes_by_seq, %{}),
      time_sig_map: Map.get(attrs, :time_sig_map),
      tempo_map: Map.get(attrs, :tempo_map),
      interventions: Map.get(attrs, :interventions, []),
      opts: Map.get(attrs, :opts, %{})
    }
  end

  @doc """
  从 Context 组装 `Declaration.scope/2` 需要的 `scope_ctx` plain map。

  ## 字段

  - `:timeline` — `ctx.timeline`
  - `:tempo_map` — `ctx.tempo_map`
  - `:tpqn` — `ctx.opts[:tpqn]` 或默认 480
  """
  @spec scope_ctx(t()) :: Zongzi.Intervention.Declaration.scope_ctx()
  def scope_ctx(%__MODULE__{timeline: tl, tempo_map: tm, opts: opts}) do
    %{
      timeline: tl,
      tempo_map: tm,
      tpqn: Map.get(opts, :tpqn, 480)
    }
  end

  @doc """
  将 `Declaration.scope/2` 的 tagged return 归一化为 tick 区间。

  - `{tick, tick}` → 原样返回 `{:ok, {tick, tick}}`
  - `{:seconds, s, e}` → 用 `scope_ctx.tempo_map` 转 tick
  - `{:seconds, _, _}` 但 `tempo_map` 为 nil → `{:error, :tempo_map_required}`
  """
  @spec normalize_scope(
          {Tick.t(), Tick.t()} | {:seconds, float, float},
          Zongzi.Intervention.Declaration.scope_ctx()
        ) :: {:ok, {Tick.t(), Tick.t()}} | {:error, term()}
  def normalize_scope({s, e}, _scope_ctx) when Tick.is_numeric_tick(s) and Tick.is_numeric_tick(e) do
    {:ok, {s, e}}
  end

  def normalize_scope({:seconds, _s, _e}, %{tempo_map: nil}) do
    {:error, :tempo_map_required}
  end

  def normalize_scope({:seconds, s, e}, %{tempo_map: tm, tpqn: tpqn}) do
    {:ok, {TempoMap.sec_to_tick(tm, s, tpqn), TempoMap.sec_to_tick(tm, e, tpqn)}}
  end
end
