defmodule Zongzi.Engine do
  @moduledoc """
  引擎契约 facade：任务只有两档——**check**（轻）与 **render**（重）。

  覆盖范围不设 whole/partial 回调：请求里**一律**带
  `segments: [Windowing.Segment.t()]`。

  - 整轨 / 无 phrase cache：`WholeTrack.window/1` → 通常 **一个** Segment
  - 乐句切开：`RestSplit3Beats` 等 → **多个** Segment

  引擎实现只消费 Segment 列表（及 notes / interventions / params），
  **不** import Windowing 模块，也**不**直接改 Timeline。

  ## check vs render

  | | check | render |
  |---|---|---|
  | 成本 | 轻 | 重 |
  | 产出 | check_artifact：resolve、semantic conflicts、params 约束 | render_artifact：终态声学/全量特征等 |
  | 必选 | **是** `check/1` | 否（`@optional_callbacks`） |

  ## Request

  map 形，不强制 struct：

  - **必填** `segments` — 至少可为 `[]`；UTAU 友好路径多为 length 1
  - 常用：`notes` / `notes_by_seq`、`interventions`（结构存活集）、
    `params`（Gender/Energy 等，非 intervention）、`tempo_segments`、`opts`

  ## 参数两类

  1. **Intervention** — 可改的上游生成结果（曲线 / timing / 可编辑 G2P…）
  2. **params** — 非锚旋钮；check 做类型/范围校验

  ## 循环

      rebase_all → Strategy.window → [Segment]
        → check(%{segments: ..., interventions: ..., params: ...})
        →（用户决议）
        → render(%{segments: ..., ...})   # 可选
  """

  alias Zongzi.Windowing.Segment

  @typedoc "check 阶段产出：非 final audio"
  @type check_artifact :: term()

  @typedoc "render 阶段产出：引擎定义的终态"
  @type render_artifact :: term()

  @type request :: %{
          required(:segments) => [Segment.t()],
          optional(:timeline) => term(),
          optional(:notes) => list(),
          optional(:notes_by_seq) => map(),
          optional(:interventions) => list(),
          optional(:tempo_segments) => term(),
          optional(:params) => map(),
          optional(:opts) => keyword() | map(),
          optional(any()) => any()
        }

  @doc """
  语义与参数检查（轻）。

  对 `segments` 覆盖范围内的材料做投影比对 / `Declaration.resolve` /
  params 约束。返回 check_artifact，不是 final render。
  """
  @callback check(request()) :: {:ok, check_artifact()} | {:error, term()}

  @doc """
  重渲染（可选）。消费同一套 `segments`（及已决议的 interventions）。
  """
  @callback render(request()) ::
              {:ok, render_artifact()} | {:error, term()} | {:async, ref :: term()}

  @optional_callbacks [render: 1]

  def supports_render?(mod) when is_atom(mod), do: function_exported?(mod, :render, 1)
  def supports_render?(_), do: false
end
