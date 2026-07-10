defmodule Zongzi.Timeline.Tempo do
  @moduledoc """
  时长工具的入口。
  """
  alias Zongzi.Timeline
  alias Zongzi.Timeline.Tick
  import Tick

  # ---- 速度变化事件 ----

  defmodule Event do
    @moduledoc "速度变化事件"

    @type context :: term()
    @type t :: %__MODULE__{
            module: module(),
            context: context()
          }
    defstruct [:module, :context]
  end

  @typedoc "自第 x 刻开始，有了 XXX 速度段。"
  @type tempo_event :: {Tick.numeric_tick(), Event.t()}

  @type tempo_events :: [tempo_event()] | {[tempo_event()], last :: Tick.t()}

  # ---- 速度片段 ----

  defmodule Segment do
    @moduledoc "速度段的行为定义，预计实际支持阶梯、线性、甚至曲线。"

    @typedoc "实现速度段的结构体。"
    @type segment :: struct()

    @typedoc "实际运行的时间长度。"
    @type duration :: float() | :infinity

    @doc "从事件以及时间线构建出当前的片段。"
    @callback build_from_event(
                start_tick :: Tick.numeric_tick(),
                end_tick :: Tick.t(),
                event :: Event.context()
              ) :: {:ok, segment()} | {:error, reason :: term()}

    @doc "该片段的持续时间。"
    @callback duration_sec(segment) :: duration()

    @doc "该片段从开始到第 `tick_offset` 刻的持续时间。"
    @callback tick_to_sec(segment, tick_offset :: Tick.numeric_tick()) :: duration()

    @doc "该片段第 X.XX 秒所对应的刻。"
    @callback sec_to_tick(segment, sec_offset :: Timeline.physical_time()) :: Tick.numeric_tick()

    defmacro __using__(_opts) do
      quote do
        @behaviour Zongzi.Timeline.Tempo.Segment
      end
    end
  end

  defmodule Step do
    @moduledoc """
    最简单的速度段定义——阶梯。

    如果全部都是一个阶梯，那么就是恒定速度。
    """

    alias Zongzi.Timeline.Tempo.{Segment, Event}
    use Segment

    defstruct [:start_tick, :end_tick, :bpm]

    @impl true
    def build_from_event(_, _, %{bpm: bpm}) when not is_number(bpm),
      do: {:error, {:invalid_bpm, bpm}}

    def build_from_event(_, _, %{bpm: bpm}) when bpm <= 0,
      do: {:error, {:bpm_is_negative, bpm}}

    def build_from_event(start_tick, end_tick, %{bpm: bpm}),
      do: {:ok, %__MODULE__{start_tick: start_tick, end_tick: end_tick, bpm: bpm}}

    def build_from_event(_, _, invalid_context),
      do: {:error, {:invalid_tempo_context, invalid_context}}

    @impl true
    def duration_sec(%{end_tick: end_tick}) when is_dynamic_tick(end_tick), do: :infinity

    def duration_sec(seg) do
      tick_to_sec(seg, seg.end_tick - seg.start_tick)
    end

    @impl true
    def tick_to_sec(seg, ticks) do
      sec_per_quarter = 60.0 / seg.bpm
      ticks * (sec_per_quarter / ticks_per_quarter_note())
    end

    @impl true
    def sec_to_tick(seg, offset_sec) do
      round(offset_sec * (ticks_per_quarter_note() * seg.bpm / 60))
    end
  end

  defmodule Linear do
    @moduledoc """
    线性渐变速度段。

    在 `start_tick` 到 `end_tick` 之间，BPM 从 `bpm_start` 均匀变化到 `bpm_end`。

    ## 数学

        bpm(t) = bpm_start + rate * t
        rate = (bpm_end - bpm_start) / duration_ticks

        sec(t) = (60 / (TPQN * rate)) * ln(bpm(t) / bpm_start)   (rate != 0)
        sec(t) = t * (60 / bpm_start) / TPQN                      (rate = 0, 退化为恒定)
    """

    alias Zongzi.Timeline.Tempo.{Segment, Event}
    alias Zongzi.Timeline.Tick
    import Tick

    use Segment

    defstruct [:start_tick, :end_tick, :bpm_start, :bpm_end]

    @impl true
    def build_from_event(_start_tick, end_tick, _context) when is_dynamic_tick(end_tick),
      do: {:error, :linear_requires_finite_end_tick}

    def build_from_event(_start_tick, _end_tick, %{bpm_start: bs, bpm_end: _be})
        when not is_number(bs) or bs <= 0,
        do: {:error, {:invalid_bpm_start, bs}}

    def build_from_event(_start_tick, _end_tick, %{bpm_start: _bs, bpm_end: be})
        when not is_number(be) or be <= 0,
        do: {:error, {:invalid_bpm_end, be}}

    def build_from_event(start_tick, end_tick, %{bpm_start: bpm_start, bpm_end: bpm_end}),
      do:
        {:ok,
         %__MODULE__{
           start_tick: start_tick,
           end_tick: end_tick,
           bpm_start: bpm_start,
           bpm_end: bpm_end
         }}

    def build_from_event(_, _, invalid_context),
      do: {:error, {:invalid_tempo_context, invalid_context}}

    @impl true
    def duration_sec(%{end_tick: end_tick}) when is_dynamic_tick(end_tick), do: :infinity

    def duration_sec(seg) do
      tick_to_sec(seg, seg.end_tick - seg.start_tick)
    end

    @impl true
    def tick_to_sec(_seg, 0), do: 0.0

    def tick_to_sec(seg, ticks) do
      rate = rate(seg)

      if rate == 0.0 do
        ticks * (60.0 / seg.bpm_start) / ticks_per_quarter_note()
      else
        bpm_at = seg.bpm_start + rate * ticks
        60.0 / (ticks_per_quarter_note() * rate) * :math.log(bpm_at / seg.bpm_start)
      end
    end

    @impl true
    def sec_to_tick(_seg, sec) when sec == 0.0, do: 0

    def sec_to_tick(seg, offset_sec) do
      rate = rate(seg)

      if rate == 0.0 do
        round(offset_sec * seg.bpm_start * ticks_per_quarter_note() / 60.0)
      else
        bpm_at = seg.bpm_start * :math.exp(offset_sec * rate * ticks_per_quarter_note() / 60.0)
        round((bpm_at - seg.bpm_start) / rate)
      end
    end

    # 计算 BPM 变化率（每 tick 的 BPM 变化量）
    defp rate(%{bpm_start: bs, bpm_end: be, start_tick: st, end_tick: et}) do
      duration = et - st
      (be - bs) / duration
    end
  end

  # 应用曲线
  # 这里的曲线要和 `Zongzi.Curve` 区分开
  defmodule Curve, do: nil

  # ---- 速度段功能调用 ----
  # 可以直接通过 Tempo.blabla(segment_or_module, blabla) 调用速度段内部的函数

  @doc """
  根据模块、刻以及上下文构建片段的函数。

  把一些实现无关的错误（e.g. tick 早于零）提前拎出来。
  """
  def build_segment_from_event(_module, start_tick, _, _) when start_tick < 0,
    do: {:error, {:tick_invalid, %{start_tick: start_tick}}}

  def build_segment_from_event(module, start_tick, end_tick, payload)
      when is_dynamic_tick(end_tick),
      do: module.build_from_event(start_tick, end_tick, payload)

  def build_segment_from_event(_module, start_tick, end_tick, _) when start_tick >= end_tick,
    do: {:error, {:tick_invalid, %{start_tick: start_tick, end_tick: end_tick}}}

  def build_segment_from_event(module, start_tick, end_tick, payload),
    do: module.build_from_event(start_tick, end_tick, payload)

  @doc "得到该片段自开始到 tick 刻的持续时间。"
  @spec tick_to_sec(Segment.segment(), Tick.t()) :: Segment.duration()
  def tick_to_sec(segment, tick) do
    impl(segment).tick_to_sec(segment, tick)
  end

  @doc "得到该片段的持续时间。"
  @spec duration_sec(Segment.segment()) :: Segment.duration()
  def duration_sec(segment) do
    impl(segment).duration_sec(segment)
  end

  @doc "得到该片段自开始某段时间所经过的 Tick 数。"
  @spec sec_to_tick(Segment.segment(), Timeline.physical_time()) :: Segment.duration()
  def sec_to_tick(segment, sec) do
    impl(segment).sec_to_tick(segment, sec)
  end

  # ---- 一些 Helpers ----

  defp impl(%module{}), do: module
  defp impl(module) when is_atom(module), do: module
end
