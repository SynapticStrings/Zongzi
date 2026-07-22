defmodule Zongzi.Anchor.Strategy do
  @moduledoc """
  结构锚策略 behaviour。与 `Intervention.Declaration`（语义 snapshot/resolve）正交。

  ## 与 Declaration 的分界

  - Strategy.rebase — 锚还指得准吗？（结构存活，编辑时）
  - Declaration.resolve — base 还对得上 snapshot 吗？（语义有效，渲染/check 时）

  自定义结构策略禁止在 rebase 里做：比 pitch 曲线 snapshot、调引擎、应用 delta。
  最多读 Context 里的 Note 静态字段（key/lyric/tick）来选宿主。

  ## anchor 形状

  `Intervention.anchor` 是 `term()`——形状由本策略负责解释。
  默认 `NoteTriplet` 用 `{prev_seq | nil, current_seq, next_seq | nil}`。
  其他策略可定义自己的形状，必须实现 `referenced_seqs/1`
  以告知 gc 该 intervention 依赖哪些 SeqID。
  """

  alias Zongzi.{Intervention, Timeline, Anchor.Context}
  alias Zongzi.Timeline.SeqID

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

  第四参数 `opts` 为本策略专属配置（struct 或 map），
  由 `Intervention.strategy` 的 `{module(), opts}` 元组传入。
  不得做语义 snapshot 比对（那是 Declaration.resolve）。
  """
  @callback rebase(Intervention.t(), Timeline.t(), Context.t(), opts :: term()) :: decision()

  @doc """
  返回 intervention 锚所引用的全部 SeqID 集合。
  供 `Timeline.gc/2` 判定哪些墓碑仍被引用、不可回收。

  NoteTriplet 返回三元组的三个元素。
  """
  @callback referenced_seqs(Intervention.t()) :: [SeqID.t()]

  @doc """
  可选：从「已死/丢失」的 focus 选出新宿主。
  """
  @callback choose_host(
              focus :: SeqID.t() | nil,
              Timeline.t(),
              Context.t(),
              keyword()
            ) :: {:ok, SeqID.t(), map()} | {:conflict, reason()}

  @optional_callbacks [choose_host: 4]
end
