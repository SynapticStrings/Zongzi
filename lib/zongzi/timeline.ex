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

  机制细节：`Anchor.NoteTriplet`（implements `Anchor.Strategy`）。
  """
  alias Zongzi.{Util.ID, Score.Note, Timeline.SeqID}
  alias Zongzi.Timeline.Neighborhood

  @typedoc "格子状态。策略用此区分 merge 墓碑 vs delete 墓碑，无需猜 seq_map。"
  @type cell_status :: :active | :merge_tombstone | :delete_tombstone | :missing

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
  # ---- 查询原语（ADR-013 / Strategy 地基）----

  @doc """
  格子状态。策略用此区分 merge 墓碑 vs delete 墓碑，无需猜 seq_map。

  - `:active` — 在 order、非墓碑、seq_map 有条目
  - `:merge_tombstone` — 墓碑且 seq_map 仍有（merge 保留映射）
  - `:delete_tombstone` — 墓碑且 seq_map 已无
  - `:missing` — order 中不存在（已 gc 或从未插入）
  """
  @spec status(t(), SeqID.t()) :: cell_status()
  def status(%__MODULE__{} = tl, seq_id) do
    cond do
      not Enum.member?(tl.note_order, seq_id) ->
        :missing

      MapSet.member?(tl.tombstones, seq_id) ->
        if Map.has_key?(tl.seq_map, seq_id), do: :merge_tombstone, else: :delete_tombstone

      Map.has_key?(tl.seq_map, seq_id) ->
        :active

      true ->
        # 防御：在 order、非墓碑、却无 map — 不变量被破坏
        :missing
    end
  end

  @doc "是否为可承载锚点的活格子。"
  @spec active?(t(), SeqID.t()) :: boolean()
  def active?(%__MODULE__{} = tl, seq_id), do: status(tl, seq_id) == :active

  @doc """
  有向扫描，返回候选 SeqID 列表（近→远）。

  ## Options

  - `:active_only` — 跳过墓碑（默认 `true`）
  - `:include_self` — 默认 `false`；为 true 时若自身满足过滤则置于列表头
  - `:limit` — 最多返回几个；`nil` 表示不限制
  - `:max_hops` — 在 note_order 上最多跨几格（含被跳过的墓碑格）

  `nearest_active/3` ≡ `scan(..., limit: 1) |> List.first()` 的包装。
  """
  @spec scan(t(), SeqID.t(), :prev | :next, keyword()) :: [SeqID.t()]
  def scan(%__MODULE__{} = tl, seq_id, direction, opts \\ [])
      when direction in [:prev, :next] do
    active_only? = Keyword.get(opts, :active_only, true)
    include_self? = Keyword.get(opts, :include_self, false)
    limit = Keyword.get(opts, :limit)
    max_hops = Keyword.get(opts, :max_hops)

    case note_order_index(tl, seq_id) do
      {:error, _} ->
        []

      {:ok, idx} ->
        self_part =
          if include_self? and pass_filter?(tl, seq_id, active_only?),
            do: [seq_id],
            else: []

        walked = walk(tl, idx, direction, active_only?, max_hops, limit)
        take_limit(self_part ++ walked, limit)
    end
  end

  @doc """
  焦点邻域。默认 `count: 1, active_only: false` 可还原三元组邻居语义。

  `count` 是每侧收集的格子数（不是格距半径）。中间若隔墓碑，hops_from_focus 可 > count。
  """
  @spec neighborhood(t(), SeqID.t(), keyword()) :: Neighborhood.t()
  def neighborhood(%__MODULE__{} = tl, seq_id, opts \\ []) do
    count = Keyword.get(opts, :count, 1)
    active_only? = Keyword.get(opts, :active_only, false)

    focus_status = status(tl, seq_id)

    case note_order_index(tl, seq_id) do
      {:error, _} ->
        %Neighborhood{focus: seq_id, focus_status: :missing, left: [], right: []}

      {:ok, idx} ->
        left = collect_cells(tl, idx, :prev, count, active_only?)
        right = collect_cells(tl, idx, :next, count, active_only?)

        %Neighborhood{
          focus: seq_id,
          focus_status: focus_status,
          left: left,
          right: right
        }
    end
  end

  @doc """
  将 focus 洗成「左右均为 active（或 nil）」的三元组。

  relocate 落地后写回 anchor 时使用，避免新锚钉在墓碑上。
  """
  @spec scrub_triplet(t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}} | {:error, :not_active}
  def scrub_triplet(%__MODULE__{} = tl, focus) do
    if active?(tl, focus) do
      prev =
        case scan(tl, focus, :prev, active_only: true, limit: 1) do
          [p] -> p
          [] -> nil
        end

      next_ =
        case scan(tl, focus, :next, active_only: true, limit: 1) do
          [n] -> n
          [] -> nil
        end

      {:ok, {prev, focus, next_}}
    else
      {:error, :not_active}
    end
  end

  @doc """
  note_order 上两点格距（含墓碑格）。

  任一方不在 order 中返回 `{:error, :not_found}`。
  """
  @spec hops(t(), SeqID.t(), SeqID.t()) ::
          {:ok, non_neg_integer()} | {:error, :not_found}
  def hops(%__MODULE__{} = tl, a, b) do
    with {:ok, i} <- note_order_index(tl, a),
         {:ok, j} <- note_order_index(tl, b) do
      {:ok, abs(i - j)}
    else
      _ -> {:error, :not_found}
    end
  end
  # ---- 原有查询（行为不变，内部用新原语重写）----

  @doc """
  查询 seq_id 在 Timeline 中的邻接关系（含墓碑邻居）。

  返回 `{:ok, {prev_seq, current_seq, next_seq}}`。
  prev/next 可能为 nil（首/尾），可能是墓碑。

  如果 seq_id 是墓碑：返回 `{:tombstone, seq_id}`。
  如果 seq_id 不在 Timeline：返回 `{:error, :not_found}`。
  """
  @spec adjacent(t(), SeqID.t()) ::
          {:ok, {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}}
          | {:tombstone, SeqID.t()}
          | {:error, :not_found}
  def adjacent(%__MODULE__{} = tl, seq_id) do
    case status(tl, seq_id) do
      :missing ->
        {:error, :not_found}

      st when st in [:merge_tombstone, :delete_tombstone] ->
        {:tombstone, seq_id}

      :active ->
        case note_order_index(tl, seq_id) do
          {:ok, idx} ->
            order = tl.note_order
            prev = if idx > 0, do: Enum.at(order, idx - 1)
            current = Enum.at(order, idx)
            next_ = Enum.at(order, idx + 1)
            {:ok, {prev, current, next_}}

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

  thin wrapper over `scan/4`。
  """
  @spec nearest_active(t(), SeqID.t(), :prev | :next) ::
          {:ok, SeqID.t()} | {:error, :no_active_neighbor}
  def nearest_active(%__MODULE__{} = tl, seq_id, direction)
      when direction in [:prev, :next] do
    case scan(tl, seq_id, direction, active_only: true, limit: 1) do
      [sid] -> {:ok, sid}
      [] -> {:error, :no_active_neighbor}
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

  更推荐新代码用 `status/2`，但保留此函数向后兼容。
  """
  @spec seq_map_has?(t(), SeqID.t()) :: boolean()
  def seq_map_has?(%__MODULE__{seq_map: sm}, seq_id), do: Map.has_key?(sm, seq_id)

  # ---- helpers ----

  defp pass_filter?(tl, seq_id, true), do: active?(tl, seq_id)
  defp pass_filter?(_tl, _seq_id, false), do: true

  defp take_limit(list, nil), do: list
  defp take_limit(list, n) when is_integer(n) and n >= 0, do: Enum.take(list, n)

  defp walk(tl, idx, direction, active_only?, max_hops, limit) do
    order = tl.note_order
    len = length(order)

    range =
      case direction do
        :prev -> (idx - 1)..0//-1
        :next -> (idx + 1)..(len - 1)//1
      end

    {result, _hops} =
      Enum.reduce_while(range, {[], 0}, fn i, {acc, hops_count} ->
        hops_count = hops_count + 1

        cond do
          max_hops && hops_count > max_hops ->
            {:halt, {acc, hops_count}}

          limit && length(acc) >= limit ->
            {:halt, {acc, hops_count}}

          true ->
            sid = Enum.at(order, i)

            if pass_filter?(tl, sid, active_only?) do
              {:cont, {[sid | acc], hops_count}}
            else
              {:cont, {acc, hops_count}}
            end
        end
      end)

    Enum.reverse(result)
  end

  defp collect_cells(tl, idx, direction, count, active_only?) do
    order = tl.note_order
    len = length(order)

    range =
      case direction do
        :prev -> (idx - 1)..0//-1
        :next -> (idx + 1)..(len - 1)//1
      end

    {result, _hops} =
      Enum.reduce_while(range, {[], 0}, fn i, {acc, hops_count} ->
        hops_count = hops_count + 1
        sid = Enum.at(order, i)
        st = status(tl, sid)

        cond do
          length(acc) >= count ->
            {:halt, {acc, hops_count}}

          active_only? and st != :active ->
            {:cont, {acc, hops_count}}

          st == :missing ->
            {:cont, {acc, hops_count}}

          true ->
            cell = %{
              seq_id: sid,
              status: st,
              order_index: i,
              hops_from_focus: hops_count
            }

            {:cont, {[cell | acc], hops_count}}
        end
      end)

    Enum.reverse(result)
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
