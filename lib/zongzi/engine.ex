defmodule Zongzi.Engine do
  @moduledoc """
  引擎契约：覆盖范围（whole / partial）× 任务（check / render）。

  zongzi 不跑引擎——只定 `@callback`。内部可以是 DAG、子进程、NIF，任意。

  ## 两个任务（artifact 分层）

  | 任务 | 成本 | 典型产出（check_artifact / render_artifact） |
  |---|---|---|
  | **check** | 轻 | 投影比对、`Declaration.resolve` 结果、semantic conflicts、类型/范围约束；**不是** final audio |
  | **render** | 重 | 可交付声学/全量特征等终态（或引擎定义的 final） |

  check 与 render **共用**同一套 Request / Slice；Windowing 不必为两任务切两次
  （除非 opts 里质量档不同）。

  ## 四个回调；除 `check_whole` 外均可选

  | | whole | partial |
  |---|---|---|
  | check | **必选** `check_whole/1` | 可选 `check_partial/1` |
  | render | 可选 `render_whole/1` | 可选 `render_partial/1` |

  - UTAU / 无 phrase cache：实现 `check_whole` + `render_whole` 即可。
  - 只预览语义、暂不出声：可只实现 check。
  - phrase 引擎：再实现 `*_partial`。
  - 未实现的 optional 回调：Host 不应调用；若误调，behaviour 编译期不强制，
    运行时由引擎模块自行 `def ... do {:error, :not_supported} end` 或省略。

  ## 循环

      rebase_all →（可选硬门：无结构 conflict）
        → Strategy.window → [Slice] | whole
        → check_*  → check_artifact（conflicts / resolved）
        → 用户决议（若有）
        → render_* → render_artifact（重）

  ## Request

  map 形，不强制 struct：

  - 公共：`notes` / `notes_by_seq`、`interventions`（结构存活集）、
    `tempo_segments`、`opts`、可选 `params`（见下）
  - partial：必填 `slices: [Windowing.Slice.t()]`

  ## 参数两类（与 Intervention 正交）

  1. **Intervention** — 模型（或上游管线）**生成的、用户可改** 的局部结果  
     （pitch 曲线、phoneme timing、可编辑 G2P 音素序列…）。走锚 + snapshot/resolve。
  2. **非 intervention 参数** — 全局/音色旋钮（Gender、Energy…）。  
     **不**走 Timeline 锚；check 时做类型与范围约束即可（可放 `opts` / `params`，
     由引擎自定 schema）。

  语义 conflict 属于 intervention 路径；参数非法属于 `{:error, {:invalid_param, _}}`
  一类引擎错误，不要伪装成 anchor conflict。
  """

  alias Zongzi.Windowing.Slice

  @typedoc "check 阶段产出：resolved / conflicts / 轻量投影引用等，非 final audio"
  @type check_artifact :: term()

  @typedoc "render 阶段产出：引擎定义的终态（音频、全量特征…）"
  @type render_artifact :: term()

  @type whole_request :: %{
          optional(:timeline) => term(),
          optional(:notes) => list(),
          optional(:notes_by_seq) => map(),
          optional(:interventions) => list(),
          optional(:tempo_segments) => term(),
          optional(:params) => map(),
          optional(:opts) => keyword() | map(),
          optional(any()) => any()
        }

  @type partial_request :: %{
          required(:slices) => [Slice.t()],
          optional(:notes) => list(),
          optional(:notes_by_seq) => map(),
          optional(:interventions) => list(),
          optional(:tempo_segments) => term(),
          optional(:params) => map(),
          optional(:opts) => keyword() | map(),
          optional(any()) => any()
        }

  @doc """
  整轨语义检查（轻）。

  投影 + 对 interventions 调 `Declaration.resolve`（或引擎等价物），
  并校验非 intervention 参数约束。返回 check_artifact，不是 final render。
  """
  @callback check_whole(whole_request()) :: {:ok, check_artifact()} | {:error, term()}

  @doc """
  按切片语义检查（轻）。`slices` 来自 `Windowing.Strategy.window/1`。
  """
  @callback check_partial(partial_request()) :: {:ok, check_artifact()} | {:error, term()}

  @doc """
  整轨重渲染（重）。可消费此前 check 的决议；产出 render_artifact。
  """
  @callback render_whole(whole_request()) :: {:ok, render_artifact()} | {:error, term()}

  @doc """
  按切片重渲染（重）。
  """
  @callback render_partial(partial_request()) :: {:ok, render_artifact()} | {:error, term()}

  @optional_callbacks [
    check_partial: 1,
    render_whole: 1,
    render_partial: 1
  ]
end
