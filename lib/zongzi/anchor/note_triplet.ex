defmodule Zongzi.Anchor.NoteTriplet do
  @moduledoc """
  基于 NoteTriplet 的结构锚点策略。默认策略。

  三元组 `{prev_seq, current_seq, next_seq}` 锚定 intervention 在 Timeline 中的位置。
  rebase 是纯函数——只判结构死活，不碰 snapshot（语义有效性留给 render 时 resolve）。

  ## 决策表

  | current status | match | 输出 |
  |---|---|---|
  | active | 3/3 | `{:ok, :preserve}` |
  | active | ≥ threshold | `{:ok, {:rebase, updated}}` |
  | active | < threshold | `{:conflict, :adjacency_lost}` |
  | merge_tombstone | — | `{:conflict, :merged_away}`（或 `:follow_merge` relocate） |
  | delete_tombstone | — | relocate 到最近活跃邻居（双腿扫描） |
  | missing | — | 依据注入 interv 时的 option 等判断是 conflict 还是 relocated |

  ## match_threshold

  Context 或 Strategy opts 可设 `match_threshold`（默认 2）：
  - `2` = 默认：≥2/3 匹配即存活
  - `1` = lenient：仅 current 匹配即可（适合 pitch 等 parameter channel）

  ## Options

  本策略专属配置，挂在 `Intervention.strategy` 的 `{NoteTriplet, %Options{…}}` 元组中。
  rebase 的第四参数即为 `%Options{}`（或兼容 map）。

  - `:match_threshold` — 存活阈值（默认 2）。`1` = lenient（仅 current 匹配即可，适合 pitch channel）
  - `:allow_follow_merge` — 是否允许跟踪 merge 目标重定位（默认 false）
  - `:orphan_direction` — `:prev` | `:next` | `:never`（默认 `:next`）。
    `:never` 时 delete tombstone 直接报 conflict，不尝试 relocate。
  """

  @behaviour Zongzi.Anchor.Strategy

  alias Zongzi.{Intervention, Timeline}
  alias Zongzi.Anchor.TripletMatch
  alias Zongzi.Timeline.Query

  defmodule Options do
    @moduledoc false

    defstruct match_threshold: 2,
              allow_follow_merge: false,
              orphan_direction: :next
  end

  @impl true
  def rebase(
        %Intervention{anchor: {_old_prev, current, _old_next}} = int,
        %Timeline{} = timeline,
        _ctx,
        opts
      ) do
    opts = normalize_opts(opts)

    case TripletMatch.match(int, timeline) do
      {:active, match_count, {new_prev, _current, new_next}} ->
        cond do
          match_count >= opts.match_threshold ->
            if match_count == 3 do
              {:ok, :preserve}
            else
              {:ok, {:rebase, %{int | anchor: {new_prev, current, new_next}}}}
            end

          true ->
            {:conflict, :adjacency_lost}
        end

      {:tombstone, :merge} ->
        if opts.allow_follow_merge do
          follow_merge(int, timeline, current)
        else
          {:conflict, :merged_away}
        end

      {:tombstone, :delete} ->
        maybe_relocate(int, timeline, current, opts.orphan_direction)
    end
  end

  @impl true
  def referenced_seqs(%Intervention{anchor: {p, c, n}}),
    do: TripletMatch.referenced_seqs({p, c, n})

  def referenced_seqs(_), do: []

  # ---- private ----

  # Normalize opts to %Options{} struct, filling defaults from anything map-like.
  defp normalize_opts(%Options{} = opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: struct(Options, Map.to_list(opts))
  defp normalize_opts(_), do: %Options{}

  # 跟随合并目标重定位
  defp follow_merge(int, %Timeline{} = timeline, dead_seq) do
    merged_id = Map.get(timeline.seq_map, dead_seq)

    active_merged =
      Enum.find(Timeline.to_list(timeline), fn sid ->
        not MapSet.member?(timeline.tombstones, sid) and
          Map.get(timeline.seq_map, sid) == merged_id
      end)

    if active_merged do
      case TripletMatch.scrub_triplet(timeline, active_merged) do
        {:ok, triplet} ->
          {:ok,
           {:relocate, %{int | anchor: triplet},
            %{from: dead_seq, to: active_merged, method: :follow_merge}}}

        {:error, :not_active} ->
          {:conflict, :merged_away}
      end
    else
      {:conflict, :merged_away}
    end
  end

  # relocate：从当前位置（墓碑）向两侧扫描活跃邻居。
  # 当 current 已从 Timeline 移除（missing）时 Query.scan 返回 []，
  # 直接走 conflict 路径——这属于"挂载时 Caller 选错了锚点"或
  # "连续删除导致锚点链断裂"的正常语义冲突，不需要额外处理。
  defp maybe_relocate(int, timeline, current, direction) do
    case direction do
      :never -> {:conflict, :relocate_forbidden}
      _ -> maybe_relocate_inner(int, timeline, current, direction)
    end
  end

  defp maybe_relocate_inner(int, timeline, current, direction) do
    prev_cand = Query.scan(timeline, current, :prev, active_only: true, limit: 1)
    next_cand = Query.scan(timeline, current, :next, active_only: true, limit: 1)

    all =
      case direction do
        :prev -> prev_cand ++ next_cand
        :next -> next_cand ++ prev_cand
      end

    case all do
      [nearest | _] ->
        case TripletMatch.scrub_triplet(timeline, nearest) do
          {:ok, triplet} ->
            {:ok,
             {:relocate, %{int | anchor: triplet},
              %{from: current, to: nearest, method: :nearest_active}}}

          {:error, :not_active} ->
            {:conflict, :adjacency_lost}
        end

      [] ->
        {:conflict, :adjacency_lost}
    end
  end
end
