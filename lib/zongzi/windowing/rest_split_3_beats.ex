defmodule Zongzi.Windowing.RestSplit3Beats do
  @moduledoc """
  默认乐句分窗策略（windowing-post-rebase 默认策略）。

  ## 规则

  1. 按 Timeline **active 序**取 note cores。
  2. Hard glue：`slice_flag == :force_merge` 的音符与**后一个** active 音符不可切开；
     `:force_slice` 强制在该音符前切开（即使空隙不足 3 拍）。
  3. Intervention：对 `channel` pattern match；当前实现凡 `scope: {start, end}`
     合法的均并入 content（`:pitch` / `:phoneme_timing` / 其它带 scope 的）。
     无 `scope` 的 iv 不撑窗。
  4. 相邻 content 空档 `gap`：
     - `gap < 3 * beat_ticks` → 粘连
     - `gap >= 3 * beat_ticks` → 切开；**前 1 拍归前片，后 2 拍归后片**；
       更长空隙中间为死区（不进任一切片）

  ## 一拍

  `opts.beat_ticks` 优先；否则 `opts.tpqn`（默认 480）当作一拍
  （无 TimeSig 时的显式假定：四分音符 = 一拍）。
  `time_sig_map` 接入推后——有拍号表时再换成「切点前块端」推导。

  ## Caveats

  - scope 与 note 完全不相交时，作为独立 content span 参与合并/切开。
  - 暂不做引擎 pad（pad 后置（Host））。
  """

  @behaviour Zongzi.Windowing.Strategy

  alias Zongzi.Windowing.{Context, Slice}
  alias Zongzi.Timeline.Query
  alias Zongzi.Intervention

  @impl true
  def window(%Context{} = ctx) do
    beat = beat_ticks(ctx)
    threshold = 3 * beat

    with {:ok, note_spans} <- build_note_spans(ctx),
         spans = note_spans ++ intervention_spans(ctx.interventions),
         spans = Enum.sort_by(spans, & &1.start) do
      blocks =
        spans
        |> merge_spans(threshold, beat, ctx)
        |> apply_cut_ownership(threshold, beat)

      slices =
        Enum.reduce_while(blocks, {:ok, []}, fn block, {:ok, acc} ->
          case Slice.new(block.start, block.end, Enum.uniq(block.seq_ids)) do
            {:ok, slice} -> {:cont, {:ok, [slice | acc]}}
            {:error, _} = err -> {:halt, err}
          end
        end)

      case slices do
        {:ok, list} -> {:ok, Enum.reverse(list)}
        {:error, _} = err -> err
      end
    end
  end

  # ---- beat ----

  defp beat_ticks(%Context{opts: opts}) do
    cond do
      is_integer(opts[:beat_ticks]) and opts[:beat_ticks] > 0 -> opts[:beat_ticks]
      is_integer(opts[:tpqn]) and opts[:tpqn] > 0 -> opts[:tpqn]
      true -> 480
    end
  end

  # ---- note cores ----

  defp build_note_spans(%Context{timeline: tl, notes_by_seq: notes}) do
    active =
      tl.note_order
      |> Enum.filter(&Query.active?(tl, &1))

    missing =
      Enum.reject(active, &Map.has_key?(notes, &1))

    if missing != [] do
      {:error, {:missing_notes_for_seq, missing}}
    else
      spans =
        Enum.map(active, fn sid ->
          n = Map.fetch!(notes, sid)

          %{
            start: n.start_tick,
            end: n.start_tick + n.duration_tick,
            seq_ids: [sid],
            force_merge_after?: n.slice_flag == :force_merge,
            force_slice_before?: n.slice_flag == :force_slice
          }
        end)

      {:ok, spans}
    end
  end

  # ---- interventions by channel ----

  defp intervention_spans(ivs) do
    ivs
    |> Enum.map(&expand_intervention/1)
    |> Enum.reject(&is_nil/1)
  end

  # channel 分派：有合法 scope 的一律撑 content；后续 channel 可改写子句
  defp expand_intervention(%Intervention{channel: :pitch, scope: scope}),
    do: scope_to_span(scope)

  defp expand_intervention(%Intervention{channel: :phoneme_timing, scope: scope}),
    do: scope_to_span(scope)

  defp expand_intervention(%Intervention{channel: _other, scope: scope}),
    do: scope_to_span(scope)

  defp scope_to_span({s, e}) when is_integer(s) and is_integer(e) and e > s do
    %{
      start: s,
      end: e,
      seq_ids: [],
      force_merge_after?: false,
      force_slice_before?: false
    }
  end

  defp scope_to_span(_), do: nil

  # ---- merge ----

  # 将已排序 spans 合成 content blocks；threshold 用于「小缝必粘」
  # force_merge_after on a span glues to the next span regardless of gap
  # force_slice_before forces a cut before that span (unless force_merge from prev wins? glue wins)
  defp merge_spans([], _threshold, _beat, _ctx), do: []

  defp merge_spans([first | rest], threshold, _beat, _ctx) do
    Enum.reduce(rest, {[first], first}, fn span, {acc, prev} ->
      gap = span.start - prev.end
      glue? = prev.force_merge_after? == true
      force_cut? = span.force_slice_before? == true and not glue?

      cond do
        glue? or (gap < threshold and not force_cut?) ->
          merged = %{
            start: min(prev.start, span.start),
            end: max(prev.end, span.end),
            seq_ids: prev.seq_ids ++ span.seq_ids,
            force_merge_after?: span.force_merge_after?,
            force_slice_before?: false
          }

          {List.replace_at(acc, -1, merged), merged}

        true ->
          {acc ++ [span], span}
      end
    end)
    |> elem(0)
  end

  # 对已切开的相邻块应用 1/2 空拍归属（仅当 gap >= threshold）
  # merge_spans 已在 gap < threshold 时粘连，故此处相邻块 gap 必 >= threshold
  # （除非 force_slice 造成 gap < threshold 的切开）
  defp apply_cut_ownership([], _threshold, _beat), do: []
  defp apply_cut_ownership([only], _threshold, _beat), do: [only]

  defp apply_cut_ownership(blocks, threshold, beat) do
    blocks
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce({[], hd(blocks)}, fn [_left, right], {done, cur_left} ->
      gap = right.start - cur_left.end

      {left2, right2} =
        if gap >= threshold do
          {
            %{cur_left | end: cur_left.end + 1 * beat},
            %{right | start: right.start - 2 * beat}
          }
        else
          # force_slice 等造成的小缝切开：不吞空拍，边界贴 content
          {cur_left, right}
        end

      # 校正：归属后不得交叉
      {left2, right2} =
        if left2.end > right2.start do
          mid = div(cur_left.end + right.start, 2)
          {%{left2 | end: mid}, %{right2 | start: mid}}
        else
          {left2, right2}
        end

      {done ++ [left2], right2}
    end)
    |> then(fn {done, last} -> done ++ [last] end)
  end
end
