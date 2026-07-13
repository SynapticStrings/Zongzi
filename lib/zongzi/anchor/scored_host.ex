defmodule Zongzi.Anchor.ScoredHost do
  @moduledoc """
  多候选打分的孤儿归宿策略。

  与 `NoteTriplet` 的区别：relocate 时不单向找最近邻居，而是
  向两侧各扫 N 个候选，按领域规则打分，择优落户。

  ## 打分规则

  - 无 Note 信息 → score 1（垫底）
  - 同 key（同音高）→ 100
  - 同 Window（同渲染窗）→ 50
  - 跨 Window → `:forbid`（硬约束）

  同分并列 → `{:conflict, :ambiguous_host}`。

  ## Context 键

  - `:notes_by_seq` — `%{SeqID.t() => Note.t()}`，用于读 key
  - `:seq_to_window` — `%{SeqID.t() => window_id}`，可选，跨窗约束
  - `:focus_note` — 原始 focus 的 Note（已删时从 snapshot 恢复）
  """

  @behaviour Zongzi.Anchor.Strategy

  alias Zongzi.{Intervention, Timeline}
  alias Zongzi.Score.Key

  @impl true
  def rebase(intervention, tl, context) do
    %Intervention{anchor: {_, current, _}} = intervention

    case Timeline.try_match(tl, intervention.anchor) do
      {:ok, 3} -> {:ok, :preserve}
      {:ok, 2} -> do_rebase(intervention, tl, current)
      {:ok, _} -> {:conflict, :adjacency_lost}

      {:tombstone, _} ->
        if Timeline.seq_map_has?(tl, current) do
          {:conflict, :merged_away}
        else
          do_scored_relocate(intervention, tl, current, context)
        end

      {:error, :not_found} ->
        do_scored_relocate(intervention, tl, current, context)
    end
  end

  @impl true
  def choose_host(focus, tl, context, opts) do
    scan_limit = Keyword.get(opts, :scan_limit, 4)

    candidates =
      Timeline.Query.scan(tl, focus, :prev, active_only: true, limit: scan_limit) ++
        Timeline.Query.scan(tl, focus, :next, active_only: true, limit: scan_limit)

    scored = score_candidates(candidates, tl, context)

    case scored do
      [] -> {:conflict, :no_host}
      [{best, best_score} | rest] ->
        if length(rest) > 0 and elem(hd(rest), 1) == best_score do
          {:conflict, :ambiguous_host}
        else
          {:ok, best, %{scores: scored}}
        end
    end
  end

  # ---- private ----

  defp do_rebase(intervention, tl, current) do
    case Timeline.adjacent(tl, current) do
      {:ok, new_triplet} -> {:ok, {:rebase, %{intervention | anchor: new_triplet}}}
      _ -> {:conflict, :adjacency_lost}
    end
  end

  defp do_scored_relocate(intervention, tl, current, context) do
    case choose_host(current, tl, context, []) do
      {:ok, best, meta} ->
        case Timeline.Query.scrub_triplet(tl, best) do
          {:ok, triplet} ->
            {:ok,
             {:relocate, %{intervention | anchor: triplet},
              Map.merge(meta, %{from: current, to: best, method: :scored})}}
          {:error, :not_active} -> {:conflict, :no_host}
        end
      {:conflict, _} = err -> err
    end
  end

  @doc false
  def score_candidates(candidates, _tl, context) do
    notes_by_seq = Map.get(context, :notes_by_seq, %{})
    seq_to_window = Map.get(context, :seq_to_window, %{})
    focus_note = Map.get(context, :focus_note)

    candidates
    |> Enum.map(fn cand -> {cand, score_one(cand, notes_by_seq, seq_to_window, focus_note)} end)
    |> Enum.reject(fn {_, s} -> s == :forbid end)
    |> Enum.sort_by(fn {_, s} -> -s end)
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
  defp different_window?(_cand, seq_to_window, _focus_win) when map_size(seq_to_window) == 0, do: false
  defp different_window?(cand, seq_to_window, focus_win) do
    case Map.get(seq_to_window, cand) do
      nil -> true
      ^focus_win -> false
      _other -> true
    end
  end
end
