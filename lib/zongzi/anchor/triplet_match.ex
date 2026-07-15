defmodule Zongzi.Anchor.TripletMatch do
  @moduledoc """
  Triplet anchor 结构的**共享判定逻辑**（NoteTriplet 与 ScoredHost 共用）。
  """

  alias Zongzi.{Intervention, Timeline}
  alias Zongzi.Timeline.{Query, SeqID}

  @type triplet :: {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}

  @doc """
  使用当前三元组邻接与旧锚比对，返回 `match_count` 和新锚候选。

  返回值：
  - `{:active, match_count, {new_prev, current, new_next}}`
  - `{:tombstone, :merge | :delete}`
  - `{:tombstone, :delete, old_prev, old_next}` — delete tombstone hold legs
  - `{:conflict, reason}`
  """
  @spec match(Intervention.t(), Timeline.t()) ::
          {:active, pos_integer(), triplet()}
          | {:tombstone, :merge | :delete}
          | {:tombstone, :delete, SeqID.t() | nil, SeqID.t() | nil}
          | {:conflict, term()}
  def match(%Intervention{anchor: {old_prev, current, old_next}}, %Timeline{} = timeline) do
    case Query.status(timeline, current) do
      :missing ->
        {:tombstone, :delete, old_prev, old_next}

      :merge_tombstone ->
        {:tombstone, :merge}

      :delete_tombstone ->
        {:tombstone, :delete, old_prev, old_next}

      :active ->
        nb = Query.neighborhood(timeline, current, active_only: false, count: 1)

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
  @spec referenced_seqs(triplet()) :: [SeqID.t()]
  def referenced_seqs({a, b, c}), do: Enum.reject([a, b, c], &is_nil/1)

  @doc """
  将 focus 洗成「左右均为 active（或 nil）」的三元组。
  """
  @spec scrub_triplet(Timeline.t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}} | {:error, :not_active}
  def scrub_triplet(%Timeline{} = timeline, focus) do
    nb = Timeline.Query.neighborhood(timeline, focus, active_only: true, count: 1)

    if nb.focus_status == :active do
      prev =
        case nb.left do
          [%{seq_id: s}] -> s
          [] -> nil
        end

      next_ =
        case nb.right do
          [%{seq_id: s}] -> s
          [] -> nil
        end

      {:ok, {prev, focus, next_}}
    else
      {:error, :not_active}
    end
  end
end
