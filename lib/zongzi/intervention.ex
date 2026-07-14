defmodule Zongzi.Intervention do
  @moduledoc """
  对**上游已生成、且允许用户修改**的局部结果所挂的修改意图。

  ## 什么是 / 不是 Intervention

  **是**（模型或管线生成 → 用户可改 → 可挂锚与 snapshot）：

  - 曲线参数（pitch 等）：控制点 + 边界 + 原始值（原始值进 `snapshot`）
  - timing 偏移
  - **可编辑的 G2P 音素序列**（若产品允许用户改音素，则属 intervention，
    锚在 note / note 序列上，而不是「假装成全局旋钮」）

  **不是**（全局/音色类旋钮，不进本 struct）：

  - Gender、Energy、主音高等 **非生成式局部结果** 的参数  
  - 它们走引擎 `params` / 类型与范围检查（见 `Zongzi.Engine`），
    不做 Timeline 结构 rebase，也不做 snapshot 语义 conflict

  Intervention 描述「在某处（anchor）、对某通道（channel）、做某种偏移（payload）」。
  它不是渲染指令——**check** 时 resolve，**render** 时再物化为重产物。

  ## 两个判死时机

  - **编辑时（结构）** — `Anchor.Strategy`（默认 `NoteTriplet`）检查锚点邻接是否存活。
  - **check 时（语义）** — `Declaration.resolve` 比对 `snapshot` 与当前投影，apply / conflict。

  snapshot 优于输入指纹：改了歌词但 G2P 输出恰好相同不应判死；
  判死依据是「base 本身还在不在」，而非「产生 base 的输入变没变」。
  """

  alias Zongzi.Timeline.SeqID

  @type triplet :: {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}

  @type t :: %__MODULE__{
          id: term(),
          channel: atom(),
          anchor: triplet(),
          payload: term(),
          snapshot: term(),
          scope: term(),
          strategy: module() | nil
        }

  defstruct [
    :id,
    :channel,
    :anchor,
    :payload,
    :snapshot,
    :scope,
    strategy: nil
  ]
end
