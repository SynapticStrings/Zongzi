defmodule Zongzi.Anchor.NoteTriplet do
  @moduledoc """
  基于 NoteTriplet 的结构锚点 rebase。

  三元组 `{prev_seq, current_seq, next_seq}` 锚定 intervention 在 Timeline 中的位置。
  rebase 是纯函数——只判结构死活，不碰 snapshot（语义有效性留给 render 时 resolve）。
  """

  alias Zongzi.{Intervention, Timeline}

  @doc """
  将 intervention 的锚点 rebase 到当前 Timeline。

  ## 参数

  - `intervention` — 待 rebase 的 intervention
  - `tl` — 当前 Timeline
  - `orphan_direction` — 当 anchor seq_id 不在 Timeline 时（:not_found），
    向哪个方向找最近活跃邻居重新锚定。由 channel strategy 决定
    （如 pitch 向前找，phoneme offset 向后找）。默认 `:next`。

  ## 返回值

  | Timeline.try_match | rebase 输出 |
  |---|---|
  | `{:ok, 3}` | `{:ok, :preserve}` |
  | `{:ok, 2}` | `{:ok, {:rebase, updated_intervention}}` |
  | `{:ok, 0..1}` | `{:conflict, :adjacency_lost}` |
  | `{:tombstone, _}` | `{:push, nearest_seq_id, updated_intervention}` |
  | `{:error, :not_found}` | `{:push, nearest_seq_id, updated_intervention}` |
  """
  @spec rebase(Intervention.t(), Timeline.t(), :prev | :next) ::
          {:ok, :preserve}
          | {:ok, {:rebase, Intervention.t()}}
          | {:conflict, :adjacency_lost | :merged_away}
          | {:push, Timeline.SeqID.t(), Intervention.t()}
  def rebase(intervention, tl, orphan_direction \\ :next)

  def rebase(
        %Intervention{anchor: {_, current, _}} = intervention,
        %Timeline{} = tl,
        orphan_direction
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
        # merge 保留 seq_map 条目；delete 移除 → 以此区分
        if Timeline.seq_map_has?(tl, current) do
          {:conflict, :merged_away}
        else
          do_orphan_push(intervention, tl, current, orphan_direction)
        end

      {:error, :not_found} ->
        do_orphan_push(intervention, tl, current, orphan_direction)
    end
  end

  defp do_orphan_push(intervention, tl, current, direction) do
    case Timeline.nearest_active(tl, current, direction) do
      {:ok, nearest} ->
        # 构建无墓碑的干净三元组
        prev = clean_neighbor(tl, nearest, :prev)
        next_ = clean_neighbor(tl, nearest, :next)
        {:push, nearest, %{intervention | anchor: {prev, nearest, next_}}}

      {:error, :no_active_neighbor} ->
        {:conflict, :adjacency_lost}
    end
  end

  defp clean_neighbor(tl, seq_id, dir) do
    case Timeline.nearest_active(tl, seq_id, dir) do
      {:ok, neighbor} -> neighbor
      {:error, :no_active_neighbor} -> nil
    end
  end
end
