defmodule Zongzi.Timeline do
  @moduledoc """
  轨道的序列真相（source of truth for note ordering）。

  独立于 Note 的生命周期——Note 被 split/merge/drag 后，
  Timeline 维护的 seq_id 序列始终反映最新的全序关系。

  ## 数据字段

  - `note_order` — seq_id 的有序链表，定义轨道的全序
  - `seq_map` — seq_id → note_id 的反向查找
  - `tombstones` — 已删除的 seq_id，保留在链表中以维护邻接稳定性

  ## 查询原语

  `status/2`、`scan/4`、`neighborhood/3` 等查询原语在 `Timeline.Query`。
  `adjacent/2`、`try_match/2` 等旧 API 保留在本模块，内部 delegate 到 Query。
  """
  alias Zongzi.{Util.ID, Score.Note, Timeline.SeqID}
  alias Zongzi.Timeline.Query

  @type t :: %__MODULE__{
          track_id: ID.t(),
          note_order: [SeqID.t()],
          seq_map: %{SeqID.t() => ID.t()},
          tombstones: MapSet.t(SeqID.t())
        }

  defstruct [:track_id, note_order: [], seq_map: %{}, tombstones: MapSet.new(), next_seq: 1]

  @doc """
  创建 Timeline。

  ## 选项
  - `:next_seq` — 反序列化时传入，应设为 `max(已有 seq_id) + 1`。新建时留空（默认 1）。
  """
  def new(track_id, opts \\ []) do
    next_seq = Keyword.get(opts, :next_seq, 1)
    {:ok, %__MODULE__{track_id: track_id, next_seq: next_seq}}
  end

  # ---- 写操作 ----

  @doc "将音符追加到 Timeline 末尾，自动分配 seq_id。"
  @spec insert_note(t(), Note.t()) :: {:ok, t(), Note.t()}
  def insert_note(%__MODULE__{} = tl, %Note{} = note) do
    {seq_id, tl} =
      if note.seq_id, do: {note.seq_id, tl}, else: generate(tl)
    note = %{note | seq_id: seq_id}
    tl = %__MODULE__{tl | note_order: tl.note_order ++ [seq_id],
                        seq_map: Map.put(tl.seq_map, seq_id, note.id)}
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
    tl = %__MODULE__{tl | note_order: left ++ [seq_id | right],
                        seq_map: Map.put(tl.seq_map, seq_id, note.id)}
    {:ok, tl, note}
  end

  @doc "在 seq_id 处切开音符，新 seq_id 插入其后。"
  @spec split_note(t(), SeqID.t(), non_neg_integer()) ::
          {:ok, t(), SeqID.t(), SeqID.t()} | {:error, term()}
  def split_note(%__MODULE__{} = tl, seq_id, _split_tick) do
    case note_order_index(tl, seq_id) do
      {:ok, idx} ->
        {new_seq, tl} = generate(tl)
        {left, right} = Enum.split(tl.note_order, idx + 1)
        tl = %__MODULE__{tl | note_order: left ++ [new_seq | right],
                            seq_map: Map.put(tl.seq_map, new_seq, tl.seq_map[seq_id])}
        {:ok, tl, seq_id, new_seq}
      {:error, _} = err -> err
    end
  end

  @doc "拖拽 seq_id 到新 index。"
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
        {:error, _} = err -> err
      end
    end
  end

  @doc "合并：seq_id_2 变墓碑，seq_id_1 保留。"
  @spec merge_notes(t(), SeqID.t(), SeqID.t(), ID.t()) :: {:ok, t()} | {:error, term()}
  def merge_notes(%__MODULE__{} = tl, seq_id_1, seq_id_2, merged_note_id) do
    with {:ok, _} <- note_order_index(tl, seq_id_1),
         {:ok, _} <- note_order_index(tl, seq_id_2),
         :ok <- assert_not_tombstone(tl, seq_id_1),
         :ok <- assert_not_tombstone(tl, seq_id_2) do
      tl = %__MODULE__{tl | seq_map: Map.put(tl.seq_map, seq_id_1, merged_note_id),
                          tombstones: MapSet.put(tl.tombstones, seq_id_2)}
      {:ok, tl}
    end
  end

  @doc "删除 seq_id → 墓碑。"
  @spec delete_note(t(), SeqID.t()) :: {:ok, t()} | {:error, term()}
  def delete_note(%__MODULE__{} = tl, seq_id) do
    with {:ok, _} <- note_order_index(tl, seq_id),
         :ok <- assert_not_tombstone(tl, seq_id) do
      tl = %__MODULE__{tl | seq_map: Map.delete(tl.seq_map, seq_id),
                          tombstones: MapSet.put(tl.tombstones, seq_id)}
      {:ok, tl}
    end
  end

  @doc "自持 counter 生成新 SeqID。"
  @spec generate(t()) :: {SeqID.t(), t()}
  def generate(%__MODULE__{next_seq: next} = tl), do: {next, %__MODULE__{tl | next_seq: next + 1}}

  @doc "回收无 intervention 引用的墓碑。"
  @spec gc(t(), [Zongzi.Intervention.t()]) :: t()
  def gc(%__MODULE__{} = tl, interventions) do
    live_refs =
      interventions
      |> Enum.flat_map(fn int -> {p, c, n} = int.anchor; [p, c, n] |> Enum.reject(&is_nil/1) end)
      |> MapSet.new()
    unreachable = Enum.filter(tl.tombstones, fn s -> not MapSet.member?(live_refs, s) end)
    %__MODULE__{tl | note_order: Enum.reject(tl.note_order, &(&1 in unreachable)),
                   tombstones: Enum.reduce(unreachable, tl.tombstones, &MapSet.delete(&2, &1))}
  end

  # ---- 旧查询 API（delegate 到 Query）----

  @doc "邻接三元组（含墓碑邻居）。"
  @spec adjacent(t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}}
          | {:tombstone, SeqID.t()} | {:error, :not_found}
  def adjacent(%__MODULE__{} = tl, seq_id) do
    case Query.status(tl, seq_id) do
      :missing -> {:error, :not_found}
      st when st in [:merge_tombstone, :delete_tombstone] -> {:tombstone, seq_id}
      :active ->
        case note_order_index(tl, seq_id) do
          {:ok, idx} ->
            order = tl.note_order
            {:ok, {if(idx > 0, do: Enum.at(order, idx - 1)),
                   Enum.at(order, idx),
                   Enum.at(order, idx + 1)}}
          {:error, _} -> {:error, :not_found}
        end
    end
  end

  @doc "2-of-3 exact match。"
  @spec try_match(t(), {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}) ::
          {:ok, non_neg_integer()} | {:tombstone, SeqID.t()} | {:error, :not_found}
  def try_match(%__MODULE__{} = tl, {old_prev, old_current, old_next}) do
    case adjacent(tl, old_current) do
      {:ok, {new_prev, _, new_next}} ->
        m = ((old_prev == new_prev && 1) || 0) + 1 + ((old_next == new_next && 1) || 0)
        {:ok, m}
      other -> other
    end
  end

  @doc "向一侧跳过墓碑，找最近活跃邻居。thin wrapper over `Query.scan/4`。"
  @spec nearest_active(t(), SeqID.t(), :prev | :next) ::
          {:ok, SeqID.t()} | {:error, :no_active_neighbor}
  def nearest_active(%__MODULE__{} = tl, seq_id, direction)
      when direction in [:prev, :next] do
    case Query.scan(tl, seq_id, direction, active_only: true, limit: 1) do
      [sid] -> {:ok, sid}
      [] -> {:error, :no_active_neighbor}
    end
  end

  @doc "seq_map 成员检查。更推荐用 `Query.status/2`。"
  @spec seq_map_has?(t(), SeqID.t()) :: boolean()
  def seq_map_has?(%__MODULE__{seq_map: sm}, seq_id), do: Map.has_key?(sm, seq_id)

  # ---- 共享 helper ----

  @doc false
  @spec note_order_index(t(), SeqID.t()) :: {:ok, non_neg_integer()} | {:error, {:not_found, SeqID.t()}}
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
