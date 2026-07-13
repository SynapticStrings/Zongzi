defmodule Zongzi.Timeline.QueryTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Timeline, Score.Note}

  # ---- helpers ----

  # build_tl returns {tl, notes_with_seq_ids}
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
    id = "Note_#{System.unique_integer([:positive])}"
    base = %{id: id, start_tick: 0, duration_tick: 480, key: %Zongzi.Score.Key.TwelveET{midi: 60}}
    attrs = Map.merge(base, overrides)
    {:ok, n} = Note.new(attrs)
    n
  end

  describe "status/2" do
    test "active" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      assert Timeline.Query.status(tl, a.seq_id) == :active
      assert Timeline.Query.status(tl, b.seq_id) == :active
      assert Timeline.Query.status(tl, c.seq_id) == :active
    end

    test "missing for unknown seq_id" do
      {tl, _} = build_tl([note()])
      assert Timeline.Query.status(tl, 99999) == :missing
    end

    test "merge_tombstone after merge" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      {:ok, tl, _merged} = Timeline.merge_notes(tl, a, b, "merged_note")
      assert Timeline.Query.status(tl, a.seq_id) == :active
      assert Timeline.Query.status(tl, b.seq_id) == :merge_tombstone
    end

    test "delete_tombstone after delete" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      {:ok, tl} = Timeline.delete_note(tl, a.seq_id)
      assert Timeline.Query.status(tl, a.seq_id) == :delete_tombstone
      assert Timeline.Query.status(tl, b.seq_id) == :active
    end

    test "active? alias" do
      {tl, notes} = build_tl([note()])
      [a] = notes
      assert Timeline.Query.active?(tl, a.seq_id)
      refute Timeline.Query.active?(tl, a.seq_id + 999)
    end
  end

  describe "scan/4" do
    test "prev direction active_only" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      assert Timeline.Query.scan(tl, c.seq_id, :prev) == [b.seq_id, a.seq_id]
    end

    test "next direction active_only" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      assert Timeline.Query.scan(tl, a.seq_id, :next) == [b.seq_id, c.seq_id]
    end

    test "limit" do
      {tl, notes} = build_tl([note(), note(), note(), note()])
      [_a, _b, _c, d] = notes
      result = Timeline.Query.scan(tl, d.seq_id, :prev, limit: 2)
      assert length(result) == 2
    end

    test "max_hops" do
      {tl, notes} = build_tl([note(), note(), note()])
      [_a, _b, c] = notes
      result = Timeline.Query.scan(tl, c.seq_id, :prev, max_hops: 1)
      assert length(result) <= 1
    end

    test "include_self" do
      {tl, notes} = build_tl([note(), note()])
      [a, _b] = notes
      result = Timeline.Query.scan(tl, a.seq_id, :next, include_self: true, active_only: false)
      assert hd(result) == a.seq_id
    end

    test "active_only false includes tombstones" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, _c] = notes
      {:ok, tl} = Timeline.delete_note(tl, b.seq_id)
      result = Timeline.Query.scan(tl, a.seq_id, :next, active_only: false)
      assert b.seq_id in result
    end

    test "active_only true skips tombstones" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      {:ok, tl} = Timeline.delete_note(tl, b.seq_id)
      result = Timeline.Query.scan(tl, a.seq_id, :next, active_only: true)
      refute b.seq_id in result
      assert c.seq_id in result
    end

    test "missing start returns empty" do
      {tl, _} = build_tl([note()])
      assert Timeline.Query.scan(tl, 99999, :next) == []
    end
  end

  describe "neighborhood/3" do
    test "default count:1 active_only:false mirrors adjacent raw neighbors" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      nb = Timeline.Query.neighborhood(tl, b.seq_id)
      assert nb.focus == b.seq_id
      assert nb.focus_status == :active
      assert length(nb.left) == 1
      assert length(nb.right) == 1
      assert hd(nb.left).seq_id == a.seq_id
      assert hd(nb.right).seq_id == c.seq_id
    end

    test "count:2 collects two per side" do
      {tl, notes} = build_tl([note(), note(), note(), note()])
      [_a, b, _c, _d] = notes
      nb = Timeline.Query.neighborhood(tl, b.seq_id, count: 2)
      assert length(nb.left) == 1
      assert length(nb.right) == 2
    end

    test "active_only:true skips tombstones" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      {:ok, tl} = Timeline.delete_note(tl, b.seq_id)
      nb = Timeline.Query.neighborhood(tl, a.seq_id, active_only: true, count: 2)
      assert nb.focus == a.seq_id
      assert hd(nb.right).seq_id == c.seq_id
      assert Enum.all?(nb.right, &(&1.status == :active))
    end

    test "focus at head has empty left" do
      {tl, notes} = build_tl([note(), note()])
      [a, _b] = notes
      nb = Timeline.Query.neighborhood(tl, a.seq_id)
      assert nb.left == []
    end

    test "focus at tail has empty right" do
      {tl, notes} = build_tl([note(), note()])
      [_a, b] = notes
      nb = Timeline.Query.neighborhood(tl, b.seq_id)
      assert nb.right == []
    end

    test "missing focus" do
      {tl, _} = build_tl([note()])
      nb = Timeline.Query.neighborhood(tl, 99999)
      assert nb.focus_status == :missing
      assert nb.left == []
      assert nb.right == []
    end
  end

  describe "scrub_triplet/2" do
    test "active focus gets clean triplet" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      assert Timeline.Query.scrub_triplet(tl, b.seq_id) == {:ok, {a.seq_id, b.seq_id, c.seq_id}}
    end

    test "scrubs tombstones from neighbors" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      {:ok, tl} = Timeline.delete_note(tl, b.seq_id)
      assert Timeline.Query.scrub_triplet(tl, c.seq_id) == {:ok, {a.seq_id, c.seq_id, nil}}
    end

    test "head focus gets nil prev" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      assert Timeline.Query.scrub_triplet(tl, a.seq_id) == {:ok, {nil, a.seq_id, b.seq_id}}
    end

    test "tail focus gets nil next" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      assert Timeline.Query.scrub_triplet(tl, b.seq_id) == {:ok, {a.seq_id, b.seq_id, nil}}
    end

    test "tombstone focus returns error" do
      {tl, notes} = build_tl([note(), note()])
      [a, _b] = notes
      {:ok, tl} = Timeline.delete_note(tl, a.seq_id)
      assert Timeline.Query.scrub_triplet(tl, a.seq_id) == {:error, :not_active}
    end
  end

  describe "hops/3" do
    test "adjacent notes have hop 1" do
      {tl, notes} = build_tl([note(), note()])
      [a, b] = notes
      assert Timeline.Query.hops(tl, a.seq_id, b.seq_id) == {:ok, 1}
    end

    test "same note hop 0" do
      {tl, notes} = build_tl([note()])
      [a] = notes
      assert Timeline.Query.hops(tl, a.seq_id, a.seq_id) == {:ok, 0}
    end

    test "tombstones counted in hops" do
      {tl, notes} = build_tl([note(), note(), note()])
      [a, b, c] = notes
      {:ok, tl} = Timeline.delete_note(tl, b.seq_id)
      assert Timeline.Query.hops(tl, a.seq_id, c.seq_id) == {:ok, 2}
    end

    test "missing returns error" do
      {tl, notes} = build_tl([note()])
      [a] = notes
      assert Timeline.Query.hops(tl, a.seq_id, 99999) == {:error, :not_found}
    end
  end
end
