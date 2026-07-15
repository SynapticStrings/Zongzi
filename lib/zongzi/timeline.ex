defmodule Zongzi.Timeline do
  @moduledoc """
  轨道序列真实源。

  仅记录音符序列之间的相互关系

  独立于 Note 的生命周期——Note 被 split/merge/drag 后，
  Timeline 维护的 seq_id 序列始终反映最新的全序关系。

  ## 数据字段

  - `note_order` — seq_id 的有序链表，定义轨道的全序
  - `seq_map` — seq_id → note_id 的反向查找
  - `tombstones` — 已删除的 seq_id，保留在链表中以维护邻接稳定性

  ## 查询原语

  参见 `Zongzi.Timeline.Query` 模块。
  """
  alias Zongzi.{Util.ID, Score.Note, Timeline.SeqID}

  @type t :: %__MODULE__{
          track_id: ID.t(),
          note_order: [SeqID.t()],
          seq_map: %{SeqID.t() => ID.t(Note)},
          tombstones: MapSet.t(SeqID.t())
        }

  defstruct [:track_id, note_order: [], seq_map: %{}, tombstones: MapSet.new(), next_seq: 1]

  @doc """
  创建 Timeline。

  ## 选项

  - `:next_seq` — 反序列化时传入，应设为 `max(existed seq_id) + 1`。新建时留空（默认 1）。
  """
  def new(track_id, opts \\ []) do
    next_seq = Keyword.get(opts, :next_seq, 1)
    {:ok, %__MODULE__{track_id: track_id, next_seq: next_seq}}
  end

  # ---- 写操作 ----
  # 也是针对音符序列的操作

  @doc "将音符追加到 Timeline 末尾，自动分配 seq_id。"
  @spec insert_note(t(), Note.t()) :: {:ok, t(), Note.t()}
  def insert_note(%__MODULE__{} = tl, %Note{} = note) do
    {seq_id, tl} =
      if note.seq_id, do: {note.seq_id, tl}, else: generate(tl)

    note = %{note | seq_id: seq_id}

    tl = %__MODULE__{
      tl
      | note_order: tl.note_order ++ [seq_id],
        seq_map: Map.put(tl.seq_map, seq_id, note.id)
    }

    {:ok, tl, note}
  end

  @doc "将音符插入 Timeline 的指定 index（0-based）。"
  @spec insert_note_at(t(), Note.t(), non_neg_integer()) :: {:ok, t(), Note.t()}
  def insert_note_at(%__MODULE__{} = tl, %Note{} = note, index)
      when is_integer(index) and index >= 0 do
    {seq_id, tl} = if note.seq_id, do: {note.seq_id, tl}, else: generate(tl)
    note = %{note | seq_id: seq_id}
    idx = min(index, length(tl.note_order))
    {left, right} = Enum.split(tl.note_order, idx)

    tl = %__MODULE__{
      tl
      | note_order: left ++ [seq_id | right],
        seq_map: Map.put(tl.seq_map, seq_id, note.id)
    }

    {:ok, tl, note}
  end

  @doc """
  在 `split_tick` 处切开音符，返回前后两个 Note。

  内部调用 `Note.split/4`，`new_id` 显式注入。
  后半音符自动分配新 seq_id 并 splice 到原音符后。
  """
  @spec split_note(t(), Note.t(), non_neg_integer(), ID.t()) ::
          {:ok, t(), Note.t(), Note.t()} | {:error, term()}
  def split_note(%__MODULE__{} = tl, %Note{} = note, split_tick, new_id) do
    seq_id = note.seq_id

    with {:ok, idx} <- note_order_index(tl, seq_id),
         :ok <- assert_not_tombstone(tl, seq_id),
         {:ok, before_note, after_note} <- Note.split(note, split_tick, new_id) do
      {new_seq, tl} = generate(tl)
      before_note = %{before_note | seq_id: seq_id}
      after_note = %{after_note | seq_id: new_seq}

      {left, right} = Enum.split(tl.note_order, idx + 1)

      tl = %__MODULE__{
        tl
        | note_order: left ++ [new_seq | right],
          seq_map: Map.put(tl.seq_map, new_seq, tl.seq_map[seq_id])
      }

      {:ok, tl, before_note, after_note}
    end
  end

  @doc """
  拖拽 seq 到 target_seq 的 before/after 位置。

  拖拽墓碑拒绝；target 不存在报错。
  """
  @spec move_note(t(), SeqID.t(), SeqID.t(), :before | :after) :: {:ok, t()} | {:error, term()}
  def move_note(%__MODULE__{} = tl, seq_id, target_seq, where)
      when where in [:before, :after] do
    with :ok <- assert_not_tombstone(tl, seq_id),
         {:ok, src_idx} <- note_order_index(tl, seq_id),
         {:ok, tgt_idx} <- note_order_index(tl, target_seq) do
      without = List.delete_at(tl.note_order, src_idx)
      # 删除后 target index 可能左移一位
      tgt_idx2 = if src_idx < tgt_idx, do: tgt_idx - 1, else: tgt_idx
      insert_idx = if where == :after, do: tgt_idx2 + 1, else: tgt_idx2
      insert_idx = min(insert_idx, length(without))
      {left, right} = Enum.split(without, insert_idx)
      {:ok, %__MODULE__{tl | note_order: left ++ [seq_id | right]}}
    else
      {:error, reason} when not is_map(reason) -> {:error, reason}
      {:error, _} = err -> err
    end
  end

  @doc "拖拽 seq_id 到新 index。已废弃，建议用基于锚相对语义的 move_note/4。"
  @spec drag_note(t(), SeqID.t(), non_neg_integer()) :: {:ok, t()} | {:error, term()}
  def drag_note(%__MODULE__{} = tl, seq_id, new_index)
      when is_integer(new_index) and new_index >= 0 do
    if MapSet.member?(tl.tombstones, seq_id) do
      {:error, {:is_tombstone, seq_id}}
    else
      case note_order_index(tl, seq_id) do
        {:ok, idx} ->
          without = List.delete_at(tl.note_order, idx)
          new_index = min(new_index, length(without))
          {left, right} = Enum.split(without, new_index)
          {:ok, %__MODULE__{tl | note_order: left ++ [seq_id | right]}}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  合并两个音符。内部调用 `Note.merge/4`，`merged_id` 显式注入。

  seq_id_2 变墓碑，seq_id_1 保留并指向 merged_note_id。
  返回合并后的 Note（seq_id 继承 note_a.seq_id）。
  """
  @spec merge_notes(t(), Note.t(), Note.t(), ID.t()) :: {:ok, t(), Note.t()} | {:error, term()}
  def merge_notes(%__MODULE__{} = tl, %Note{} = note_a, %Note{} = note_b, merged_id) do
    s1 = note_a.seq_id
    s2 = note_b.seq_id

    with {:ok, _} <- note_order_index(tl, s1),
         {:ok, _} <- note_order_index(tl, s2),
         :ok <- assert_not_tombstone(tl, s1),
         :ok <- assert_not_tombstone(tl, s2),
         {:ok, merged} <- Note.merge(note_a, note_b, merged_id) do
      merged = %{merged | seq_id: s1}

      tl = %__MODULE__{
        tl
        | seq_map: Map.put(tl.seq_map, s1, merged_id),
          tombstones: MapSet.put(tl.tombstones, s2)
      }

      {:ok, tl, merged}
    end
  end

  @doc "删除 seq_id → 墓碑。"
  @spec delete_note(t(), SeqID.t()) :: {:ok, t()} | {:error, term()}
  def delete_note(%__MODULE__{} = tl, seq_id) do
    with {:ok, _} <- note_order_index(tl, seq_id),
         :ok <- assert_not_tombstone(tl, seq_id) do
      tl = %__MODULE__{
        tl
        | seq_map: Map.delete(tl.seq_map, seq_id),
          tombstones: MapSet.put(tl.tombstones, seq_id)
      }

      {:ok, tl}
    end
  end

  # 和音符操作无关的更新

  @doc "回收无 intervention 引用的墓碑。"
  @spec gc(t(), [Zongzi.Intervention.t()]) :: t()
  def gc(%__MODULE__{} = tl, interventions) do
    live_refs =
      interventions
      |> Enum.flat_map(&(&1.declaration.referenced_seqs(&1)))
      |> MapSet.new()

    unreachable = tl.tombstones |> MapSet.difference(live_refs)

    %__MODULE__{
      tl
      | note_order: Enum.reject(tl.note_order, &MapSet.member?(unreachable, &1)),
        tombstones: Enum.reduce(unreachable, tl.tombstones, &MapSet.delete(&2, &1))
    }
  end

  # ---- 共享 helper ----

  @doc "自持 counter 生成新 SeqID。"
  @spec generate(t()) :: {SeqID.t(), t()}
  def generate(%__MODULE__{next_seq: next} = tl), do: {next, %__MODULE__{tl | next_seq: next + 1}}

  @doc false
  @spec note_order_index(t(), SeqID.t()) ::
          {:ok, non_neg_integer()} | {:error, {:not_found, SeqID.t()}}
  def note_order_index(%__MODULE__{note_order: order}, seq_id) do
    case Enum.find_index(order, &(&1 == seq_id)) do
      nil -> {:error, {:not_found, seq_id}}
      idx -> {:ok, idx}
    end
  end

  defp assert_not_tombstone(%__MODULE__{tombstones: ts}, seq_id) do
    if MapSet.member?(ts, seq_id), do: {:error, {:is_tombstone, seq_id}}, else: :ok
  end
end
