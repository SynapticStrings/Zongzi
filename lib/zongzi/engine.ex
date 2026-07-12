defmodule Zongzi.Engine do
  @moduledoc """
  引擎契约。

  zongzi 只定义契约和 rebase 纯逻辑。resolve（投影 + delta 合并）
  留给引擎/adapter 实现，与 ADR-010 rule 7 一致。

  ## 多轮循环

      # conflicts 上浮用户界面 ← rebase_all ← edit batch
      #       ↓
      #     render → artifact
      #       ↓
      # 挂新 intervention（adapt / modify / ...） → 作为新的 batch

  ## Request 字段

  - `notes` — 经 Timeline 排序的音符列表
  - `interventions` — rebase 后存活的 interventions（含 scope 声明）
  - `tempo_segments` — 渲染所需的 tempo map 片段
  - `opts` — 引擎特定选项（sample rate, frame shift 等）
  """

  alias Zongzi.{Intervention, Score.Note, Score.Tempo}

  @type request :: %__MODULE__{
          notes: [Note.t()],
          interventions: [Intervention.t()],
          tempo_segments: [Tempo.Segment.segment()],
          opts: keyword()
        }

  defstruct [
    :notes,
    :interventions,
    :tempo_segments,
    opts: []
  ]

  @type artifact :: term()

  @doc """
  执行一轮渲染。

  消费 request 中的 notes + interventions + tempo，
  产生引擎特定的 artifact（音频、参数序列、标注等）。

  resolve 在此回调内发生：
  1. 引擎生成投影
  2. 对每个 intervention 调 `Declaration.resolve/2`（snapshot 比对）
  3. 通过的 apply delta，失败的返回 conflict

  ## 返回值

  - `{:ok, artifact}` — 渲染成功，artifact 含最终输出 + resolve 结果
  - `{:error, reason}` — 渲染失败（引擎自身错误，不是 intervention conflict）
  """
  @callback render(request :: request()) :: {:ok, artifact()} | {:error, term()}
end
