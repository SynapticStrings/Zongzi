defmodule Zongzi.Anchor.NoteTriplet do
  @moduledoc """
  基于 NoteTriplet 的结构锚点策略。默认策略。

  三元组 `{prev_seq, current_seq, next_seq}` 锚定 intervention 在 Timeline 中的位置。
  rebase 是纯函数——只判结构死活，不碰 snapshot（语义有效性留给 render 时 resolve）。

  ## 决策表

  | current status | match | 输出 |
  |---|---|---|
  | active | 3/3 | `{:ok, :preserve}` |
  | active | 2/3 | `{:ok, {:rebase, updated}}` |
  | active | 1/3 | `{:conflict, :adjacency_lost}` |
  | merge_tombstone | — | `{:conflict, :merged_away}` |
  | delete_tombstone | — | relocate 到最近活跃邻居 |
  | missing | — | relocate or conflict |

  ## Context 键

  - `:orphan_direction` — `:prev` | `:next`，默认 `:next`
  """

  @behaviour Zongzi.Anchor.Strategy

  alias Zongzi.{Intervention, Timeline}
  alias Zongzi.Timeline.Query

  @impl true
  def rebase(intervention, tl, context \\ Zongzi.Anchor.Context.new())

  def rebase(
        %Intervention{anchor: {old_prev, current, old_next}} = int,
        %Timeline{} = tl,
        context
      ) do
    case Query.status(tl, current) do
      :missing ->
        do_relocate(int, tl, current, context)

      :merge_tombstone ->
        {:conflict, :merged_away}

      :delete_tombstone ->
        do_relocate(int, tl, current, context)

      :active ->
        # neighborhood returns raw neighbors from note_order (active_only: false)
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

        case match_count do
          3 -> {:ok, :preserve}
          2 -> {:ok, {:rebase, %{int | anchor: {new_prev, current, new_next}}}}
          _ -> {:conflict, :adjacency_lost}
        end
    end
  end

  defp do_relocate(int, tl, current, context) do
    direction = Map.get(context, :orphan_direction, :next)

    case Query.scan(tl, current, direction, active_only: true, limit: 1) do
      [nearest] ->
        case Query.scrub_triplet(tl, nearest) do
          {:ok, triplet} ->
            {:ok,
             {:relocate, %{int | anchor: triplet},
              %{from: current, to: nearest, method: :nearest_active}}}

          {:error, :not_active} ->
            {:conflict, :adjacency_lost}
        end

      [] ->
        {:conflict, :adjacency_lost}
    end
  end
end
