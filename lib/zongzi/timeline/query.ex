defmodule Zongzi.Timeline.Query do
  @moduledoc """
  纯读操作且无副作用的 Timeline 的查询原语。

  下游模块（如 Strategy 和 Windowing）使用这些原语来判定锚存活、选宿主、切窗口。

  ## 不变量

  格子状态 **仅** 由 `tombstones` 与 `seq_map` 两个 O(1) 查找判定。
  写操作保证：
  - insert 同时写 `note_order` 和 `seq_map`
  - gc 同时从 `note_order` 和 `tombstones` 移除
  因此不存在「order 里有但 tombstones 和 seq_map 都没有」的状态。
  """

  alias Zongzi.Timeline
  alias Zongzi.Timeline.{SeqID, Neighborhood}

  @typedoc """
  格子状态。


  - `:active` — 非墓碑且 seq_map 有条目
  - `:merge_tombstone` — 墓碑且 seq_map 仍有（merge 保留映射）
  - `:delete_tombstone` — 墓碑且 seq_map 已无
  - `:missing` — 两表均无（已 gc 或从未插入）
  """
  @type cell_status :: :active | :merge_tombstone | :delete_tombstone | :missing

  @doc """
  获取给定 SeqID 的格子状态。

  仅用 tombstones + seq_map（复杂度 O(1)），不扫 note_order。
  """
  @spec status(Timeline.t(), SeqID.t()) :: cell_status()
  def status(%Timeline{} = tl, seq_id) do
    cond do
      MapSet.member?(tl.tombstones, seq_id) ->
        if Map.has_key?(tl.seq_map, seq_id), do: :merge_tombstone, else: :delete_tombstone

      Map.has_key?(tl.seq_map, seq_id) ->
        :active

      true ->
        :missing
    end
  end

  @doc "是否为可承载锚点的活格子，仅在 `:active` 下返回真。"
  @spec active?(Timeline.t(), SeqID.t()) :: boolean()
  def active?(%Timeline{} = tl, seq_id), do: status(tl, seq_id) == :active

  @doc """
  有向扫描，返回候选 SeqID 列表（近→远）。

  ## Options
  - `:active_only` — 跳过墓碑（默认 `true`）
  - `:include_self` — 默认 `false`
  - `:limit` — 最多返回几个；`nil` 不限制
  - `:max_hops` — 在 note_order 上最多跨几格（含墓碑格）
  """
  @spec scan(Timeline.t(), SeqID.t(), :prev | :next, keyword()) :: [SeqID.t()]
  def scan(%Timeline{} = tl, seq_id, direction, opts \\ [])
      when direction in [:prev, :next] do
    active_only? = Keyword.get(opts, :active_only, true)
    include_self? = Keyword.get(opts, :include_self, false)
    limit = Keyword.get(opts, :limit)
    max_hops = Keyword.get(opts, :max_hops)

    case Timeline.note_order_index(tl, seq_id) do
      {:error, _} ->
        []

      {:ok, idx} ->
        self_part =
          if include_self? and pass_filter?(tl, seq_id, active_only?), do: [seq_id], else: []

        # 先切列表再按格走，避免 Enum.at O(n²)
        walked =
          case direction do
            :next ->
              tl.note_order |> Enum.drop(idx + 1) |> walk_list(tl, active_only?, max_hops, limit)

            :prev ->
              tl.note_order
              |> Enum.take(idx)
              |> Enum.reverse()
              |> walk_list(tl, active_only?, max_hops, limit)
          end

        (self_part ++ walked) |> take_limit_list(limit)
    end
  end

  @doc """
  焦点邻域。`count` 是每侧收集的格子数（不是格距半径）。
  默认 `count: 1, active_only: false` 可还原三元组邻居语义。
  """
  @spec neighborhood(Timeline.t(), SeqID.t(), keyword()) :: Neighborhood.t()
  def neighborhood(%Timeline{} = tl, seq_id, opts \\ []) do
    count = Keyword.get(opts, :count, 1)
    active_only? = Keyword.get(opts, :active_only, false)
    focus_status = status(tl, seq_id)

    case Timeline.note_order_index(tl, seq_id) do
      {:error, _} ->
        %Neighborhood{focus: seq_id, focus_status: :missing, left: [], right: []}

      {:ok, idx} ->
        left =
          tl.note_order
          |> Enum.take(idx)
          |> Enum.reverse()
          |> collect_cells(tl, count, active_only?)

        right = tl.note_order |> Enum.drop(idx + 1) |> collect_cells(tl, count, active_only?)
        %Neighborhood{focus: seq_id, focus_status: focus_status, left: left, right: right}
    end
  end

  # scrub_triplet kept for backward compat; now delegates to neighborhood
  @doc """
  将 focus 洗成「左右均为 active（或 nil）」的三元组。
  """
  @spec scrub_triplet(Timeline.t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}} | {:error, :not_active}
  def scrub_triplet(%Timeline{} = tl, focus) do
    nb = neighborhood(tl, focus, active_only: true, count: 1)

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

  @doc """
  note_order 上两点格距（含墓碑格）。任一方不在 order 中返回 error。
  """
  @spec hops(Timeline.t(), SeqID.t(), SeqID.t()) ::
          {:ok, non_neg_integer()} | {:error, :not_found}
  def hops(%Timeline{} = tl, a, b) do
    with {:ok, i} <- Timeline.note_order_index(tl, a),
         {:ok, j} <- Timeline.note_order_index(tl, b) do
      {:ok, abs(i - j)}
    else
      _ -> {:error, :not_found}
    end
  end

  # ---- private helpers ----

  defp pass_filter?(tl, seq_id, true), do: active?(tl, seq_id)
  defp pass_filter?(_tl, _seq_id, false), do: true

  defp take_limit_list(list, nil), do: list
  defp take_limit_list(list, n) when is_integer(n) and n >= 0, do: Enum.take(list, n)

  # 列表走法：替代原先 Enum.at + range
  defp walk_list([], _tl, _active_only?, _max_hops, _limit), do: []

  defp walk_list(_list, _tl, _active_only?, max_hops, _limit)
       when is_integer(max_hops) and max_hops <= 0,
       do: []

  defp walk_list(list, tl, active_only?, max_hops, limit) when is_list(list) do
    {acc, _count} =
      Enum.reduce_while(Enum.with_index(list), {[], 0}, fn {sid, _grid_idx}, {acc, n} ->
        hops_count = n + 1

        cond do
          is_integer(max_hops) and hops_count > max_hops ->
            {:halt, {acc, n}}

          is_integer(limit) and n >= limit ->
            {:halt, {acc, n}}

          pass_filter?(tl, sid, active_only?) ->
            {:cont, {[sid | acc], n + 1}}

          true ->
            {:cont, {acc, n + 1}}
        end
      end)

    Enum.reverse(acc)
  end

  # 收集邻域 cell
  defp collect_cells(list, tl, count, active_only?) when is_list(list) do
    {result, _} =
      Enum.reduce_while(Enum.with_index(list), {[], 0}, fn {sid, grid_idx}, {acc, n} ->
        hops_count = n + 1

        cond do
          n >= count ->
            {:halt, {acc, n}}

          true ->
            st = status(tl, sid)

            if active_only? and st != :active do
              {:cont, {acc, n}}
            else
              cell = %{
                seq_id: sid,
                status: st,
                order_index: grid_idx,
                hops_from_focus: hops_count
              }

              {:cont, {[cell | acc], n + 1}}
            end
        end
      end)

    Enum.reverse(result)
  end
end
