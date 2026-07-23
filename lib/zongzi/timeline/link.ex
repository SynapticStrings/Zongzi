defmodule Zongzi.Timeline.Link do
  @moduledoc false
  # Link primitives with pure functions, no timeline struct
  #
  # All operations within `{head, tail, nodes}` triple

  alias Zongzi.Timeline.SeqID

  @type t ::
          {head :: SeqID.t() | nil, tail :: SeqID.t() | nil,
           nodes :: %{
             SeqID.t() => {prev_seq_id :: SeqID.t() | nil, next_seq_id :: SeqID.t() | nil}
           }}

  # ---- 链入 ----

  @doc "Append to link tail"
  def link_tail({nil, nil, nodes}, seq_id) do
    {seq_id, seq_id, Map.put(nodes, seq_id, {nil, nil})}
  end

  def link_tail({head, tail, nodes}, seq_id) do
    {head, seq_id, put_next(nodes, tail, seq_id) |> Map.put(seq_id, {tail, nil})}
  end

  @doc "在 after_seq 之后插入 seq_id。"
  def link_after({head, tail, nodes}, seq_id, after_seq) do
    {_, nxt} = Map.fetch!(nodes, after_seq)
    node = {after_seq, nxt}
    nodes = nodes |> Map.put(seq_id, node) |> put_next(after_seq, seq_id)

    if nxt do
      {head, tail, put_prev(nodes, nxt, seq_id)}
    else
      {head, seq_id, nodes}
    end
  end

  @doc "在 before_seq 之前插入 seq_id。"
  def link_before({head, tail, nodes}, seq_id, before_seq) do
    {prv, _} = Map.fetch!(nodes, before_seq)
    node = {prv, before_seq}
    nodes = nodes |> Map.put(seq_id, node) |> put_prev(before_seq, seq_id)

    if prv do
      {head, tail, put_next(nodes, prv, seq_id)}
    else
      {seq_id, tail, nodes}
    end
  end

  # ---- 摘链 ----

  @doc "从链表中摘除 seq_id（不删节点数据，只调整指针）。"
  def unlink({head, tail, nodes}, seq_id) do
    {prv, nxt} = Map.fetch!(nodes, seq_id)
    nodes = Map.delete(nodes, seq_id)

    cond do
      prv && nxt ->
        {head, tail, nodes |> put_next(prv, nxt) |> put_prev(nxt, prv)}

      prv ->
        {head, prv, put_next(nodes, prv, nil)}

      nxt ->
        {nxt, tail, put_prev(nodes, nxt, nil)}

      true ->
        {nil, nil, nodes}
    end
  end

  # ---- 指针更新 ----

  @doc "更新某节点的 next 指针。"
  def put_next(nodes, seq_id, new_next) do
    {prv, _} = Map.fetch!(nodes, seq_id)
    Map.put(nodes, seq_id, {prv, new_next})
  end

  @doc "更新某节点的 prev 指针。"
  def put_prev(nodes, seq_id, new_prev) do
    {_, nxt} = Map.fetch!(nodes, seq_id)
    Map.put(nodes, seq_id, {new_prev, nxt})
  end

  # ---- 子链构造 ----

  @doc """
  从有序 seq_id 列表构造相邻子链 nodes map。

  ## Examples

      iex> Zongzi.Timeline.Link.build_sub_chain([1, 2, 3])
      %{1 => {nil, 2}, 2 => {1, 3}, 3 => {2, nil}}
  """
  def build_sub_chain([]), do: %{}

  def build_sub_chain(seq_ids) do
    prevs = [nil | Enum.drop(seq_ids, -1)]
    nexts = Enum.drop(seq_ids, 1) ++ [nil]

    [seq_ids, prevs, nexts]
    |> Enum.zip()
    |> Enum.map(fn {sid, prv, nxt} -> {sid, {prv, nxt}} end)
    |> Map.new()
  end

  # ---- 范围收集 ----

  @doc """
  从 `from` 沿 next 方向遍历到 `to`，收集经过的 seq_id（含两端）。

  返回 `{:ok, [seq_ids]}` 或 `{:error, {:range_not_found, to}}`。
  """
  @spec collect_range(
          nodes :: %{SeqID.t() => {SeqID.t() | nil, SeqID.t() | nil}},
          from :: SeqID.t(),
          to :: SeqID.t()
        ) :: {:ok, [SeqID.t()]} | {:error, {:range_not_found, SeqID.t()}}
  def collect_range(nodes, from, to) do
    do_collect_range(nodes, from, to, [])
  end

  defp do_collect_range(_nodes, current, to, acc) when current == to,
    do: {:ok, Enum.reverse([current | acc])}

  defp do_collect_range(nodes, current, to, acc) do
    {_, nxt} = Map.fetch!(nodes, current)

    if is_nil(nxt) do
      {:error, {:range_not_found, to}}
    else
      do_collect_range(nodes, nxt, to, [current | acc])
    end
  end
end
