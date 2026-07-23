defmodule Zongzi.Timeline do
  @moduledoc """
  The source of truth of the note sequences, only records the relationships between them.

  Implemented using a doubly linked list.

  独立于 Note 的生命周期——Note 被 split/merge/drag 后，
  Timeline 维护的 seq_id 序列始终反映最新的全序关系。

  ## Data Fields

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

  针对批量操作：

  - 批量在末尾添加
  - 批量在某音符前/后插入一堆音符
  - 批量删除一堆音符

  ## 查询原语

  参见 `Zongzi.Timeline.Query` 模块。

  ## Caller Related

  Timeline not contain Note.
  写操作后 Caller 侧 note 快照（notes_by_seq）的同步需要单独实现。
  """

  alias Zongzi.{Util.ID, Score.Note}
  alias Zongzi.Timeline.{SeqID, Link, Validator}

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
  Create blank Timeline.

  ## Examples

      iex> Timeline.new("Track-a")
      {:ok, %Timeline{track_id: "Track-a", next_seq: 1}}
  """
  def new(track_id) do
    {:ok, %__MODULE__{track_id: track_id, next_seq: 1}}
  end

  @doc """
  Rebuild Timeline within serialized arguments.

  `note_order` → 链表，O(n)。

  ## Attributes

    * `track_id` - Required
    * `note_order` - `[SeqID.t()]`，有序列表（含墓碑）
    * `seq_map` — 可选，默认 `%{}`
    * `tombstones` — `[SeqID.t()]`，可选，默认 `[]`
    * `next_seq` — 可选，默认 `max(note_order) + 1`

  ## Examples

      iex> Timeline.build(
      ...>   %{track_id: "t1", note_order: [],
      ...>   seq_map: %{}, tombstones: []})
      {:ok, %Timeline{track_id: "t1", next_seq: 1}}

      iex> Timeline.build(
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
    init_tl = %__MODULE__{
      track_id: track_id,
      seq_map: Map.get(attrs, :seq_map, %{}),
      tombstones: Map.get(attrs, :tombstones, []) |> MapSet.new(),
      next_seq: Map.get(attrs, :next_seq, default_next(order))
    }

    {:ok,
     Enum.reduce(order, init_tl, fn seq_id, tl -> unlink(tl, &Link.link_tail(&1, seq_id)) end)}
  end

  defp default_next([]), do: 1
  defp default_next(order), do: Enum.max(order) + 1

  @doc "返回完整 seq_id 列表（含墓碑）。"
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

  @doc "获得给定 SeqID 的 NoteID 。"
  @spec note_id_for(t(), SeqID.t()) :: {:ok, ID.t(Note.t())} | :error
  def note_id_for(%__MODULE__{seq_map: seq_map}, seq_id), do: Map.fetch(seq_map, seq_id)

  @doc """
  基于 Timeline 自持的计数器生成新 SeqID。

  ## Examples

      iex> Timeline.new("Track-a") |> elem(1) |> Timeline.generate()
      {1, %Zongzi.Timeline{track_id: "Track-a", next_seq: 2}}

      iex> %Zongzi.Timeline{track_id: "Track-b", next_seq: 2} |> Timeline.generate()
      {2, %Zongzi.Timeline{track_id: "Track-b", next_seq: 3}}
  """
  @spec generate(t()) :: {SeqID.t(), t()}
  def generate(%__MODULE__{next_seq: next} = timeline),
    do: {next, %__MODULE__{timeline | next_seq: next + 1}}

  @doc "Validate Timeline."
  defdelegate validate(timeline), to: Validator

  # ---- 写操作（单个音符的 CRUD） ----

  @doc "将音符追加到 Timeline 末尾。"
  @spec insert_note(t(), Note.t()) :: {:ok, t(), Note.t()} | {:error, term()}
  def insert_note(%__MODULE__{} = timeline, %Note{} = note) do
    with {:ok, timeline, note, seq_id} <- update_timeline(timeline, note) do
      {:ok, unlink(timeline, &Link.link_tail(&1, seq_id)), note}
    end
  end

  @doc "在 target_seq 之前插入音符。"
  @spec insert_note_before(t(), Note.t(), SeqID.t()) :: {:ok, t(), Note.t()} | {:error, term()}
  def insert_note_before(%__MODULE__{} = timeline, %Note{} = note, target_seq) do
    with :ok <- assert_has_node(timeline, target_seq),
         {:ok, timeline, note, seq_id} <- update_timeline(timeline, note) do
      {:ok, unlink(timeline, &Link.link_before(&1, seq_id, target_seq)), note}
    end
  end

  @doc "在 target_seq 之后插入音符。"
  @spec insert_note_after(t(), Note.t(), SeqID.t()) :: {:ok, t(), Note.t()} | {:error, term()}
  def insert_note_after(%__MODULE__{} = timeline, %Note{} = note, target_seq) do
    with :ok <- assert_has_node(timeline, target_seq),
         {:ok, timeline, note, seq_id} <- update_timeline(timeline, note) do
      {:ok, unlink(timeline, &Link.link_after(&1, seq_id, target_seq)), note}
    end
  end

  # 不放后面了，就前面几个函数会被用到
  # 确保永远单调递增
  defp update_timeline(%__MODULE__{} = timeline, %Note{} = note) do
    cond do
      is_nil(note.seq_id) ->
        put_new(timeline, timeline.next_seq, note)

      note.seq_id >= timeline.next_seq ->
        put_new(timeline, note.seq_id, note)

      true ->
        {:error, {:seq_id_reused, note.seq_id, timeline.next_seq}}
    end
  end

  defp put_new(%__MODULE__{} = timeline, seq_id, note) do
    {:ok,
     %{
       timeline
       | next_seq: seq_id + 1,
         seq_map: Map.put(timeline.seq_map, seq_id, note.id)
     }, %{note | seq_id: seq_id}, seq_id}
  end

  @doc """
  在 `split_tick` 处切开音符，返回前后两个 Note。

  后半音符自动分配新 seq_id 并 splice 到原音符后。
  `attrs` 可选，透传给 `Note.split/4`（如给后半音符不同的 lyric）。
  """
  @spec split_note(t(), Note.t(), non_neg_integer(), ID.t(Note.t()), map() | keyword()) ::
          {:ok, t(), Note.t(), Note.t()} | {:error, term()}
  def split_note(%__MODULE__{} = timeline, %Note{} = note, split_tick, new_id, attrs \\ []) do
    seq_id = note.seq_id

    with :ok <- assert_has_node(timeline, seq_id),
         :ok <- assert_not_tombstone(timeline, seq_id),
         {:ok, before_note, after_note} <- Note.split(note, split_tick, new_id, attrs) do
      {new_seq, timeline} = generate(timeline)
      before_note = %{before_note | seq_id: seq_id}
      after_note = %{after_note | seq_id: new_seq}

      {head, tail, nodes} =
        Link.link_after({timeline.head, timeline.tail, timeline.nodes}, new_seq, seq_id)

      timeline = %{
        timeline
        | head: head,
          tail: tail,
          nodes: nodes,
          seq_map: Map.put(timeline.seq_map, new_seq, new_id)
      }

      {:ok, timeline, before_note, after_note}
    end
  end

  @doc "拖拽 seq 到 target_seq 的 before/after 位置。"
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
        {:ok,
         unlink(timeline, fn link_tuple ->
           Link.unlink(link_tuple, seq_id)
           |> then(
             &case where do
               :before -> Link.link_before(&1, seq_id, target_seq)
               :after -> Link.link_after(&1, seq_id, target_seq)
             end
           )
         end)}
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
      sub_nodes = Link.build_sub_chain(seq_ids)

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
        |> Link.put_next(target_seq, first)
        |> Link.put_prev(first, target_seq)

      nodes =
        if old_next do
          nodes |> Link.put_next(last, old_next) |> Link.put_prev(old_next, last)
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
      case Link.collect_range(timeline.nodes, from_seq, to_seq) do
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

  @doc """
  回收无 intervention 引用的墓碑，将其从链表中移除。

  引用判定走各 intervention 的 `Anchor.Strategy.referenced_seqs/1`
  （strategy 为 nil 时回退 `NoteTriplet`）。

  extra_refs 是为了使 undo 可用。
  """
  @spec gc(t(), [Zongzi.Intervention.t()]) :: {:ok, t()}
  def gc(%__MODULE__{} = timeline, interventions, extra_refs \\ []) do
    live_refs =
      interventions
      |> Enum.flat_map(fn int ->
        {strategy_mod, _opts} = int.strategy || {Zongzi.Anchor.NoteTriplet, %{}}
        strategy_mod.referenced_seqs(int)
      end)
      |> then(&(&1 ++ extra_refs))
      |> MapSet.new()

    unreachable = MapSet.difference(timeline.tombstones, live_refs)

    timeline =
      Enum.reduce(unreachable, timeline, fn seq, %__MODULE__{} = acc ->
        acc = %__MODULE__{
          acc
          | tombstones: MapSet.delete(acc.tombstones, seq),
            seq_map: Map.delete(acc.seq_map, seq)
        }

        {head, tail, nodes} = Link.unlink({acc.head, acc.tail, acc.nodes}, seq)
        %{acc | head: head, tail: tail, nodes: nodes}
      end)

    {:ok, timeline}
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

  # ---- helpers ----

  defp unlink(%__MODULE__{} = timeline, op_fn) do
    {hd, tl, nodes} = op_fn.({timeline.head, timeline.tail, timeline.nodes})

    %{timeline | head: hd, tail: tl, nodes: nodes}
  end

  defp assert_has_node(timeline, seq_id) do
    if has_node?(timeline, seq_id), do: :ok, else: {:error, {:not_found, seq_id}}
  end

  defp assert_not_tombstone(%__MODULE__{tombstones: ts}, seq_id) do
    if MapSet.member?(ts, seq_id), do: {:error, {:is_tombstone, seq_id}}, else: :ok
  end
end

defimpl Enumerable, for: Zongzi.Timeline do
  def count(%Zongzi.Timeline{seq_map: seq_map, tombstones: tombstones}) do
    live = Enum.reduce(tombstones, map_size(seq_map), fn sid, acc ->
      if Map.has_key?(seq_map, sid), do: acc - 1, else: acc
    end)
    {:ok, live}
  end

  def member?(%Zongzi.Timeline{nodes: nodes, tombstones: tombstones}, seq_id) do
    {:ok, Map.has_key?(nodes, seq_id) and not MapSet.member?(tombstones, seq_id)}
  end

  def reduce(%Zongzi.Timeline{head: nil}, {:cont, acc}, _fun), do: {:done, acc}
  def reduce(%Zongzi.Timeline{head: nil}, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(%Zongzi.Timeline{head: nil}, {:suspend, acc}, _fun),
    do: {:suspended, acc, &reduce_done/1}

  def reduce(%Zongzi.Timeline{} = tl, acc, fun) do
    do_reduce(tl.nodes, tl.head, tl.tombstones, acc, fun)
  end

  defp do_reduce(_nodes, nil, _ts, {:cont, acc}, _fun), do: {:done, acc}
  defp do_reduce(_nodes, nil, _ts, {:halt, acc}, _fun), do: {:halted, acc}
  defp do_reduce(_nodes, nil, _ts, {:suspend, acc}, _fun),
    do: {:suspended, acc, &reduce_done/1}

  defp do_reduce(_nodes, _seq, _ts, {:done, acc}, _fun), do: {:done, acc}

  defp do_reduce(nodes, seq, ts, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(nodes, seq, ts, &1, fun)}
  end

  defp do_reduce(_nodes, _seq, _ts, {:halt, acc}, _fun), do: {:halted, acc}

  defp do_reduce(nodes, seq, ts, {:cont, acc}, fun) do
    {_, nxt} = Map.fetch!(nodes, seq)

    if MapSet.member?(ts, seq) do
      do_reduce(nodes, nxt, ts, {:cont, acc}, fun)
    else
      case fun.(seq, acc) do
        {:cont, acc2} -> do_reduce(nodes, nxt, ts, {:cont, acc2}, fun)
        {:halt, acc2} -> {:halted, acc2}
        {:suspend, acc2} -> {:suspended, acc2, &do_reduce(nodes, nxt, ts, &1, fun)}
      end
    end
  end

  defp reduce_done({:cont, acc}), do: {:done, acc}
  defp reduce_done({:halt, acc}), do: {:halted, acc}
  defp reduce_done({:suspend, acc}), do: {:suspended, acc, &reduce_done/1}

  def slice(%Zongzi.Timeline{} = tl) do
    {:ok, map_size(tl.seq_map), &do_slice(tl, &1, &2, &3)}
  end

  defp do_slice(tl, start, length, 1) do
    tl
    |> Zongzi.Timeline.to_list()
    |> Enum.reject(&MapSet.member?(tl.tombstones, &1))
    |> Enum.slice(start, length)
  end

  defp do_slice(_tl, _start, _length, _step), do: []
end
