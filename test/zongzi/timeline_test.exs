defmodule Zongzi.TimelineTest do
  use ExUnit.Case, async: true

  alias Zongzi.Util.ID
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Timeline

  doctest Zongzi.Timeline, import: true

  # ---- helpers ----

  defp build_note(attrs) do
    {:ok, key} = Key.TwelveET.new(60)

    defaults = [
      id: ID.generate_id("Note_"),
      start_tick: 0,
      duration_tick: 480,
      key: key,
      lyric: "あ"
    ]

    Note.new(Keyword.merge(defaults, attrs) |> Enum.into(%{}))
  end

  # ---- new ----

  describe "new/1" do
    test "创建空 Timeline" do
      track_id = "track_01"
      {:ok, tl} = Timeline.new(track_id)
      assert tl.track_id == track_id
      assert Timeline.to_list(tl) == []
      assert tl.seq_map == %{}
      assert tl.tombstones == MapSet.new()
    end
  end

  # ---- build ----

  describe "build/1" do
    test "从空 note_order 重建" do
      {:ok, tl} = Timeline.build(%{track_id: "t1", note_order: []})
      assert tl.track_id == "t1"
      assert tl.head == nil
      assert tl.tail == nil
      assert Timeline.to_list(tl) == []
      assert tl.next_seq == 1
    end

    test "从有序列表重建链表" do
      {:ok, tl} =
        Timeline.build(%{
          track_id: "t1",
          note_order: [1, 2, 3],
          seq_map: %{1 => "N_a", 2 => "N_b", 3 => "N_c"}
        })

      assert tl.head == 1
      assert tl.tail == 3
      assert Timeline.to_list(tl) == [1, 2, 3]
      assert tl.seq_map[2] == "N_b"
    end

    test "含墓碑的序列重建" do
      {:ok, tl} =
        Timeline.build(%{
          track_id: "t1",
          note_order: [1, 2, 3],
          seq_map: %{1 => "N_a", 3 => "N_c"},
          tombstones: [2]
        })

      assert Timeline.to_list(tl) == [1, 2, 3]
      assert MapSet.member?(tl.tombstones, 2)
      refute Map.has_key?(tl.seq_map, 2)
    end

    test "指定 next_seq" do
      {:ok, tl} =
        Timeline.build(%{
          track_id: "t1",
          note_order: [5, 6],
          next_seq: 100
        })

      assert tl.next_seq == 100
    end

    test "next_seq 默认为 max + 1" do
      {:ok, tl} =
        Timeline.build(%{
          track_id: "t1",
          note_order: [5, 6, 10]
        })

      assert tl.next_seq == 11
    end
  end

  # ---- generate ----

  describe "generate/1" do
    test "生成递增的 SeqID（用于 new/1）" do
      {:ok, tl} = Timeline.new("t1")
      {id1, tl} = Timeline.generate(tl)
      {id2, _tl} = Timeline.generate(tl)

      assert id1 > 0
      assert id2 == id1 + 1
    end

    test "从指定 next_seq 起算（用于 build/1）" do
      {:ok, tl} = Timeline.new("t1")
      {id, _tl} = %{tl | next_seq: 100} |> Timeline.generate()
      assert id == 100
    end
  end

  # ---- insert_note ----

  describe "insert_note/2" do
    test "插入音符到空 Timeline" do
      {:ok, note} = build_note([])
      {:ok, tl} = Timeline.new("track_01")

      {:ok, tl, note} = Timeline.insert_note(tl, note)
      assert Timeline.to_list(tl) == [note.seq_id]
      assert tl.seq_map[note.seq_id] == note.id
    end

    test "连续插入保持顺序" do
      # 注意：是插入的顺序而不是 start_tick 的顺序
      # 其交给 Track 管理
      {:ok, n1} = build_note(start_tick: 0)
      {:ok, n2} = build_note(start_tick: 480)
      {:ok, n3} = build_note(start_tick: 960)
      {:ok, tl} = Timeline.new("t1")

      {:ok, tl, n1} = Timeline.insert_note(tl, n1)
      {:ok, tl, n2} = Timeline.insert_note(tl, n2)
      {:ok, tl, n3} = Timeline.insert_note(tl, n3)

      assert Timeline.to_list(tl) == [n1.seq_id, n2.seq_id, n3.seq_id]
    end

    test "已有 seq_id 的不重新生成" do
      {:ok, note} = build_note(seq_id: 42)
      {:ok, tl} = Timeline.new("t1")

      {:ok, _tl, note} = Timeline.insert_note(tl, note)
      assert note.seq_id == 42
    end
  end

  # ---- insert ----

  describe "insert_note_before/3" do
    test "在指定 seq 之前插入" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, note} = build_note(start_tick: 480)

      {:ok, tl, note} = Timeline.insert_note_before(tl, note, b)
      assert Timeline.to_list(tl) == [a, note.seq_id, b, c]
    end

    test "在 head 之前插入" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, note} = build_note(start_tick: 0)

      {:ok, tl, note} = Timeline.insert_note_before(tl, note, a)
      assert Timeline.to_list(tl) == [note.seq_id, a, b, c]
    end
  end

  describe "insert_note_after/3" do
    test "在指定 seq 之后插入" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, note} = build_note(start_tick: 480)

      {:ok, tl, note} = Timeline.insert_note_after(tl, note, a)
      assert Timeline.to_list(tl) == [a, note.seq_id, b, c]
    end

    test "在 tail 之后插入" do
      {:ok, tl, _notes} = build_timeline_3()
      {:ok, note} = build_note(start_tick: 1440)

      {:ok, tl, note} = Timeline.insert_note_after(tl, note, List.last(Timeline.to_list(tl)))
      assert List.last(Timeline.to_list(tl)) == note.seq_id
    end
  end

  # ---- split_note ----

  describe "split_note/3" do
    test "在中间切开：原 seq_id 保留，新 seq_id 紧随其后" do
      {:ok, n1} = build_note(start_tick: 0)
      {:ok, n2} = build_note(start_tick: 480)
      {:ok, n3} = build_note(start_tick: 960)
      {:ok, tl} = Timeline.new("t1")
      {:ok, tl, n1} = Timeline.insert_note(tl, n1)
      {:ok, tl, n2} = Timeline.insert_note(tl, n2)
      {:ok, tl, n3} = Timeline.insert_note(tl, n3)

      # n2: start=480, dur=480, end=960. Split halfway at 720.
      split_tick = 720
      new_id = Zongzi.Util.ID.generate_id("N_")
      {:ok, tl, before_note, after_note} = Timeline.split_note(tl, n2, split_tick, new_id)
      assert Timeline.to_list(tl) == [n1.seq_id, before_note.seq_id, after_note.seq_id, n3.seq_id]
      assert before_note.seq_id == n2.seq_id
      assert before_note.start_tick == 480
      assert before_note.duration_tick == 240
      assert after_note.start_tick == 720
      assert after_note.duration_tick == 240
      assert after_note.id == new_id
      assert after_note.seq_id != before_note.seq_id
    end

    test "不存在的 seq_id 报错" do
      {:ok, tl} = Timeline.new("t1")
      {:ok, note} = build_note(start_tick: 0)
      bogus_note = %{note | seq_id: 99999}
      assert Timeline.split_note(tl, bogus_note, 100, "new_id") == {:error, {:not_found, 99999}}
    end
  end

  # ---- move_note ----

  describe "move_note/4" do
    test "拖拽到末尾" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)

      {:ok, tl} = Timeline.move_note(tl, b, c, :after)
      assert Timeline.to_list(tl) == [a, c, b]
    end

    test "拖拽到开头" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)

      {:ok, tl} = Timeline.move_note(tl, c, a, :before)
      assert Timeline.to_list(tl) == [c, a, b]
    end

    test "拖拽墓碑拒绝" do
      {:ok, tl, [_n1, n2, n3]} = build_timeline_3()
      [_a, _b, c] = Timeline.to_list(tl)
      {:ok, tl, _merged} = Timeline.merge_notes(tl, n2, n3, "merged_note")

      assert Timeline.move_note(tl, c, c, :before) == {:error, {:is_tombstone, c}}
    end

    test "seq_id 不存在报错" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.move_note(tl, 99999, 99999, :before) == {:error, {:not_found, 99999}}
    end
  end

  # ---- splice_after ----

  describe "splice_after/3" do
    test "空列表不变" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, tl, []} = Timeline.splice_after(tl, [], a)
      assert Timeline.to_list(tl) == [a, b, c]
    end

    test "在中间 splice 一组音符" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, n1} = build_note(start_tick: 240)
      {:ok, n2} = build_note(start_tick: 360)

      {:ok, tl, inserted} = Timeline.splice_after(tl, [n1, n2], a)
      assert length(inserted) == 2
      assert Timeline.to_list(tl) == [a, hd(inserted).seq_id, List.last(inserted).seq_id, b, c]
    end

    test "在 tail splice" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, note} = build_note(start_tick: 1440)

      {:ok, tl, [inserted]} = Timeline.splice_after(tl, [note], c)
      assert tl.tail == inserted.seq_id
      assert Timeline.to_list(tl) == [a, b, c, inserted.seq_id]
    end

    test "target 不存在报错" do
      {:ok, tl, _notes} = build_timeline_3()
      {:ok, note} = build_note([])
      assert Timeline.splice_after(tl, [note], 99999) == {:error, {:not_found, 99999}}
    end
  end

  # ---- delete_range ----

  describe "delete_range/3" do
    test "删除单个" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)
      {:ok, tl} = Timeline.delete_range(tl, b, b)
      assert Timeline.to_list(tl) == [a, b, c]
      assert MapSet.member?(tl.tombstones, b)
      refute Map.has_key?(tl.seq_map, b)
    end

    test "删除连续范围" do
      {:ok, tl, _notes} = build_timeline_4()
      [a, b, c, d] = Timeline.to_list(tl)
      {:ok, tl} = Timeline.delete_range(tl, b, c)
      assert Timeline.to_list(tl) == [a, b, c, d]
      assert MapSet.member?(tl.tombstones, b)
      assert MapSet.member?(tl.tombstones, c)
      refute Map.has_key?(tl.seq_map, b)
      refute Map.has_key?(tl.seq_map, c)
    end

    test "from > to 报错" do
      {:ok, tl, _notes} = build_timeline_3()
      [a, b, _c] = Timeline.to_list(tl)
      assert Timeline.delete_range(tl, b, a) == {:error, {:range_not_found, a}}
    end
  end

  # ---- merge_notes ----

  describe "merge_notes/4" do
    test "合并两个相邻音符：前保留后墓碑" do
      {:ok, tl, [_n1, n2, n3]} = build_timeline_3()
      [a, b, c] = Timeline.to_list(tl)

      {:ok, tl, _merged} = Timeline.merge_notes(tl, n2, n3, "merged_bc")

      assert tl.seq_map[b] == "merged_bc"
      assert MapSet.member?(tl.tombstones, c)
      assert Timeline.to_list(tl) == [a, b, c]
    end

    test "合并已墓碑拒绝" do
      {:ok, tl, [_n1, n2, n3]} = build_timeline_3()
      [_a, _b, c] = Timeline.to_list(tl)
      {:ok, tl, _merged} = Timeline.merge_notes(tl, n2, n3, "merged")
      assert Timeline.merge_notes(tl, n3, n2, "bad") == {:error, {:is_tombstone, c}}
    end
  end

  # ---- adjacent ----

  defp build_timeline_3 do
    {:ok, key} = Zongzi.Score.Key.TwelveET.new(60)

    {:ok, n1} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 0,
        duration_tick: 480,
        key: key,
        lyric: "a"
      })

    {:ok, n2} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 480,
        duration_tick: 480,
        key: key,
        lyric: "b"
      })

    {:ok, n3} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 960,
        duration_tick: 480,
        key: key,
        lyric: "c"
      })

    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    {:ok, tl, [n1, n2, n3]}
  end

  defp build_timeline_4 do
    {:ok, key} = Zongzi.Score.Key.TwelveET.new(60)

    {:ok, n1} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 0,
        duration_tick: 480,
        key: key,
        lyric: "a"
      })

    {:ok, n2} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 480,
        duration_tick: 480,
        key: key,
        lyric: "b"
      })

    {:ok, n3} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 960,
        duration_tick: 480,
        key: key,
        lyric: "c"
      })

    {:ok, n4} =
      Zongzi.Score.Note.new(%{
        id: Zongzi.Util.ID.generate_id("N_"),
        start_tick: 1440,
        duration_tick: 480,
        key: key,
        lyric: "d"
      })

    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    {:ok, tl, n4} = Timeline.insert_note(tl, n4)
    {:ok, tl, [n1, n2, n3, n4]}
  end
end
