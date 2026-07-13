defmodule Zongzi.Timeline.Query do
  @moduledoc """
  Timeline 的查询原语。纯读操作，无副作用。

  Strategy 和 Windowing 层使用这些原语来判定锚存活、选宿主、切窗口。
  """

  alias Zongzi.Timeline
  alias Zongzi.Timeline.{SeqID, Neighborhood}

  @typedoc "格子状态"
  @type cell_status :: :active | :merge_tombstone | :delete_tombstone | :missing

  @doc """
  格子状态。策略用此区分 merge 墓碑 vs delete 墓碑，无需猜 seq_map。

  - `:active` — 在 order、非墓碑、seq_map 有条目
  - `:merge_tombstone` — 墓碑且 seq_map 仍有（merge 保留映射）
  - `:delete_tombstone` — 墓碑且 seq_map 已无
  - `:missing` — order 中不存在（已 gc 或从未插入）
  """
  @spec status(Timeline.t(), SeqID.t()) :: cell_status()
  def status(%Timeline{} = tl, seq_id) do
    cond do
      not Enum.member?(tl.note_order, seq_id) -> :missing
      MapSet.member?(tl.tombstones, seq_id) ->
        if Map.has_key?(tl.seq_map, seq_id), do: :merge_tombstone, else: :delete_tombstone
      Map.has_key?(tl.seq_map, seq_id) -> :active
      true -> :missing
    end
  end

  @doc "是否为可承载锚点的活格子。"
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
      {:error, _} -> []
      {:ok, idx} ->
        self_part =
          if include_self? and pass_filter?(tl, seq_id, active_only?),
            do: [seq_id], else: []
        walked = walk(tl, idx, direction, active_only?, max_hops, limit)
        take_limit(self_part ++ walked, limit)
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
        left = collect_cells(tl, idx, :prev, count, active_only?)
        right = collect_cells(tl, idx, :next, count, active_only?)
        %Neighborhood{focus: seq_id, focus_status: focus_status, left: left, right: right}
    end
  end

  @doc """
  将 focus 洗成「左右均为 active（或 nil）」的三元组。
  relocate 落地后写回 anchor 时使用。
  """
  @spec scrub_triplet(Timeline.t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}} | {:error, :not_active}
  def scrub_triplet(%Timeline{} = tl, focus) do
    if active?(tl, focus) do
      prev = case scan(tl, focus, :prev, active_only: true, limit: 1) do
               [p] -> p; [] -> nil end
      next_ = case scan(tl, focus, :next, active_only: true, limit: 1) do
                [n] -> n; [] -> nil end
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

  defp take_limit(list, nil), do: list
  defp take_limit(list, n) when is_integer(n) and n >= 0, do: Enum.take(list, n)

  defp walk(tl, idx, direction, active_only?, max_hops, limit) do
    order = tl.note_order
    len = length(order)
    range = case direction do
              :prev -> (idx - 1)..0//-1
              :next -> (idx + 1)..(len - 1)//1
            end

    {result, _hops} =
      Enum.reduce_while(range, {[], 0}, fn i, {acc, hops_count} ->
        hops_count = hops_count + 1
        cond do
          max_hops && hops_count > max_hops -> {:halt, {acc, hops_count}}
          limit && length(acc) >= limit -> {:halt, {acc, hops_count}}
          true ->
            sid = Enum.at(order, i)
            if pass_filter?(tl, sid, active_only?),
              do: {:cont, {[sid | acc], hops_count}},
              else: {:cont, {acc, hops_count}}
        end
      end)

    Enum.reverse(result)
  end

  defp collect_cells(tl, idx, direction, count, active_only?) do
    order = tl.note_order
    len = length(order)
    range = case direction do
              :prev -> (idx - 1)..0//-1
              :next -> (idx + 1)..(len - 1)//1
            end

    {result, _hops} =
      Enum.reduce_while(range, {[], 0}, fn i, {acc, hops_count} ->
        hops_count = hops_count + 1
        sid = Enum.at(order, i)
        st = status(tl, sid)
        cond do
          length(acc) >= count -> {:halt, {acc, hops_count}}
          active_only? and st != :active -> {:cont, {acc, hops_count}}
          st == :missing -> {:cont, {acc, hops_count}}
          true ->
            cell = %{seq_id: sid, status: st, order_index: i, hops_from_focus: hops_count}
            {:cont, {[cell | acc], hops_count}}
        end
      end)

    Enum.reverse(result)
  end
end
