defmodule Zongzi.Curve.Chunk do
  @moduledoc "一条曲线段"
  # adapter + container 模式，behaviour 回调直接在 adapter 模块上
  # container.points[].tick 为相对 start_tick 的偏移
  # end_tick 通过 adapter.span(container) + start_tick 按需计算，不存储

  alias Zongzi.Util.ID

  @type t :: %__MODULE__{
          id: ID.t(),
          adapter: module(),
          container: struct(),
          start_tick: non_neg_integer(),
          rasterized: term() | nil,
          extra: map()
        }
  use Zongzi.Util.Model,
    keys: [:id, :adapter, :container, :start_tick, rasterized: nil, extra: %{}],
    id_prefix: "CurveChunk_"
end
