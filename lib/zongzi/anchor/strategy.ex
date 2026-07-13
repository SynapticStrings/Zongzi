defmodule Zongzi.Anchor.Strategy do
  @moduledoc """
  结构锚策略 behaviour。与 `Intervention.Declaration`（语义 snapshot/resolve）正交。

  ## 与 Declaration 的分界

  - Strategy.rebase — 锚还指得准吗？（结构存活，编辑时）
  - Declaration.resolve — base 还对得上 snapshot 吗？（语义有效，渲染时）

  自定义结构策略禁止在 rebase 里做：比 pitch 曲线 snapshot、调引擎、应用 delta。
  最多读 Context 里的 Note 静态字段（key/lyric/tick）来选宿主。
  """

  alias Zongzi.{Intervention, Timeline, Anchor.Context}

  @type reason ::
          :adjacency_lost
          | :merged_away
          | :no_host
          | :ambiguous_host
          | {:custom, term()}

  @type decision ::
          {:ok, :preserve}
          | {:ok, {:rebase, Intervention.t()}}
          | {:ok, {:relocate, Intervention.t(), meta :: map()}}
          | {:conflict, reason()}

  @doc """
  判定 intervention 的结构锚是否存活，必要时改写或重定位。

  不得做语义 snapshot 比对（那是 Declaration.resolve）。
  """
  @callback rebase(Intervention.t(), Timeline.t(), Context.t()) :: decision()

  @doc """
  可选：从「已死/丢失」的 focus 选出新宿主。
  默认策略可内联在 rebase 里；拆出来便于单测与复用。
  """
  @callback choose_host(
              focus :: Timeline.SeqID.t() | nil,
              Timeline.t(),
              Context.t(),
              keyword()
            ) :: {:ok, Timeline.SeqID.t(), map()} | {:conflict, reason()}

  @optional_callbacks [choose_host: 4]
end
