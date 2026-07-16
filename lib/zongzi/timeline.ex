defmodule Zongzi.Timeline do
  @moduledoc """
  轨道序列真实源。双向链表实现。

  仅记录音符序列之间的相互关系

  独立于 Note 的生命周期——Note 被 split/merge/drag 后，
  Timeline 维护的 seq_id 序列始终反映最新的全序关系。

  ## 数据字段

  - `head` / `tail` — 链表首尾指针（nil 表示空链表）
  - `nodes` — `%{SeqID.t() => {prev :: SeqID.t() | nil, next :: SeqID.t() | nil}}`，双向链表
  - `seq_map` — seq_id → note_id 的反向查找
  - `tombstones` — 已删除的 seq_id，保留在链表中以维护邻接稳定性

  ## 更新记录的操作

  - 在末尾添加音符
  - 在序列的特定位置添加音符（基于目前存在的音符序列的位置）
  - 切开/合并特定音符
  - 可能需要变更音符排序的拖拽音符
  - 删除音符

  以上操作均指单个音符。

  ## 查询原语

  参见 `Zongzi.Timeline.Query` 模块。

  ## 复杂度

  - seq_id 相对操作（append/split/move）：O(1)
  - index 相对操作（insert_at/drag）：O(n) walk from head
  - 查询（neighborhood/scan）：O(k) 只访问需要的邻居数
  - gc：O(n) 遍历整条链
  """

  alias Zongzi.{Util.ID, Score.Note, Timeline.SeqID}

  @type t :: %__MODULE__{
          track_id: ID.t(),
          head: SeqID.t() | nil,
          tail: SeqID.t() | nil,
          nodes: %{SeqID.t() => {prev_seq_id :: SeqID.t() | nil, next_seq_id :: SeqID.t() | nil}},
          seq_map: %{SeqID.t() => ID.t(Note)},
          tombstones: MapSet.t(SeqID.t()),
          next_seq: pos_integer()
        }

  defstruct [
    :track_id,
    head: nil,
    tail: nil,
    nodes: %{},
    seq_map: %{},
    tombstones: MapSet.new(),
    next_seq: 1
  ]

  @doc """
  创建空 Timeline。

  ## 用例

      iex> new("Track-a")
      {:ok, %Timeline{track_id: "Track-a", next_seq: 1}}
  """
  def new(track_id) do
    {:ok, %__MODULE__{track_id: track_id, next_seq: 1}}
  end

  @doc """
  从序列化参数重建 Timeline。

  `note_order` → 链表，O(n)。

  ## 参数

    * `track_id` — 必填
    * `note_order` — `[SeqID.t()]`，有序列表（含墓碑）
    * `seq_map` — 可选，默认 `%{}`
    * `tombstones` — `[SeqID.t()]`，可选，默认 `[]`
    * `next_seq` — 可选，默认 `max(note_order) + 1`

  ## Examples

      iex> build(
      ...>   %{track_id: "t1", note_order: [],
      ...>   seq_map: %{}, tombstones: []})
      {:ok, %Timeline{track_id: "t1", next_seq: 1}}

      iex> build(
      ...>   %{track_id: "t1", note_order: [1, 2],
      ...>   seq_map: %{1 => "N_a", 2 => "N_b"}, tombstones: [2]})
      {:ok, %Timeline{
        track_id: "t1",
        head: 1, tail: 2,
        nodes: %{1 => {nil, 2}, 2 => {1, nil}},
        seq_map: %{1 => "N_a", 2 => "N_b"},
        tombstones: MapSet.new([2]), next_seq: 3}
      }
  """
  @spec build(%{
          required(:track_id) => ID.t(),
          required(:note_order) => [SeqID.t()],
          optional(:seq_map) => %{SeqID.t() => ID.t(Note)},
          optional(:tombstones) => [SeqID.t()],
          optional(:next_seq) => pos_integer()
        }) :: {:ok, t()}
  def build(%{track_id: track_id, note_order: order} = attrs) do
    seq_map = Map.get(attrs, :seq_map, %{})
    tombstones = attrs |> Map.get(:tombstones, []) |> MapSet.new()
    next_seq = Map.get(attrs, :next_seq, default_next(order))

    tl = %__MODULE__{
      track_id: track_id,
      seq_map: seq_map,
      tombstones: tombstones,
      next_seq: next_seq
    }

    tl = Enum.reduce(order, tl, fn seq_id, acc -> link_tail(acc, seq_id) end)
    {:ok, tl}
  end

  defp default_next([]), do: 1
  defp default_next(order), do: Enum.max(order) + 1

  @doc """
  返回完整 seq_id 列表（含墓碑）。
  """
  @spec to_list(t()) :: [SeqID.t()]
  def to_list(%__MODULE__{head: nil}), do: []

  def to_list(%__MODULE__{nodes: nodes, head: head}) do
    do_to_list(nodes, head, [])
  end

  # 递归遍历所有节点将下一个添加到列表
  defp do_to_list(_nodes, nil, acc), do: Enum.reverse(acc)

  defp do_to_list(nodes, seq, acc) do
    {_, nxt} = Map.fetch!(nodes, seq)
    do_to_list(nodes, nxt, [seq | acc])
  end

  @doc "给定 seq_id 是否在链表中。"
  @spec has_node?(t(), SeqID.t()) :: boolean()
  def has_node?(%__MODULE__{nodes: nodes}, seq_id), do: Map.has_key?(nodes, seq_id)

  @doc """
  基于 Timeline 自持的计数器生成新 SeqID。

  ## 用例

      iex> new("Track-a") |> elem(1) |> generate()
      {1, %Zongzi.Timeline{track_id: "Track-a", next_seq: 2}}

      iex> %Zongzi.Timeline{track_id: "Track-b", next_seq: 2} |> generate()
      {2, %Zongzi.Timeline{track_id: "Track-b", next_seq: 3}}
  """
  @spec generate(t()) :: {SeqID.t(), t()}
  def generate(%__MODULE__{next_seq: next} = timeline),
    do: {next, %__MODULE__{timeline | next_seq: next + 1}}

  # ---- 写操作（单个音符的 CRUD） ----

  @doc "将音符追加到 Timeline 末尾。"
  @spec insert_note(t(), Note.t()) :: {:ok, t(), Note.t()}
  def insert_note(%__MODULE__{} = timeline, %Note{} = note) do
    {seq_id, timeline} =
      if note.seq_id, do: {note.seq_id, timeline}, else: generate(timeline)

    note = %{note | seq_id: seq_id}
    timeline = %__MODULE__{timeline | seq_map: Map.put(timeline.seq_map, seq_id, note.id)}
    timeline = link_tail(timeline, seq_id)
    {:ok, timeline, note}
  end

  @doc "在 target_seq 之前插入音符。"
  @spec insert_note_before(t(), Note.t(), SeqID.t()) :: {:ok, t(), Note.t()} | {:error, term()}
  def insert_note_before(%__MODULE__{} = timeline, %Note{} = note, target_seq) do
    with :ok <- assert_has_node(timeline, target_seq) do
      {seq_id, timeline} = if note.seq_id, do: {note.seq_id, timeline}, else: generate(timeline)
      note = %{note | seq_id: seq_id}
      timeline = %__MODULE__{timeline | seq_map: Map.put(timeline.seq_map, seq_id, note.id)}
      timeline = link_before(timeline, seq_id, target_seq)
      {:ok, timeline, note}
    end
  end

  @doc "在 target_seq 之后插入音符。"
  @spec insert_note_after(t(), Note.t(), SeqID.t()) :: {:ok, t(), Note.t()} | {:error, term()}
  def insert_note_after(%__MODULE__{} = timeline, %Note{} = note, target_seq) do
    with :ok <- assert_has_node(timeline, target_seq) do
      {seq_id, timeline} = if note.seq_id, do: {note.seq_id, timeline}, else: generate(timeline)
      note = %{note | seq_id: seq_id}
      timeline = %__MODULE__{timeline | seq_map: Map.put(timeline.seq_map, seq_id, note.id)}
      timeline = link_after(timeline, seq_id, target_seq)
      {:ok, timeline, note}
    end
  end

  @doc """
  在 `split_tick` 处切开音符，返回前后两个 Note。

  后半音符自动分配新 seq_id 并 splice 到原音符后。
  """
  @spec split_note(t(), Note.t(), non_neg_integer(), ID.t(Note.t())) ::
          {:ok, t(), Note.t(), Note.t()} | {:error, term()}
  def split_note(%__MODULE__{} = timeline, %Note{} = note, split_tick, new_id) do
    seq_id = note.seq_id

    with :ok <- assert_has_node(timeline, seq_id),
         :ok <- assert_not_tombstone(timeline, seq_id),
         {:ok, before_note, after_note} <- Note.split(note, split_tick, new_id) do
      {new_seq, timeline} = generate(timeline)
      before_note = %{before_note | seq_id: seq_id}
      after_note = %{after_note | seq_id: new_seq}

      timeline =
        timeline
        |> link_after(new_seq, seq_id)
        |> then(&%{&1 | seq_map: Map.put(&1.seq_map, new_seq, &1.seq_map[seq_id])})

      {:ok, timeline, before_note, after_note}
    end
  end

  @doc """
  拖拽 seq 到 target_seq 的 before/after 位置。
  """
  @spec move_note(t(), selected_seq_id :: SeqID.t(), target_seq_id :: SeqID.t(), :before | :after) ::
          {:ok, t()} | {:error, term()}
  def move_note(%__MODULE__{} = timeline, seq_id, target_seq, where)
      when where in [:before, :after] do
    with :ok <- assert_not_tombstone(timeline, seq_id),
         :ok <- assert_has_node(timeline, seq_id),
         :ok <- assert_has_node(timeline, target_seq) do
      if seq_id == target_seq do
        {:ok, timeline}
      else
        timeline = unlink(timeline, seq_id)

        timeline =
          case where do
            :before -> link_before(timeline, seq_id, target_seq)
            :after -> link_after(timeline, seq_id, target_seq)
          end

        {:ok, timeline}
      end
    end
  end

  @doc """
  合并两个音符。内部调用 `Note.merge/4`。

  seq_id_2 变墓碑，seq_id_1 保留并指向 merged_note_id。
  """
  @spec merge_notes(t(), Note.t(), Note.t(), ID.t(Note.t())) ::
          {:ok, t(), Note.t()} | {:error, term()}
  def merge_notes(%__MODULE__{} = timeline, %Note{} = note_a, %Note{} = note_b, merged_id) do
    s1 = note_a.seq_id
    s2 = note_b.seq_id

    with :ok <- assert_has_node(timeline, s1),
         :ok <- assert_has_node(timeline, s2),
         :ok <- assert_not_tombstone(timeline, s1),
         :ok <- assert_not_tombstone(timeline, s2),
         {:ok, merged} <- Note.merge(note_a, note_b, merged_id) do
      merged = %{merged | seq_id: s1}

      timeline = %__MODULE__{
        timeline
        | seq_map: Map.put(timeline.seq_map, s1, merged_id),
          tombstones: MapSet.put(timeline.tombstones, s2)
      }

      {:ok, timeline, merged}
    end
  end

  @doc "删除 seq_id → 墓碑（保留在链表中以维护邻接稳定性）。"
  @spec delete_note(t(), SeqID.t()) :: {:ok, t()} | {:error, term()}
  def delete_note(%__MODULE__{} = timeline, seq_id) do
    with :ok <- assert_has_node(timeline, seq_id),
         :ok <- assert_not_tombstone(timeline, seq_id) do
      timeline = %__MODULE__{
        timeline
        | seq_map: Map.delete(timeline.seq_map, seq_id),
          tombstones: MapSet.put(timeline.tombstones, seq_id)
      }

      {:ok, timeline}
    end
  end

  # ---- 批量操作以及该用到的 ----

  # 批量增加音符的 SeqID
  defp generate_batch(timeline, 0), do: {[], timeline}

  defp generate_batch(%__MODULE__{} = timeline, count) do
    start = timeline.next_seq
    {Enum.to_list(start..(start + count - 1)), %{timeline | next_seq: start + count}}
  end

  # 纯 nodes map 操作（不依赖 struct 匹配）
  defp put_next_raw(nodes, seq_id, new_next) do
    {prv, _} = Map.fetch!(nodes, seq_id)
    Map.put(nodes, seq_id, {prv, new_next})
  end

  defp put_prev_raw(nodes, seq_id, new_prev) do
    {_, nxt} = Map.fetch!(nodes, seq_id)
    Map.put(nodes, seq_id, {new_prev, nxt})
  end

  # 从 seq_ids 列表构造相邻子链 nodes
  defp build_sub_chain([]), do: %{}

  defp build_sub_chain(seq_ids) do
    prevs = [nil | Enum.drop(seq_ids, -1)]
    nexts = Enum.drop(seq_ids, 1) ++ [nil]

    [seq_ids, prevs, nexts]
    |> Enum.zip()
    |> Enum.map(fn {sid, prv, nxt} -> {sid, {prv, nxt}} end)
    |> Map.new()
  end

  # 从 from 向 next 方向走到 to，收集经过的 seq_id
  defp collect_range(_nodes, current, to, acc) when current == to,
    do: {:ok, Enum.reverse([current | acc])}

  defp collect_range(nodes, current, to, acc) do
    {_, nxt} = Map.fetch!(nodes, current)

    if is_nil(nxt) do
      {:error, {:range_not_found, to}}
    else
      collect_range(nodes, nxt, to, [current | acc])
    end
  end

  @doc """
  批量 splice：把一组 notes 整体接到 target_seq 之后。O(n) 建子链 + O(1) splice。

  notes 按传入顺序依次链接，seq_id 自动分配。
  """
  @spec splice_after(t(), [Note.t()], SeqID.t()) :: {:ok, t(), [Note.t()]} | {:error, term()}
  def splice_after(%__MODULE__{} = timeline, [], _target_seq) do
    {:ok, timeline, []}
  end

  def splice_after(%__MODULE__{} = timeline, notes, target_seq) when is_list(notes) do
    with :ok <- assert_has_node(timeline, target_seq) do
      {seq_ids, timeline} = generate_batch(timeline, length(notes))

      notes_with_seq =
        Enum.zip(notes, seq_ids)
        |> Enum.map(fn {note, sid} -> %{note | seq_id: sid} end)

      # 构造子链 nodes
      sub_nodes = build_sub_chain(seq_ids)

      # 加入 seq_map
      seq_map =
        Enum.reduce(notes_with_seq, timeline.seq_map, fn n, acc ->
          Map.put(acc, n.seq_id, n.id)
        end)

      # splice: target_seq → first → ... → last → (old next)
      first = hd(seq_ids)
      last = List.last(seq_ids)
      {_, old_next} = Map.fetch!(timeline.nodes, target_seq)

      nodes =
        timeline.nodes
        |> Map.merge(sub_nodes)
        |> put_next_raw(target_seq, first)
        |> put_prev_raw(first, target_seq)

      nodes =
        if old_next do
          nodes |> put_next_raw(last, old_next) |> put_prev_raw(old_next, last)
        else
          nodes
        end

      tail = if old_next, do: timeline.tail, else: last

      {:ok, %{timeline | nodes: nodes, seq_map: seq_map, tail: tail}, notes_with_seq}
    end
  end

  @doc """
  批量删除 from_seq..to_seq 范围内的所有 seq_id（标记墓碑，不断链）。

  from_seq 必须链表中先于 to_seq（或相等）。
  """
  @spec delete_range(t(), SeqID.t(), SeqID.t()) :: {:ok, t()} | {:error, term()}
  def delete_range(%__MODULE__{} = timeline, from_seq, to_seq) do
    with :ok <- assert_has_node(timeline, from_seq),
         :ok <- assert_has_node(timeline, to_seq) do
      case collect_range(timeline.nodes, from_seq, to_seq, []) do
        {:ok, seq_ids} ->
          timeline =
            Enum.reduce(seq_ids, timeline, fn sid, acc ->
              %{
                acc
                | seq_map: Map.delete(acc.seq_map, sid),
                  tombstones: MapSet.put(acc.tombstones, sid)
              }
            end)

          {:ok, timeline}

        {:error, _} = err ->
          err
      end
    end
  end

  # ---- 内存回收 ----

  @doc "回收无 intervention 引用的墓碑，将其从链表中移除。"
  @spec gc(t(), [Zongzi.Intervention.t()]) :: t()
  def gc(%__MODULE__{} = timeline, interventions) do
    live_refs =
      interventions
      |> Enum.flat_map(& &1.declaration.referenced_seqs(&1))
      |> MapSet.new()

    unreachable = MapSet.difference(timeline.tombstones, live_refs)

    Enum.reduce(unreachable, timeline, fn seq, %__MODULE__{} = acc ->
      %__MODULE__{acc | tombstones: MapSet.delete(acc.tombstones, seq)}
      |> unlink(seq)
    end)
  end

  # ---- Query 用遍历原语 ----

  @doc "获得给定时间线下某 SeqID 的下一个 SeqID 。"
  @spec node_next(t(), SeqID.t()) :: SeqID.t() | nil
  def node_next(%__MODULE__{nodes: nodes}, seq_id) do
    case Map.fetch(nodes, seq_id) do
      {:ok, {_, next}} -> next
      :error -> nil
    end
  end

  @doc "获得给定时间线下某 SeqID 的上一个 SeqID 。"
  @spec node_prev(t(), SeqID.t()) :: SeqID.t() | nil
  def node_prev(%__MODULE__{nodes: nodes}, seq_id) do
    case Map.fetch(nodes, seq_id) do
      {:ok, {prev, _}} -> prev
      :error -> nil
    end
  end

  # ---- Private: 链表原语 ----

  defp link_tail(%__MODULE__{head: nil} = timeline, seq_id) do
    %__MODULE__{
      timeline
      | head: seq_id,
        tail: seq_id,
        nodes: Map.put(timeline.nodes, seq_id, {nil, nil})
    }
  end

  defp link_tail(%__MODULE__{tail: tail} = timeline, seq_id) do
    node = {tail, nil}
    timeline = %__MODULE__{timeline | nodes: Map.put(timeline.nodes, seq_id, node)}
    timeline = put_next(timeline, tail, seq_id)
    %__MODULE__{timeline | tail: seq_id}
  end

  defp link_after(%__MODULE__{} = timeline, seq_id, after_seq) do
    {_, nxt} = Map.fetch!(timeline.nodes, after_seq)
    node = {after_seq, nxt}
    timeline = %__MODULE__{timeline | nodes: Map.put(timeline.nodes, seq_id, node)}
    timeline = put_next(timeline, after_seq, seq_id)

    if nxt do
      put_prev(timeline, nxt, seq_id)
    else
      %__MODULE__{timeline | tail: seq_id}
    end
  end

  defp link_before(%__MODULE__{} = timeline, seq_id, before_seq) do
    {prv, _} = Map.fetch!(timeline.nodes, before_seq)
    node = {prv, before_seq}
    timeline = %__MODULE__{timeline | nodes: Map.put(timeline.nodes, seq_id, node)}
    timeline = put_prev(timeline, before_seq, seq_id)

    if prv do
      put_next(timeline, prv, seq_id)
    else
      %__MODULE__{timeline | head: seq_id}
    end
  end

  defp unlink(%__MODULE__{} = timeline, seq_id) do
    {prv, nxt} = Map.fetch!(timeline.nodes, seq_id)
    timeline = %__MODULE__{timeline | nodes: Map.delete(timeline.nodes, seq_id)}

    cond do
      prv && nxt ->
        timeline |> put_next(prv, nxt) |> put_prev(nxt, prv)

      prv ->
        %__MODULE__{put_next(timeline, prv, nil) | tail: prv}

      nxt ->
        %__MODULE__{put_prev(timeline, nxt, nil) | head: nxt}

      true ->
        %__MODULE__{timeline | head: nil, tail: nil}
    end
  end

  defp put_next(%__MODULE__{} = timeline, seq_id, new_next) do
    {prv, _} = Map.fetch!(timeline.nodes, seq_id)
    %__MODULE__{timeline | nodes: Map.put(timeline.nodes, seq_id, {prv, new_next})}
  end

  defp put_prev(%__MODULE__{} = timeline, seq_id, new_prev) do
    {_, nxt} = Map.fetch!(timeline.nodes, seq_id)
    %__MODULE__{timeline | nodes: Map.put(timeline.nodes, seq_id, {new_prev, nxt})}
  end

  defp assert_has_node(timeline, seq_id) do
    if has_node?(timeline, seq_id), do: :ok, else: {:error, {:not_found, seq_id}}
  end

  defp assert_not_tombstone(%__MODULE__{tombstones: ts}, seq_id) do
    if MapSet.member?(ts, seq_id), do: {:error, {:is_tombstone, seq_id}}, else: :ok
  end
end
