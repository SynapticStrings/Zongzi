defmodule Zongzi.Intervention do
  @moduledoc """
  用户对渲染结果施加的局部修改。

  Intervention 描述"在某处（anchor）、对某通道（channel）、做某种偏移（payload）"。
  它不是渲染指令——渲染由引擎完成，Intervention 只声明意图。
  实际生效发生在引擎 render 时，由各 channel strategy 的 resolve 回调消费。

  ## 两个判死时机

  - **编辑时（结构）** — `Anchor.Strategy`（默认 `NoteTriplet`）检查锚点邻接是否存活。
  - **渲染时（语义）** — strategy 比对 `snapshot` 与当前投影输出，决定 apply / conflict。

  snapshot 方案优于输入指纹：改了歌词但 G2P 输出恰好相同不应判死，
  判死的依据是"base 本身还在不在"，而非"产生 base 的输入变没变"。
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
