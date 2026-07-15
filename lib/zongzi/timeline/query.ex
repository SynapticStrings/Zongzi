defmodule Zongzi.Timeline.Query do
  @moduledoc """
  纯读操作且无副作用的 Timeline 的查询原语。

  下游模块（如 Strategy 和 Windowing）使用这些原语来判定锚存活、选宿主、切窗口。

  ## 不变量

  格子状态 **仅** 由 `tombstones` 与 `seq_map` 两个 O(1) 查找判定。
  写操作保证：
  - insert 同时写 nodes 链表和 seq_map
  - gc 同时从 nodes 链表和 tombstones 移除
  因此不存在「链表里有但 tombstones 和 seq_map 都没有」的状态。
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

  @doc "获取给定 SeqID 的格子状态。O(1)。"
  @spec status(Timeline.t(), SeqID.t()) :: cell_status()
  def status(%Timeline{} = timeline, seq_id) do
    cond do
      MapSet.member?(timeline.tombstones, seq_id) ->
        if Map.has_key?(timeline.seq_map, seq_id), do: :merge_tombstone, else: :delete_tombstone

      Map.has_key?(timeline.seq_map, seq_id) ->
        :active

      true ->
        :missing
    end
  end

  @doc "是否为可承载锚点的活格子，仅在 `:active` 下返回真。"
  @spec active?(Timeline.t(), SeqID.t()) :: boolean()
  def active?(%Timeline{} = timeline, seq_id), do: status(timeline, seq_id) == :active

  @doc """
  有向扫描，返回候选 SeqID 列表（近→远）。

  ## Options
  - `:active_only` — 跳过墓碑（默认 `true`）
  - `:include_self` — 默认 `false`
  - `:limit` — 最多返回几个候选；`nil` 不限制
  - `:max_hops` — 最多跨几格（含墓碑格）
  """
  @spec scan(Timeline.t(), SeqID.t(), :prev | :next, keyword()) :: [SeqID.t()]
  def scan(%Timeline{} = timeline, seq_id, direction, opts \\ [])
      when direction in [:prev, :next] do
    active_only? = Keyword.get(opts, :active_only, true)
    include_self? = Keyword.get(opts, :include_self, false)
    limit = Keyword.get(opts, :limit)
    max_hops = Keyword.get(opts, :max_hops)

    unless Timeline.has_node?(timeline, seq_id) do
      []
    else
      self_part =
        if include_self? and pass_filter?(timeline, seq_id, active_only?), do: [seq_id], else: []

      walked = walk_dir(timeline, seq_id, direction, active_only?, max_hops, limit)

      (self_part ++ walked) |> take_limit_list(limit)
    end
  end

  @doc """
  焦点邻域。`count` 是每侧收集的格子数（不是格距半径）。
  默认 `count: 1, active_only: false` 可还原三元组邻居语义。
  """
  @spec neighborhood(Timeline.t(), SeqID.t(), keyword()) :: Neighborhood.t()
  def neighborhood(%Timeline{} = timeline, seq_id, opts \\ []) do
    count = Keyword.get(opts, :count, 1)
    active_only? = Keyword.get(opts, :active_only, false)
    focus_status = status(timeline, seq_id)

    unless Timeline.has_node?(timeline, seq_id) do
      %Neighborhood{focus: seq_id, focus_status: :missing, left: [], right: []}
    else
      left = collect_cells(timeline, seq_id, :prev, count, active_only?)
      right = collect_cells(timeline, seq_id, :next, count, active_only?)
      %Neighborhood{focus: seq_id, focus_status: focus_status, left: left, right: right}
    end
  end

  @doc """
  链表上两点格距（含墓碑格）。任一方不在链表中返回 error。O(k)，k=距离。
  """
  @spec hops(Timeline.t(), SeqID.t(), SeqID.t()) ::
          {:ok, non_neg_integer()} | {:error, :not_found}
  def hops(%Timeline{} = timeline, a, b) do
    unless Timeline.has_node?(timeline, a) and Timeline.has_node?(timeline, b) do
      {:error, :not_found}
    else
      # 尝试从 a 向 next 方向找 b
      case count_hops_forward(timeline, a, b, 0) do
        {:found, n} ->
          {:ok, n}

        :not_found ->
          # 反过来从 b 向 next 方向找 a
          case count_hops_forward(timeline, b, a, 0) do
            {:found, n} -> {:ok, n}
            :not_found -> {:error, :not_found}
          end
      end
    end
  end

  # ---- private helpers ----

  defp pass_filter?(timeline, seq_id, true), do: active?(timeline, seq_id)
  defp pass_filter?(_timeline, _seq_id, false), do: true

  defp take_limit_list(list, nil), do: list
  defp take_limit_list(list, n) when is_integer(n) and n >= 0, do: Enum.take(list, n)

  # 指针遍历：沿链表方向走，hop 从 1 起算
  defp walk_dir(_timeline, _from, _dir, _active_only?, max_hops, _limit)
       when is_integer(max_hops) and max_hops <= 0,
       do: []

  defp walk_dir(timeline, from, dir, active_only?, max_hops, limit) do
    do_walk_dir(timeline, from, dir, active_only?, max_hops, limit, [], 0)
  end

  defp do_walk_dir(timeline, from, dir, active_only?, max_hops, limit, acc, hop) do
    next = next_in_dir(timeline, from, dir)

    cond do
      is_nil(next) ->
        Enum.reverse(acc)

      is_integer(max_hops) and hop + 1 > max_hops ->
        Enum.reverse(acc)

      is_integer(limit) and length(acc) >= limit ->
        Enum.reverse(acc)

      pass_filter?(timeline, next, active_only?) ->
        do_walk_dir(timeline, next, dir, active_only?, max_hops, limit, [next | acc], hop + 1)

      true ->
        do_walk_dir(timeline, next, dir, active_only?, max_hops, limit, acc, hop + 1)
    end
  end

  defp next_in_dir(timeline, seq, :next), do: Timeline.node_next(timeline, seq)
  defp next_in_dir(timeline, seq, :prev), do: Timeline.node_prev(timeline, seq)

  # 收集邻域 cell：每侧收集 count 个
  defp collect_cells(timeline, from, dir, count, active_only?) do
    do_collect_cells(timeline, from, dir, count, active_only?, [], 0)
  end

  defp do_collect_cells(_timeline, _from, _dir, count, _active_only?, acc, n) when n >= count,
    do: Enum.reverse(acc)

  defp do_collect_cells(timeline, from, dir, count, active_only?, acc, n) do
    next = next_in_dir(timeline, from, dir)

    if is_nil(next) do
      Enum.reverse(acc)
    else
      st = status(timeline, next)

      if active_only? and st != :active do
        do_collect_cells(timeline, next, dir, count, active_only?, acc, n)
      else
        cell = %{
          seq_id: next,
          status: st,
          order_index: 0,
          hops_from_focus: n + 1
        }

        do_collect_cells(timeline, next, dir, count, active_only?, [cell | acc], n + 1)
      end
    end
  end

  # hops 计算：沿 next 方向走，数步数
  defp count_hops_forward(_timeline, nil, _target, _n), do: :not_found
  defp count_hops_forward(_timeline, target, target, n), do: {:found, n}

  defp count_hops_forward(timeline, current, target, n) do
    count_hops_forward(timeline, Timeline.node_next(timeline, current), target, n + 1)
  end
end
