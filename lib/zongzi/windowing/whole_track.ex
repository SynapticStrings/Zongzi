defmodule Zongzi.Windowing.WholeTrack do
  @moduledoc """
  恒将全部 active note 收成单一的 Segment ，用于不需要 phrase
  cache 或兼容 UTAU 等的情况。

  无条件将所有的 active notes 组合成一个 Segment 。若无
  active note 且无 scope 时返回空列表。

  scope 由 `Declaration.scope/2` 现场计算（不读 struct 缓存）。
  """

  @behaviour Zongzi.Windowing.Strategy

  alias Zongzi.Windowing.{Context, Segment}
  alias Zongzi.Timeline
  alias Zongzi.Timeline.Query
  import Zongzi.Score.Tick

  @impl true
  def window(%Context{timeline: timeline, notes_by_seq: notes, interventions: intervs} = ctx) do
    scope_ctx = Context.scope_ctx(ctx)

    seq_ids =
      Timeline.to_list(timeline)
      |> Enum.filter(&Query.active?(timeline, &1))
      |> Enum.filter(&Map.has_key?(notes, &1))

    note_spans =
      Enum.map(seq_ids, fn sid ->
        n = Map.fetch!(notes, sid)
        {n.start_tick, n.start_tick + n.duration_tick, [sid]}
      end)

    with {:ok, scope_spans} <- scope_spans(intervs, scope_ctx) do
      case note_spans ++ scope_spans do
        [] ->
          {:ok, %{ctx | current_segments: []}}

        spans ->
          start_tick = spans |> Enum.map(&elem(&1, 0)) |> Enum.min()
          end_tick = spans |> Enum.map(&elem(&1, 1)) |> Enum.max()
          members = spans |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq()

          case Segment.new(start_tick, end_tick, members) do
            {:ok, slice} -> {:ok, %{ctx | current_segments: [slice]}}
            {:error, _} = err -> err
          end
      end
    end
  end

  defp scope_spans(intervs, scope_ctx) do
    intervs
    |> Enum.reduce_while({:ok, []}, fn int, {:ok, acc} ->
      case scope_span(int, scope_ctx) do
        {:ok, span} -> {:cont, {:ok, [span | acc]}}
        {:error, _} = err -> {:halt, err}
        nil -> {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, spans} -> {:ok, Enum.reverse(spans)}
      {:error, _} = err -> err
    end
  end

  defp scope_span(%{declaration: decl} = int, scope_ctx) do
    case decl.scope(int, scope_ctx) do
      {s, e} when is_numeric_tick(s) and is_numeric_tick(e) and e > s ->
        {:ok, {s, e, []}}

      {:seconds, s, e} when is_float(s) and is_float(e) and e > s ->
        with {:ok, {tick_s, tick_e}} <- Context.normalize_scope({:seconds, s, e}, scope_ctx) do
          {:ok, {tick_s, tick_e, []}}
        end

      _ ->
        nil
    end
  end
end
