defmodule Zongzi.Timeline do
  @moduledoc """
  轨道的序列真相（source of truth for note ordering）。

  独立于 Note 的生命周期——Note 被 split/merge/drag 后，
  Timeline 维护的 seq_id 序列始终反映最新的全序关系。

  ## 为什么需要 Timeline

  Note 的 `start_tick` 只表示音符在时间轴上的位置，不是它在序列中的位置。
  两个音符可以 `start_tick` 相同（复音），但在 Timeline 上有明确的先后。

  Intervention 锚定的不是绝对时间，而是序列中的邻接关系。
  当音符被拖拽、切分、合并时，只要邻接的 seq_id 对得上 2/3，
  intervention 就能存活。

  ## 数据字段

  - `note_order` — seq_id 的有序链表，定义轨道的全序
  - `seq_map` — seq_id → note_id 的反向查找
  - `tombstones` — 已删除的 seq_id（被 merge 或 split 替换），
    墓碑保留在链表中以维护邻接稳定性

  ## 与 Intervention 的关系

  Intervention 用 `{prev_seq_id, current_seq_id, next_seq_id}` 三元组锚定。
  当 Timeline 变更后，通过 `adjacent/2` 查询三元组的存活状态，
  用 2-of-3 exact match 决定 resolve 还是 conflict。

  机制细节：`Anchor.NoteTriplet`（待实现）。
  """
  alias Zongzi.{Util.ID, Score.Note, Timeline.SeqID}

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

  - `:next_seq` — 反序列化时传入，应设为 `max(已有 seq_id) + 1`。
    新建时留空（默认 1）。
  """
  def new(track_id, opts \\ []) do
    next_seq = Keyword.get(opts, :next_seq, 1)
    {:ok, %__MODULE__{track_id: track_id, next_seq: next_seq}}
  end

  # ---- 基本操作 ----

  @doc """
  将音符追加到 Timeline 末尾。

  如果 Note 没有 seq_id（nil），自动生成一个新的。
  如果已有 seq_id（反序列化），直接使用。
  """
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

  @doc """
  将音符插入 Timeline 的指定位置。

  `index` 是 note_order 中的目标索引（0-based）。
  超出范围时插入末尾。

  调用方负责根据 start_tick 计算正确的 index——
  Timeline 不持有 Note 字段，只维护序列全序。
  """
  @spec insert_note_at(t(), Note.t(), non_neg_integer()) :: {:ok, t(), Note.t()}
  def insert_note_at(%__MODULE__{} = tl, %Note{} = note, index)
      when is_integer(index) and index >= 0 do
    {seq_id, tl} =
      if note.seq_id, do: {note.seq_id, tl}, else: generate(tl)

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
  在指定 tick 处切开 seq_id 对应的音符。

  左半保留原 seq_id（seq_map 不变），右半获得新 seq_id。
  新 seq_id 插入 note_order 中原 seq_id 之后。
  """
  @spec split_note(t(), SeqID.t(), non_neg_integer()) ::
          {:ok, t(), SeqID.t(), SeqID.t()} | {:error, term()}
  def split_note(%__MODULE__{} = tl, seq_id, _split_tick) do
    case note_order_index(tl, seq_id) do
      {:ok, idx} ->
        {new_seq, tl} = generate(tl)
        {left, right} = Enum.split(tl.note_order, idx + 1)

        tl = %__MODULE__{
          tl
          | note_order: left ++ [new_seq | right],
            seq_map: Map.put(tl.seq_map, new_seq, tl.seq_map[seq_id])
        }

        {:ok, tl, seq_id, new_seq}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  拖拽 seq_id 到 note_order 中的新位置。

  seq_id 本身不变——只是它在链表中的位置移动。
  `new_index` 是移除后重新插入的目标索引（0-based）。
  如果超出范围，插入末尾。

  ## 语义

  - seq_id 是墓碑 → 拒绝操作
  - msg_id 不在 Timeline → {:error, :not_found}
  """
  @spec drag_note(t(), SeqID.t(), non_neg_integer()) ::
          {:ok, t()} | {:error, term()}
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
          note_order = left ++ [seq_id | right]

          {:ok, %__MODULE__{tl | note_order: note_order}}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  合并两个相邻的 seq_id。

  seq_id_1 保留（更新 seq_map 指向新 note_id），seq_id_2 变成墓碑。
  seq_id_2 仍留在 note_order 中以维持邻接稳定性。
  """
  @spec merge_notes(t(), SeqID.t(), SeqID.t(), ID.t()) ::
          {:ok, t()} | {:error, term()}
  def merge_notes(%__MODULE__{} = tl, seq_id_1, seq_id_2, merged_note_id) do
    with {:ok, _idx1} <- note_order_index(tl, seq_id_1),
         {:ok, _idx2} <- note_order_index(tl, seq_id_2),
         :ok <- assert_not_tombstone(tl, seq_id_1),
         :ok <- assert_not_tombstone(tl, seq_id_2) do
      tl = %__MODULE__{
        tl
        | seq_map: tl.seq_map |> Map.put(seq_id_1, merged_note_id),
          tombstones: tl.tombstones |> MapSet.put(seq_id_2)
      }

      {:ok, tl}
    end
  end

  @doc """
  删除 seq_id——将其标记为墓碑，保留在 note_order 中维持邻接稳定性。

  与 `merge_notes/4` 类似：墓碑留在 note_order，
  锚在其上的 intervention 收到 `{:tombstone, seq_id}` → `:merged_away`。

  不再被任何 intervention 引用的墓碑可通过 `gc/2` 回收。
  """
  @spec delete_note(t(), SeqID.t()) :: {:ok, t()} | {:error, term()}
  def delete_note(%__MODULE__{} = tl, seq_id) do
    with {:ok, _idx} <- note_order_index(tl, seq_id),
         :ok <- assert_not_tombstone(tl, seq_id) do
      tl = %__MODULE__{
        tl
        | seq_map: Map.delete(tl.seq_map, seq_id),
          tombstones: MapSet.put(tl.tombstones, seq_id)
      }

      {:ok, tl}
    end
  end

  # ---- 查询 ----

  @doc """
  查询 seq_id 在 Timeline 中的邻接关系。

  返回 `{:ok, {prev_seq, current_seq, next_seq}}`。
  prev/next 可能为 nil（首/尾）。

  如果 seq_id 是墓碑：返回 `{:tombstone, seq_id}`。
  如果 seq_id 不在 Timeline：返回 `{:error, :not_found}`。
  """
  @spec adjacent(t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}}
          | {:tombstone, SeqID.t()}
          | {:error, :not_found}
  def adjacent(%__MODULE__{} = tl, seq_id) do
    cond do
      MapSet.member?(tl.tombstones, seq_id) ->
        {:tombstone, seq_id}

      true ->
        case note_order_index(tl, seq_id) do
          {:ok, idx} ->
            order = tl.note_order
            prev = if idx > 0, do: Enum.at(order, idx - 1)
            current = Enum.at(order, idx)
            next = Enum.at(order, idx + 1)
            {:ok, {prev, current, next}}

          {:error, _} ->
            {:error, :not_found}
        end
    end
  end

  @doc """
  检查 seq_id 对应的三元组是否满足 2-of-3 匹配。

  用于 Intervention rebase——旧三元组 vs 新三元组。
  返回 `{:ok, match_count}` 或 `{:tombstone, ...}`。

  `old_prev` 或 `old_next` 为 nil（首/尾边界）与新 nil 匹配视为命中。
  边界本身是稳定结构信息，理应算入 2-of-3。
  """
  @spec try_match(t(), {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}) ::
          {:ok, non_neg_integer()} | {:tombstone, SeqID.t()} | {:error, :not_found}
  def try_match(%__MODULE__{} = tl, {old_prev, old_current, old_next}) do
    case adjacent(tl, old_current) do
      {:ok, {new_prev, _, new_next}} ->
        matches =
          ((old_prev == new_prev && 1) || 0) +
            1 +
            ((old_next == new_next && 1) || 0)

        {:ok, matches}

      {:tombstone, _} = tombstone ->
        tombstone

      {:error, _} = err ->
        err
    end
  end

  @doc """
  自持 counter 生成新 SeqID。

  用 Timeline 内部的 `next_seq` 字段而非全局 `System.unique_integer`，
  避免 BEAM 重启后 counter 归零导致与已序列化的 seq_id 碰撞。
  """
  @spec generate(t()) :: {SeqID.t(), t()}
  def generate(%__MODULE__{next_seq: next} = tl) do
    {next, %__MODULE__{tl | next_seq: next + 1}}
  end

  @doc """
  从 seq_id 位置向指定方向扫描，跳过墓碑，返回最近的活跃 seq_id。

  用于 orphan push——intervention 的 anchor seq_id 不在 Timeline 时，
  沿 channel 相关方向找最近存活的邻居重新锚定。

  方向由各 channel strategy 决定（如 pitch 向前找，phoneme offset 向后找）。
  """
  @spec nearest_active(t(), SeqID.t(), :prev | :next) ::
          {:ok, SeqID.t()} | {:error, :no_active_neighbor}
  def nearest_active(%__MODULE__{} = tl, seq_id, direction) do
    case note_order_index(tl, seq_id) do
      {:ok, idx} ->
        scan_from(tl, idx, direction)

      {:error, _} ->
        {:error, :no_active_neighbor}
    end
  end

  @doc """
  回收无引用的墓碑。

  遍历所有 intervention 的锚点三元组，收集被引用的 seq_id。
  任何不在引用集合中的墓碑从 note_order 和 tombstones 集中移除。

  应该在 rebase_all 之后调用——此时 conflict 已上浮，
  存活和 rebase 的 intervention 是当前有效引用集。
  """
  @spec gc(t(), [Zongzi.Intervention.t()]) :: t()
  def gc(%__MODULE__{} = tl, interventions) do
    live_refs =
      interventions
      |> Enum.flat_map(fn int ->
        {p, c, n} = int.anchor
        [p, c, n] |> Enum.reject(&is_nil/1)
      end)
      |> MapSet.new()

    unreachable =
      tl.tombstones
      |> Enum.filter(fn seq_id -> not MapSet.member?(live_refs, seq_id) end)

    %__MODULE__{
      tl
      | note_order: Enum.reject(tl.note_order, &(&1 in unreachable)),
        tombstones: Enum.reduce(unreachable, tl.tombstones, &MapSet.delete(&2, &1))
    }
  end

  @doc """
  检查 seq_id 是否仍在 seq_map 中。

  merge 保留 seq_map 条目（指向合并后 note_id），delete 移除。
  rebase 用此区分 merge 墓碑（→ conflict）和 delete 墓碑（→ push）。
  """
  @spec seq_map_has?(t(), SeqID.t()) :: boolean()
  def seq_map_has?(%__MODULE__{seq_map: sm}, seq_id), do: Map.has_key?(sm, seq_id)

  # ---- helpers ----

  defp scan_from(%__MODULE__{note_order: order, tombstones: ts}, idx, :prev) do
    order
    |> Enum.slice(0, idx)
    |> Enum.reverse()
    |> Enum.find(&(not MapSet.member?(ts, &1)))
    |> case do
      nil -> {:error, :no_active_neighbor}
      sid -> {:ok, sid}
    end
  end

  defp scan_from(%__MODULE__{note_order: order, tombstones: ts}, idx, :next) do
    order
    |> Enum.slice((idx + 1)..-1//1)
    |> Enum.find(&(not MapSet.member?(ts, &1)))
    |> case do
      nil -> {:error, :no_active_neighbor}
      sid -> {:ok, sid}
    end
  end

  defp note_order_index(%__MODULE__{note_order: order}, seq_id) do
    case Enum.find_index(order, &(&1 == seq_id)) do
      nil -> {:error, {:not_found, seq_id}}
      idx -> {:ok, idx}
    end
  end

  defp assert_not_tombstone(%__MODULE__{tombstones: ts}, seq_id) do
    if MapSet.member?(ts, seq_id) do
      {:error, {:is_tombstone, seq_id}}
    else
      :ok
    end
  end
end
