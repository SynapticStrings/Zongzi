defmodule Zongzi.Windowing.WholeTrack do
  @moduledoc """
  恒将全部 active note 收成**一个** Segment（UTAU / 无 phrase cache 友好）。

  忽略 rest 阈值；仍会把带 `scope: {s,e}` 的 intervention 并入 tick 范围。
  无 active note 且无 scope 时返回空列表。
  """

  @behaviour Zongzi.Windowing.Strategy

  alias Zongzi.Windowing.{Context, Segment}
  alias Zongzi.Timeline.Query

  @impl true
  def window(%Context{timeline: tl, notes_by_seq: notes, interventions: ivs}) do
    seq_ids =
      tl.note_order
      |> Enum.filter(&Query.active?(tl, &1))
      |> Enum.filter(&Map.has_key?(notes, &1))

    note_spans =
      Enum.map(seq_ids, fn sid ->
        n = Map.fetch!(notes, sid)
        {n.start_tick, n.start_tick + n.duration_tick, [sid]}
      end)

    scope_spans =
      ivs
      |> Enum.map(&scope_span/1)
      |> Enum.reject(&is_nil/1)

    case note_spans ++ scope_spans do
      [] ->
        {:ok, []}

      spans ->
        start_tick = spans |> Enum.map(&elem(&1, 0)) |> Enum.min()
        end_tick = spans |> Enum.map(&elem(&1, 1)) |> Enum.max()
        members = spans |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq()

        case Segment.new(start_tick, end_tick, members) do
          {:ok, slice} -> {:ok, [slice]}
          {:error, _} = err -> err
        end
    end
  end

  defp scope_span(%{scope: {s, e}})
       when is_integer(s) and is_integer(e) and e > s,
       do: {s, e, []}

  defp scope_span(_), do: nil
end
