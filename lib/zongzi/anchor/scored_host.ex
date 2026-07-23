defmodule Zongzi.Anchor.ScoredHost do
  @moduledoc """
  多候选打分的孤儿归宿策略。

  ScoredHost 里的 host 为孤儿重定位时的新 focus seq 。

  与 `NoteTriplet` 的区别：relocate 时不单向找最近邻居，而是
  向两侧各扫 N 个候选，按领域规则打分，择优落户。

  ## 打分规则

  - 无 Note 信息 → score 1（垫底）
  - 同 key（同音高）→ 100
  - 同 Window（同渲染窗）→ 50
  - 跨 Window → `:forbid`（硬约束；seq_to_window 缺映射降为低分 1，不硬禁）

  同分且同 hops → `{:conflict, :ambiguous_host}`。

  match_threshold / allow_follow_merge 语义同 NoteTriplet，通过 `ScoredHost.Options` 结构传递。

  ## Context 键（共享快照）

  - `:notes_by_seq` — `%{SeqID.t() => Note.t()}`
  - `:seq_to_window` — `%{SeqID.t() => window_id}`
  - `:focus_note` — 原始 focus 的 Note

  策略专属旋钮见 `ScoredHost.Options`。
  """

  @behaviour Zongzi.Anchor.Strategy

  alias Zongzi.{Intervention, Timeline}
  alias Zongzi.Anchor.{TripletMatch, NoteTriplet}
  alias Zongzi.Timeline.{Query, SeqID}
  alias Zongzi.Score.Key

  defmodule Options do
    @moduledoc false

    defstruct match_threshold: 2,
              allow_follow_merge: false,
              orphan_direction: :next,
              scan_limit: 4
  end

  @type triplet :: {SeqID.t() | nil, SeqID.t(), SeqID.t() | nil}

  @impl true
  def rebase(
        %Intervention{anchor: {_old_prev, current, _old_next}} = int,
        %Timeline{} = timeline,
        ctx,
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
          NoteTriplet.rebase(int, timeline, ctx, %NoteTriplet.Options{})
        else
          {:conflict, :merged_away}
        end

      {:tombstone, :delete} ->
        do_scored_relocate(int, timeline, current, ctx, opts)
    end
  end

  @impl true
  def referenced_seqs(%Intervention{anchor: {p, c, n}}),
    do: TripletMatch.referenced_seqs({p, c, n})

  def referenced_seqs(_), do: []

  @impl true
  def choose_host(focus, timeline, context, opts) do
    opts = normalize_opts(opts)

    neighbors =
      Query.neighborhood(timeline, focus, active_only: true, count: opts.scan_limit)

    candidates = Enum.map(neighbors.left ++ neighbors.right, &{&1.seq_id, &1.hops_from_focus})

    scored = score_candidates(candidates, context)

    case scored do
      [] ->
        {:conflict, :no_host}

      [{best, best_score, best_hops} | rest] ->
        if rest != [] and elem(hd(rest), 1) == best_score and
             elem(hd(rest), 2) == best_hops do
          {:conflict, :ambiguous_host}
        else
          {:ok, best, %{scores: scored}}
        end
    end
  end

  # ---- private ----

  defp normalize_opts(%Options{} = opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: struct(Options, opts)
  defp normalize_opts(opts) when is_list(opts), do: struct(Options, opts)
  defp normalize_opts(_), do: %Options{}

  defp do_scored_relocate(intervention, timeline, current, ctx, opts) do
    if opts.orphan_direction == :never do
      {:conflict, :relocate_forbidden}
    else
      do_scored_relocate_inner(intervention, timeline, current, ctx, opts)
    end
  end

  defp do_scored_relocate_inner(intervention, timeline, current, context, opts) do
    case choose_host(current, timeline, context, opts) do
      {:ok, best, meta} ->
        case TripletMatch.scrub_triplet(timeline, best) do
          {:ok, triplet} ->
            {:ok,
             {:relocate, %{intervention | anchor: triplet},
              Map.merge(meta, %{from: current, to: best, method: :scored})}}

          {:error, :not_active} ->
            {:conflict, :no_host}
        end

      {:conflict, _} = err ->
        err
    end
  end

  @doc false
  def score_candidates(candidates, context) do
    notes_by_seq = Map.get(context, :notes_by_seq, %{})
    seq_to_window = Map.get(context, :seq_to_window, %{})
    focus_note = Map.get(context, :focus_note)

    candidates
    |> Enum.map(fn {cand, hops} ->
      s = score_one(cand, notes_by_seq, seq_to_window, focus_note)
      {cand, s, hops}
    end)
    |> Enum.reject(fn {_, s, _} -> not is_integer(s) end)
    |> Enum.sort_by(fn {_, s, h} -> {s, -h} end, :desc)
  end

  defp score_one(cand, notes_by_seq, seq_to_window, focus_note) do
    note = Map.get(notes_by_seq, cand)
    focus_win = focus_note && Map.get(seq_to_window, focus_note.seq_id)

    cond do
      different_window?(cand, seq_to_window, focus_win) -> :forbid
      is_nil(note) -> 1
      is_nil(focus_note) -> 50
      same_key?(focus_note, note) -> 100
      true -> 50
    end
  end

  defp same_key?(n1, n2), do: Key.to_midi(n1.key) == Key.to_midi(n2.key)

  defp different_window?(_cand, _seq_to_window, nil), do: false

  defp different_window?(_cand, seq_to_window, _focus_win) when map_size(seq_to_window) == 0,
    do: false

  defp different_window?(cand, seq_to_window, focus_win) do
    case Map.get(seq_to_window, cand) do
      nil -> false
      ^focus_win -> false
      _other -> true
    end
  end
end
