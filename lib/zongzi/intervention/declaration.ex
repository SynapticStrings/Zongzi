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

  未来建议在 Declaration 契约加结构层钩子（`on_rebase/3`），
  让 channel 在 rebase 时自主切分/收缩 payload 边界。

  ## 三个回调的调用时机

  - `scope/2` — 切窗前（静态，保守上界）。不能依赖投影结果，否则切窗和渲染
    互相依赖产生死循环。像 preutterance 这种"实际溢出量要渲染后才知道"的，
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
  scope 声明也可用秒，切窗/换算时由 **Caller 或引擎** 转 tick。
  zongzi 核不强制 scope 单位；tick↔秒 转换留在库外（可用本库 TempoMap 工具）。
  """

  alias Zongzi.{Intervention, Timeline}

  @doc """
  声明 intervention 在 Timeline 上的作用范围（保守上界）。

  返回 `{start_tick, end_tick}`——窗口切分的最小单位。
  各 channel 的 scope 取并集得到最终渲染窗口。

  必须是静态可算的纯函数，不能依赖投影结果。
  """
  @callback scope(intervention :: Intervention.t(), timeline :: Timeline.t()) ::
              {Zongzi.Score.Tick.t(), Zongzi.Score.Tick.t()}

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

  @callback on_rebase(intervention :: Intervention.t(), meta :: term(), timeline :: Timeline.t()) ::
              {:ok, Intervention.t()}
              | {:conflict, term()}
              | {:split, children :: Enumerable.t(Intervention.t())}

  @optional_callbacks on_rebase: 3
end
