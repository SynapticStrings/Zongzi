defmodule Zongzi.Anchor.TripletMatchTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Timeline, Score.Note, Anchor.TripletMatch}

  defp build_tl(notes) do
    {:ok, tl} = Timeline.new("track_1")

    {tl, acc} =
      Enum.reduce(notes, {tl, []}, fn note, {tl, acc} ->
        {:ok, tl, note} = Timeline.insert_note(tl, note)
        {tl, acc ++ [note]}
      end)

    {tl, acc}
  end

  defp note(overrides \\ %{}) do
    id = "Note_\#{System.unique_integer([:positive])}"
    base = %{id: id, start_tick: 0, duration_tick: 480, key: %Zongzi.Score.Key.TwelveET{midi: 60}}
    attrs = Map.merge(base, overrides)
    {:ok, n} = Note.new(attrs)
    n
  end

  describe "scrub_triplet/2" do
    test "active focus gets clean triplet" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      assert TripletMatch.scrub_triplet(tl, b.seq_id) == {:ok, {a.seq_id, b.seq_id, c.seq_id}}
    end

    test "scrubs tombstones from neighbors" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      {:ok, tl} = Timeline.delete_note(tl, b.seq_id)
      assert TripletMatch.scrub_triplet(tl, c.seq_id) == {:ok, {a.seq_id, c.seq_id, nil}}
    end

    test "head focus gets nil prev" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      assert TripletMatch.scrub_triplet(tl, a.seq_id) == {:ok, {nil, a.seq_id, b.seq_id}}
    end

    test "tail focus gets nil next" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      assert TripletMatch.scrub_triplet(tl, b.seq_id) == {:ok, {a.seq_id, b.seq_id, nil}}
    end

    test "tombstone focus returns error" do
      {tl, notes} = build_tl([note(), note()])
      [a, _b] = notes
      {:ok, tl} = Timeline.delete_note(tl, a.seq_id)
      assert TripletMatch.scrub_triplet(tl, a.seq_id) == {:error, :not_active}
    end
  end
end
