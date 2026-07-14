defmodule Zongzi.Anchor.TripletMatch do
  @moduledoc """
  Triplet anchor 结构的**共享判定逻辑**（NoteTriplet 与 ScoredHost 共用）。
  """

  alias Zongzi.{Intervention, Timeline}
  alias Zongzi.Timeline.{Query, SeqID}

  @doc """
  使用当前三元组邻接与旧锚比对，返回 `match_count` 和新锚候选。

  返回值：
  - `{:active, match_count, {new_prev, current, new_next}}`
  - `{:tombstone, :merge | :delete}`
  - `{:tombstone, :delete, old_prev, old_next}` — delete tombstone hold legs
  - `{:conflict, reason}`
  """
  @spec match(Intervention.t(), Timeline.t()) ::
          {:active, pos_integer(), {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}}
          | {:tombstone, :merge | :delete}
          | {:tombstone, :delete, SeqID.t() | nil, SeqID.t() | nil}
          | {:conflict, term()}
  @spec referenced_seqs({term() | nil, term(), term() | nil}) :: [term()]
  def match(%Intervention{anchor: {old_prev, current, old_next}}, %Timeline{} = tl) do
    case Query.status(tl, current) do
      :missing ->
        {:tombstone, :delete, old_prev, old_next}

      :merge_tombstone ->
        {:tombstone, :merge}

      :delete_tombstone ->
        {:tombstone, :delete, old_prev, old_next}

      :active ->
        nb = Query.neighborhood(tl, current, active_only: false, count: 1)

        new_prev =
          case nb.left do
            [%{seq_id: s}] -> s
            [] -> nil
          end

        new_next =
          case nb.right do
            [%{seq_id: s}] -> s
            [] -> nil
          end

        match_count =
          1 +
            if(old_prev == new_prev, do: 1, else: 0) +
            if old_next == new_next, do: 1, else: 0

        {:active, match_count, {new_prev, current, new_next}}
    end
  end

  @doc "三元组依赖的 SeqID 列表（gc 用）。"
  @spec referenced_seqs({SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}) :: [SeqID.t()]
  @spec referenced_seqs({term() | nil, term(), term() | nil}) :: [term()]
  def referenced_seqs({a, b, c}), do: Enum.reject([a, b, c], &is_nil/1)
end
