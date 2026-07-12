defmodule Zongzi.Curve.Adapter do
  @moduledoc """
  实现新的曲线适配器。

  ## 示例

      defmodule Foo do
        # 一般都存在状态
        use Zongzi.Curve.Adapter, keys: ...

        @impl Zongzi.Curve.Adapter
        def control_points(foo), do: ...
        @impl Zongzi.Curve.Adapter
        def span(foo), do: ...
        @impl Zongzi.Curve.Adapter
        def rasterize(foo, tick_seq), do: ...
      end

  ## 可编辑的曲线

      # 比方说控制点可变之类的
      # 整体平移（随着特定音符片段）
      # 什么什么的

  ## 栅格化的实现

  这里主要是用于参数的曲线在根据 Tempo 得到的 `tick_seq` 的采样点作为栅格化的单位/依据。

  所以这也是考虑 `Zongzi.Curve.Adapter.span/1` 回调的一个原因了。

  同时也要考虑只要一部分曲线拿来序列化的情况。

  关于这个名字，因为下游引擎所需要的一般是**基于物理时间的栅格化**的数据，
  所以我们还是把「栅格化」这个名字顺延过来了。
  """

  alias Zongzi.Curve.ControlPoint

  # ---- 如果这里需要一些业务函数的话，放在这 ----

  @doc "返回容器内的控制点列表，单位是 tick 。"
  @callback control_points(container :: struct()) :: [ControlPoint.t()]

  @doc "返回曲线的时间跨度（最后一个控制点的 tick 偏移）。空曲线返回 0。"
  @callback span(container :: struct()) :: non_neg_integer()

  @doc "按给定 tick 序列采样，返回 float-32-native 二进制。tick_seq 可以是 list 或 Range。"
  @callback rasterize(container :: struct(), tick_seq :: Enumerable.t(Zongzi.Score.Tick.t())) :: binary()
  # 后续 NIF 替换

  defmacro __using__(opts) do
    # 顺应 Zongzi.Util.Object 模块
    keys = Keyword.fetch!(opts, :keys)

    quote do
      use Zongzi.Util.Object, keys: unquote(keys)
      @behaviour Zongzi.Curve.Adapter
      alias Zongzi.Curve.ControlPoint
    end
  end
end
