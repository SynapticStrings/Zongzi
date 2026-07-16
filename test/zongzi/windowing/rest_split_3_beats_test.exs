defmodule Zongzi.Windowing.RestSplit3BeatsTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Timeline, Intervention}
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Windowing.{Context, RestSplit3Beats, WholeTrack}

  defp note(start_tick, duration_tick, overrides \\ %{}) do
    id = "Note_#{System.unique_integer([:positive])}"
    {:ok, key} = Key.TwelveET.new(60)

    {:ok, n} =
      Note.new(
        Map.merge(
          %{
            id: id,
            start_tick: start_tick,
            duration_tick: duration_tick,
            key: key,
            lyric: "あ"
          },
          overrides
        )
      )

    n
  end

  defp build(notes, opts \\ []) do
    {:ok, tl} = Timeline.new("t1")

    {tl, acc} =
      Enum.reduce(notes, {tl, []}, fn n, {tl, acc} ->
        {:ok, tl, n} = Timeline.insert_note(tl, n)
        {tl, acc ++ [n]}
      end)

    notes_by_seq = Map.new(acc, &{&1.seq_id, &1})

    ctx =
      Context.new(%{
        timeline: tl,
        notes_by_seq: notes_by_seq,
        interventions: Keyword.get(opts, :interventions, []),
        opts: Keyword.get(opts, :opts, %{beat_ticks: 480})
      })

    {ctx, acc}
  end

  describe "empty / single" do
    test "no notes → empty" do
      {:ok, tl} = Timeline.new("t1")
      ctx = Context.new(%{timeline: tl, notes_by_seq: %{}, opts: %{beat_ticks: 480}})
      assert RestSplit3Beats.window(ctx) == {:ok, []}
    end

    test "single note → one slice on core" do
      {ctx, [n]} = build([note(0, 480)])
      assert {:ok, [s]} = RestSplit3Beats.window(ctx)
      assert s.start_tick == 0
      assert s.end_tick == 480
      assert s.seq_ids == [n.seq_id]
    end
  end

  describe "3-beat rest split + 1/2 ownership" do
    test "gap == 3 beats: cut, 1 beat to prev, 2 to next, no dead zone" do
      # beat=480; A [0,480), gap 1440, B @ 1920
      {ctx, [a, b]} = build([note(0, 480), note(1920, 480)])
      assert {:ok, [s1, s2]} = RestSplit3Beats.window(ctx)

      assert s1.seq_ids == [a.seq_id]
      assert s2.seq_ids == [b.seq_id]
      assert s1.end_tick == 960
      assert s2.start_tick == 960
    end

    test "gap > 3 beats: dead zone in the middle" do
      # gap = 4 beats = 1920; B @ 2400
      {ctx, [a, b]} = build([note(0, 480), note(2400, 480)])
      assert {:ok, [s1, s2]} = RestSplit3Beats.window(ctx)
      assert s1.end_tick == 960
      assert s2.start_tick == 1440
      assert s1.end_tick < s2.start_tick
      assert s1.seq_ids == [a.seq_id]
      assert s2.seq_ids == [b.seq_id]
    end

    test "gap < 3 beats: glue into one slice" do
      # gap = 2 beats; B @ 1440
      {ctx, [a, b]} = build([note(0, 480), note(1440, 480)])
      assert {:ok, [s]} = RestSplit3Beats.window(ctx)
      assert s.start_tick == 0
      assert s.end_tick == 1920
      assert s.seq_ids == [a.seq_id, b.seq_id]
    end
  end

  describe "intervention scope" do
    test "scope covering gap glues distant notes" do
      {ctx, [a, b]} = build([note(0, 480), note(5000, 480)])
      assert {:ok, [_, _]} = RestSplit3Beats.window(ctx)

      iv = %Intervention{
        id: "iv1",
        channel: :pitch,
        anchor: {nil, a.seq_id, nil},
        payload: %{},
        snapshot: %{},
        scope: {0, 5480}
      }

      ctx = %{ctx | interventions: [iv]}
      assert {:ok, [s]} = RestSplit3Beats.window(ctx)
      assert a.seq_id in s.seq_ids
      assert b.seq_id in s.seq_ids
      assert s.start_tick == 0
      assert s.end_tick == 5480
    end
  end

  describe "WholeTrack" do
    test "always one slice over all active notes" do
      {ctx, [a, b]} = build([note(0, 480), note(5000, 480)])
      assert {:ok, [s]} = WholeTrack.window(ctx)
      assert s.seq_ids == [a.seq_id, b.seq_id]
      assert s.start_tick == 0
      assert s.end_tick == 5480
    end
  end

  describe "errors" do
    test "missing notes_by_seq entry" do
      {:ok, key} = Key.TwelveET.new(60)

      {:ok, n} =
        Note.new(%{id: "n1", start_tick: 0, duration_tick: 480, key: key})

      {:ok, tl} = Timeline.new("t1")
      {:ok, tl, n} = Timeline.insert_note(tl, n)

      ctx = Context.new(%{timeline: tl, notes_by_seq: %{}, opts: %{beat_ticks: 480}})
      assert {:error, {:missing_notes_for_seq, [sid]}} = RestSplit3Beats.window(ctx)
      assert sid == n.seq_id
    end
  end
end
