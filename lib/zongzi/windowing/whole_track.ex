defmodule Zongzi.Windowing.WholeTrack do
  @moduledoc """
  恒将全部 active note 收成单一的 Segment ，用于不需要 phrase
  cache 或兼容 UTAU 等的情况。

  无条件将所有的 active notes 组合成一个 Segment 。若无
  active note 且无 scope 时返回空列表。
  """

  @behaviour Zongzi.Windowing.Strategy

  alias Zongzi.Windowing.{Context, Segment}
  alias Zongzi.Timeline
  alias Zongzi.Timeline.Query
  import Zongzi.Score.Tick

  @impl true
  def window(%Context{timeline: timeline, notes_by_seq: notes, interventions: intervs} = ctx) do
    seq_ids =
      Timeline.to_list(timeline)
      |> Enum.filter(&Query.active?(timeline, &1))
      |> Enum.filter(&Map.has_key?(notes, &1))

    note_spans =
      Enum.map(seq_ids, fn sid ->
        n = Map.fetch!(notes, sid)
        {n.start_tick, n.start_tick + n.duration_tick, [sid]}
      end)

    scope_spans =
      intervs
      |> Enum.map(&scope_span/1)
      |> Enum.reject(&is_nil/1)

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

  defp scope_span(%{scope: {s, e}})
       when is_numeric_tick(s) and is_numeric_tick(e) and e > s,
       do: {s, e, []}

  defp scope_span(_), do: nil
end
