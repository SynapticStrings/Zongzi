defmodule Zongzi.Intervention.Declaration do
  @moduledoc """
  Intervention 的 channel strategy 契约。

  每个 channel（:pitch, :phoneme_timing, ...）实现此 behaviour，
  定义三件事：切多宽、原始值是什么、现在还能不能叠回去。

  ## Focus-split 载荷越界（Caveat，开放）

  Triplet rebase 只判点锚存活——如果 focus 被 split，锚的 2/3 匹配会成功，
  但 payload（曲线等）的 tick 区间可能已跨到子音符上。
  **结构 rebase 不检查这条**。暂由 Declaration.resolve 在 check 时
  通过 snapshot 兜底（snapshot 不对 → conflict）。

  已加结构层钩子 `on_rebase/4`，让 channel 在 rebase 时自主切分/收缩
  payload 边界。钩子会收到 Caller 注入的 `Anchor.Context`（含 `notes_by_seq`），
  declaration 可据此做 payload 的 tick 级维护。注意：`{:split, children}`
  的子干预不再过 strategy.rebase——**子干预锚的正确性由 declaration 负责**。

  ## 三个回调的调用时机

  - `scope/2` — 切窗前（静态，保守上界）。不依赖投影结果。
    第二参数为 `scope_ctx`（`%{timeline, tempo_map, tpqn}` 的 plain map），
    供秒级 channel 做 tick↔秒换算。返回 tagged tuple：
    `{tick, tick}` 或 `{:seconds, float, float}`。
    像 preutterance 这种"实际溢出量要渲染后才知道"的，
    只能声明引擎的 max preutterance 作为保守上界。
  - `snapshot/2` — 挂载时。从投影结果中提取这个 intervention 依赖的原始值，
    存入 `Intervention.snapshot`。
  - `resolve/2` — 渲染时。比对存储快照与当前投影，决定 apply 还是 conflict。

  ## snapshot-resolve 的比对语义

  比对要求投影确定性——同引擎同版本下，相同输入产生逐位可复现的投影。
  引擎/模型升级 = 全部快照失配 = conflict 风暴——这是显式接受的最坏情形，不是静默兼容。

  浮点比对不引入 tolerance（tolerance 就是 fuzzy match 的后门）。
  如有跨进程浮点漂移风险，在 snapshot 序列化时做 round-trip 归一化
  （如统一序列化为固定精度 decimal string），而非放宽比对。

  ## 时间单位

  intervention 的参数天然可能是秒（phoneme boundary 采样自音频）。
  scope 声明支持 tagged return：`{tick, tick}`（tick 基准，如 pitch）
  或 `{:seconds, float, float}`（秒基准，如 phoneme_timing）。
  Windowing 侧负责归一化：tick 直接用，`:seconds` 用 `scope_ctx.tempo_map`
  转 tick；缺 `tempo_map` 时返回 `{:error, :tempo_map_required}`。
  """

  alias Zongzi.{Intervention, Timeline}

  @typedoc """
  scope/2 的第二参数（plain map）。

  ## 字段

  - `:timeline` — `Timeline.t()`，必填
  - `:tempo_map` — `TempoMap.t() | nil`，秒级 channel 换算需要
  - `:tpqn` — `pos_integer()`，tick-per-quarter-note，默认 480
  """
  @type scope_ctx :: %{
          timeline: Timeline.t(),
          tempo_map: Zongzi.Score.TempoMap.t() | nil,
          tpqn: pos_integer()
        }

  @doc """
  声明 intervention 在 Timeline 上的作用范围（保守上界）。

  返回 tagged tuple：
  - `{start_tick, end_tick}` — tick 基准（如 pitch 曲线）
  - `{:seconds, start_sec, end_sec}` — 秒基准（如 phoneme boundary）

  各 channel 的 scope 取并集（归一化到 tick 后）得到最终渲染窗口。

  必须是静态可算的纯函数，不能依赖投影结果。
  """
  @callback scope(intervention :: Intervention.t(), scope_ctx :: scope_ctx()) ::
              {Zongzi.Score.Tick.t(), Zongzi.Score.Tick.t()}
              | {:seconds, float, float}

  @doc """
  从投影切片中提取此 intervention 依赖的原始值。

  挂载时调用。返回值存入 `Intervention.snapshot`，
  渲染时由 `resolve/2` 比对以判定语义有效性。

  提取逻辑 channel-dependent：
  - pitch 取锚点音符 start/end 处的基频值
  - phoneme_timing 取对应音素边界的秒值表
  """
  @callback snapshot(
              projection_slice :: term(),
              intervention :: Intervention.t()
            ) :: term()

  @doc """
  比对存储快照与当前投影，决定 intervention 是否仍可应用。

  渲染时调用。

  ## 返回值

  - `{:ok, resolved_artifact}` — 快照一致，delta 已应用到当前投影
  - `{:conflict, reason}` — 快照变了，base 已消失。保守默认是 conflict，
    某些 channel 可通过 strategy 旋钮允许 `:replay`（delta 重放到新 base 上并标记待复核）
  """
  @callback resolve(
              intervention :: Intervention.t(),
              fresh_projection :: term()
            ) :: {:ok, term()} | {:conflict, term()}

  # 用于结构化语境无变化但可能存在变化的情况
  # e.g. 修改 duration
  # 这些操作不会修改序列顺序，但是可能导致 intervention 边界发生变化
  #
  # meta 含 %{decision, old_anchor, new_anchor}（relocate 时并入 strategy 的 meta）；
  # context 为 Caller 注入 rebase_all 的 Anchor.Context（含 notes_by_seq），
  # 供 declaration 做 payload 的 tick 级维护。
  @callback on_rebase(
              intervention :: Intervention.t(),
              meta :: term(),
              timeline :: Timeline.t(),
              context :: Zongzi.Anchor.Context.t()
            ) ::
              {:ok, Intervention.t()}
              | {:conflict, term()}
              | {:split, children :: Enumerable.t(Intervention.t())}

  @optional_callbacks on_rebase: 4

  def supports_on_rebase?(mod) when is_atom(mod), do: function_exported?(mod, :on_rebase, 4)
  def supports_on_rebase?(_), do: false
end
