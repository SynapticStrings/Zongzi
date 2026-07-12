defmodule Zongzi.TimelineTest do
  use ExUnit.Case, async: true

  alias Zongzi.Util.ID
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Timeline

  # ---- helpers ----

  defp build_note(attrs) do
    {:ok, key} = Key.TwelveET.new(60)
    defaults = [id: ID.generate_id("Note_"), start_tick: 0, duration_tick: 480, key: key, lyric: "\u3042"]
    Note.new(Keyword.merge(defaults, attrs) |> Enum.into(%{}))
  end

  # ---- new ----

  describe "new/1" do
    test "\u521b\u5efa\u7a7a Timeline" do
      track_id = "track_01"
      {:ok, tl} = Timeline.new(track_id)
      assert tl.track_id == track_id
      assert tl.note_order == []
      assert tl.seq_map == %{}
      assert tl.tombstones == MapSet.new()
    end
  end

  # ---- insert_note ----

  describe "insert_note/2" do
    test "\u63d2\u5165\u97f3\u7b26\u5230\u7a7a Timeline" do
      {:ok, note} = build_note([])
      {:ok, tl} = Timeline.new("track_01")

      {:ok, tl, note} = Timeline.insert_note(tl, note)
      assert tl.note_order == [note.seq_id]
      assert tl.seq_map[note.seq_id] == note.id
    end

    test "\u8fde\u7eed\u63d2\u5165\u4fdd\u6301\u987a\u5e8f" do
      {:ok, n1} = build_note(start_tick: 0)
      {:ok, n2} = build_note(start_tick: 480)
      {:ok, n3} = build_note(start_tick: 960)
      {:ok, tl} = Timeline.new("t1")

      {:ok, tl, n1} = Timeline.insert_note(tl, n1)
      {:ok, tl, n2} = Timeline.insert_note(tl, n2)
      {:ok, tl, n3} = Timeline.insert_note(tl, n3)

      assert tl.note_order == [n1.seq_id, n2.seq_id, n3.seq_id]
    end

    test "\u5df2\u6709 seq_id \u7684\u4e0d\u91cd\u65b0\u751f\u6210" do
      {:ok, note} = build_note(seq_id: 42)
      {:ok, tl} = Timeline.new("t1")

      {:ok, _tl, note} = Timeline.insert_note(tl, note)
      assert note.seq_id == 42
    end
  end

  # ---- split_note ----

  describe "split_note/3" do
    test "\u5728\u4e2d\u95f4\u5207\u5f00\uff1a\u539f seq_id \u4fdd\u7559\uff0c\u65b0 seq_id \u7d27\u968f\u5176\u540e" do
      {:ok, n1} = build_note(start_tick: 0)
      {:ok, n2} = build_note(start_tick: 480)
      {:ok, n3} = build_note(start_tick: 960)
      {:ok, tl} = Timeline.new("t1")
      {:ok, tl, n1} = Timeline.insert_note(tl, n1)
      {:ok, tl, n2} = Timeline.insert_note(tl, n2)
      {:ok, tl, n3} = Timeline.insert_note(tl, n3)

      {:ok, tl, orig_seq, new_seq} = Timeline.split_note(tl, n2.seq_id, 240)
      assert tl.note_order == [n1.seq_id, orig_seq, new_seq, n3.seq_id]
      assert orig_seq == n2.seq_id
      assert new_seq != orig_seq
    end

    test "\u4e0d\u5b58\u5728\u7684 seq_id \u62a5\u9519" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.split_note(tl, 99999, 100) == {:error, {:not_found, 99999}}
    end
  end

  # ---- drag_note ----

  describe "drag_note/3" do
    test "\u62d6\u62fd\u5230\u672b\u5c3e" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      {:ok, tl} = Timeline.drag_note(tl, b, 2)
      assert tl.note_order == [a, c, b]
    end

    test "\u62d6\u62fd\u5230\u5f00\u5934" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      {:ok, tl} = Timeline.drag_note(tl, c, 0)
      assert tl.note_order == [c, a, b]
    end

    test "\u62d6\u62fd\u5893\u7891\u62d2\u7edd" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged_note")

      assert Timeline.drag_note(tl, c, 0) == {:error, {:is_tombstone, c}}
    end

    test "seq_id \u4e0d\u5b58\u5728\u62a5\u9519" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.drag_note(tl, 99999, 0) == {:error, {:not_found, 99999}}
    end
  end

  # ---- merge_notes ----

  describe "merge_notes/4" do
    test "\u5408\u5e76\u4e24\u4e2a\u76f8\u90bb\u97f3\u7b26\uff1a\u524d\u4fdd\u7559\u540e\u5893\u7891" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged_bc")

      assert tl.seq_map[b] == "merged_bc"
      assert MapSet.member?(tl.tombstones, c)
      assert tl.note_order == [a, b, c]
    end

    test "\u5408\u5e76\u5df2\u5893\u7891\u62d2\u7edd" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")
      assert Timeline.merge_notes(tl, c, b, "bad") == {:error, {:is_tombstone, c}}
    end
  end

  # ---- adjacent ----

  describe "adjacent/2" do
    test "\u4e2d\u95f4\u5143\u7d20\u8fd4\u56de prev/current/next" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      assert Timeline.adjacent(tl, b) == {:ok, {a, b, c}}
    end

    test "\u9996\u4e2a\u5143\u7d20\u7684 prev \u4e3a nil" do
      {:ok, tl} = build_timeline_3()
      [a | _] = tl.note_order

      assert {:ok, {nil, ^a, _}} = Timeline.adjacent(tl, a)
    end

    test "\u672b\u5c3e\u5143\u7d20\u7684 next \u4e3a nil" do
      {:ok, tl} = build_timeline_3()
      order = tl.note_order
      last = List.last(order)

      assert {:ok, {_, ^last, nil}} = Timeline.adjacent(tl, last)
    end

    test "\u5893\u7891\u8fd4\u56de :tombstone" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")

      assert Timeline.adjacent(tl, c) == {:tombstone, c}
    end

    test "\u4e0d\u5b58\u5728\u8fd4\u56de :not_found" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.adjacent(tl, 99999) == {:error, :not_found}
    end
  end

  # ---- try_match ----

  describe "try_match/2" do
    test "3/3 \u5b8c\u5168\u5339\u914d" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 3}
    end

    test "\u62d6\u62fd\u4e2d\u95f4\u5143\u7d20\u7834\u574f 2/3\uff0c\u53ea\u5269 current \u5339\u914d" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      # \u62d6 b \u5230\u6700\u540e: [a, c, b] -> adjacent(b) = {c, b, nil}
      # prev: a!=c, next: c!=nil -> 1/3
      {:ok, tl} = Timeline.drag_note(tl, b, 2)
      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 1}
    end

    test "\u62d6\u62fd\u540e 2/3 \u5339\u914d\uff08prev+current \u5b58\u6d3b\uff09" do
      # 4 \u97f3\u7b26: [a, b, c, d]\uff0c\u951a\u5728 {a, b, c}
      # \u62d6 c \u5230\u5f00\u5934 -> [c, a, b, d] -> adjacent(b) = {a, b, d}
      # prev OK, current OK, next fail -> 2/3
      {:ok, n_a} = build_note(start_tick: 0)
      {:ok, n_b} = build_note(start_tick: 480)
      {:ok, n_c} = build_note(start_tick: 960)
      {:ok, n_d} = build_note(start_tick: 1440)
      {:ok, tl} = Timeline.new("t1")
      {:ok, tl, _} = Timeline.insert_note(tl, n_a)
      {:ok, tl, _} = Timeline.insert_note(tl, n_b)
      {:ok, tl, _} = Timeline.insert_note(tl, n_c)
      {:ok, tl, _} = Timeline.insert_note(tl, n_d)

      [a, b, c, d] = tl.note_order

      # \u951a\u5728 {a, b, c}
      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 3}

      # \u62d6 c \u5230\u5f00\u5934
      {:ok, tl} = Timeline.drag_note(tl, c, 0)
      assert tl.note_order == [c, a, b, d]
      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 2}
    end

    test "current \u662f\u5893\u7891 -> :tombstone" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")

      assert Timeline.try_match(tl, {b, c, nil}) == {:tombstone, c}
    end

    test "current \u4e0d\u5728 Timeline -> :not_found" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.try_match(tl, {nil, 99999, nil}) == {:error, :not_found}
    end
  end

  # ---- helper ----

  defp build_timeline_3 do
    {:ok, n1} = build_note(start_tick: 0)
    {:ok, n2} = build_note(start_tick: 480)
    {:ok, n3} = build_note(start_tick: 960)
    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, _} = Timeline.insert_note(tl, n1)
    {:ok, tl, _} = Timeline.insert_note(tl, n2)
    {:ok, tl, _} = Timeline.insert_note(tl, n3)
    {:ok, tl}
  end
end
