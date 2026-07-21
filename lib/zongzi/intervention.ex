defmodule Zongzi.Intervention do
  @moduledoc """
  对上游已生成、且允许用户修改的局部结果所挂的修改意图。

  > 我认领序列上的某个可指称位置 L；
  > 当 Timeline 从 T₀ 变成 T₁ 时，
  > 请策略 f 决定：L 仍有效 | 更新为 L′ | 冲突。

  ## 定义与约束

  **是**（模型或管线生成 → 用户可改 → 可挂锚与 snapshot）：

  - 曲线参数（pitch 等）：控制点 + 边界 + 原始值（原始值进 `snapshot`）
  - timing 偏移
  - **可编辑的 G2P 音素序列**（若产品允许用户改音素，则属 intervention，
    锚在 note / note 序列上，而不是「假装成全局旋钮」）

  **不是**（全局/音色类旋钮，不进本 struct）：

  - Gender、Energy、气声等 **非生成式局部结果** 的参数
  - 它们走引擎 `params` / 类型与范围检查（见 `Zongzi.Engine`），
    不做 Timeline 结构 rebase，也不做 snapshot 语义 conflict

  ## 锚（anchor）

  `anchor` 是 `term()`——形状由挂载它的 `Anchor.Strategy` 定义。
  默认策略 `NoteTriplet` 使用 `{prev_seq | nil, current_seq, next_seq | nil}`。
  其他策略（identity 锚、span 锚等）使用自己的形状，
  通过 `Strategy.referenced_seqs/1` 声明依赖的 SeqID 集合。

  ## 两个判死时机

  - **编辑时（结构）** — `Anchor.Strategy` 检查锚点是否存活。
  - **check 时（语义）** — `Declaration.resolve` 比对 `snapshot` 与当前投影，apply / conflict。

  snapshot 优于输入指纹：改了歌词但 G2P 输出恰好相同不应判死；
  判死依据是「base 本身还在不在」，而非「产生 base 的输入变没变」。
  """

  @type t :: %__MODULE__{
          id: term(),
          channel: atom(),
          anchor: term(),
          payload: term(),
          snapshot: term(),
          scope: term(),
          strategy: {module(), options :: term()} | nil,
          declaration: module()
        }

  defstruct [
    :id,
    :channel,
    :anchor,
    :payload,
    :snapshot,
    :scope,
    strategy: nil,
    declaration: nil
  ]
end
