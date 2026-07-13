defmodule Zongzi.Anchor.NoteTriplet do
  @moduledoc """
  基于 NoteTriplet 的结构锚点策略。

  三元组 `{prev_seq, current_seq, next_seq}` 锚定 intervention 在 Timeline 中的位置。
  rebase 是纯函数——只判结构死活，不碰 snapshot（语义有效性留给 render 时 resolve）。

  ## 决策表

  | Timeline.try_match | 输出 |
  |---|---|
  | `{:ok, 3}` | `{:ok, :preserve}` |
  | `{:ok, 2}` | `{:ok, {:rebase, updated_intervention}}` |
  | `{:ok, 0..1}` | `{:conflict, :adjacency_lost}` |
  | merge tombstone | `{:conflict, :merged_away}` |
  | delete tombstone / missing | `{:ok, {:relocate, int, meta}}` 或 conflict |

  ## Context 键

  - `:orphan_direction` — `:prev` | `:next`，默认 `:next`
  """

  @behaviour Zongzi.Anchor.Strategy

  alias Zongzi.{Intervention, Timeline, Anchor.Context}

  @impl true
  def rebase(intervention, tl, context \\ Context.new())

  def rebase(
        %Intervention{anchor: {_, current, _}} = intervention,
        %Timeline{} = tl,
        context
      ) do
    case Timeline.try_match(tl, intervention.anchor) do
      {:ok, 3} ->
        {:ok, :preserve}

      {:ok, 2} ->
        case Timeline.adjacent(tl, current) do
          {:ok, new_triplet} ->
            {:ok, {:rebase, %{intervention | anchor: new_triplet}}}

          _ ->
            {:conflict, :adjacency_lost}
        end

      {:ok, _} ->
        {:conflict, :adjacency_lost}

      {:tombstone, _} ->
        if Timeline.seq_map_has?(tl, current) do
          {:conflict, :merged_away}
        else
          do_relocate(intervention, tl, current, context)
        end

      {:error, :not_found} ->
        do_relocate(intervention, tl, current, context)
    end
  end

  defp do_relocate(intervention, tl, current, context) do
    direction = Map.get(context, :orphan_direction, :next)

    case Timeline.nearest_active(tl, current, direction) do
      {:ok, nearest} ->
        case Timeline.Query.scrub_triplet(tl, nearest) do
          {:ok, triplet} ->
            {:ok,
             {:relocate, %{intervention | anchor: triplet},
              %{from: current, to: nearest, method: :nearest_active}}}

          {:error, :not_active} ->
            {:conflict, :adjacency_lost}
        end

      {:error, :no_active_neighbor} ->
        {:conflict, :adjacency_lost}
    end
  end
end
