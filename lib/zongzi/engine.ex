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

  |      | check | render |
  |------|---|---|
  | 成本 | 轻 | 重 |
  | 产出 | `t:check_artifact` | `t:render_artifact` |
  | 必选 | 是 `check/1` | 否（`@optional_callbacks`） |
  | 入参 | `request()` | `checked_request()` — **不是裸 request** |

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
        → render(%{request: ..., artifact: ..., fingerprint: ...})   # 可选

  `check` 产出 `{:ok, check_artifact}` 后，由 Caller 与原始 `request` 及
  `fingerprint`（内容哈希 / revision 戳）**显式打包**为 `checked_request`
  再传给 `render`。`render` 实现**必须**校验指纹仍匹配——绝不用变异后的
  项目状态渲染旧 artifact。
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

  @typedoc """
  经 `check/1` 验证后的 request，显式捆上 artifact 与指纹。

  这消除了一条隐式缝：`render` 实现直接拿到「这是哪次 check 的产物」，
  不需要 Caller 暗中传递、引擎猜对应关系。
  """
  @type checked_request :: %{
          required(:request) => request(),
          required(:artifact) => check_artifact(),
          required(:fingerprint) => term()
        }

  @doc """
  语义与参数检查（轻）。

  对 `segments` 覆盖范围内的材料做投影比对 / `Declaration.resolve` /
  params 约束。返回 check_artifact，不是 final render。
  """
  @callback check(request()) :: {:ok, check_artifact()} | {:error, term()}

  @doc """
  重渲染（可选）。

  消费 `checked_request`——即经 `check/1` 验证后的 request + artifact +
  fingerprint。实现**必须**校验 `fingerprint` 与当前状态一致；若项目已在
  check 后被其他编辑修改，应拒绝而非静默产出过期音频。

  返回 `{:async, ref}` 时，Caller 负责管理 result delivery protocol
  （progress/ok/error/cancel），并拒收 fingerprint 已失效的迟到结果。
  """
  @callback render(checked_request()) ::
              {:ok, render_artifact()} | {:error, term()} | {:async, ref :: term()}

  @optional_callbacks [render: 1]

  def supports_render?(mod) when is_atom(mod), do: function_exported?(mod, :render, 1)
  def supports_render?(_), do: false
end
