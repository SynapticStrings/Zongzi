defmodule Zongzi.Intervention.Declaration do
  @moduledoc """
  Intervention 的 channel strategy 契约。

  每个 channel（:pitch, :phoneme_timing, ...）实现此 behaviour，
  定义三件事：切多宽、原始值是什么、现在还能不能叠回去。

  ## 三个回调的调用时机

  - `scope/2` — 切窗前（静态，保守上界）。不能依赖投影结果，否则切窗和渲染
    互相依赖产生死循环。像 preutterance 这种"实际溢出量要渲染后才知道"的，
    只能声明引擎的 max preutterance 作为保守上界。
  - `snapshot/2` — 挂载时。从投影结果中提取这个 intervention 依赖的原始值，
    存入 `Intervention.snapshot`。
  - `resolve/2` — 渲染时。比对存储快照与当前投影，决定 apply 还是 conflict。

  ## snapshot-resolve 的比对语义

  比对要求投影确定性——同引擎同版本下，相同输入产生逐位可复现的投影。
  引擎升级 = 全部快照失配 = conflict 风暴，这是 ADR-012 声明的显式最坏情形。

  浮点比对不引入 tolerance（tolerance 就是 fuzzy match 的后门）。
  如有跨进程浮点漂移风险，在 snapshot 序列化时做 round-trip 归一化
  （如统一序列化为固定精度 decimal string），而非放宽比对。

  ## 时间单位

  intervention 的参数天然可能是秒（phoneme boundary 采样自音频）。
  scope 声明也可用秒，切窗时由调用方（equinox NIF / 前端）转 tick。
  zongzi 不持有 tempo map 依赖——tick↔秒 转换留在 zongzi 外。
  """

  alias Zongzi.{Intervention, Timeline}

  @doc """
  声明 intervention 在 Timeline 上的作用范围（保守上界）。

  返回 `{start_tick, end_tick}`——窗口切分的最小单位。
  各 channel 的 scope 取并集得到最终渲染窗口。

  必须是静态可算的纯函数，不能依赖投影结果。
  """
  @callback scope(intervention :: Intervention.t(), timeline :: Timeline.t()) ::
              {Timeline.Tick.t(), Timeline.Tick.t()}

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
end
