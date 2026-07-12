defmodule Zongzi.TimelineTest do
  use ExUnit.Case, async: true

  alias Zongzi.Util.ID
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Timeline

  # ---- helpers ----

  defp build_note(attrs) do
    {:ok, key} = Key.TwelveET.new(60)
    defaults = [id: ID.generate_id("Note_"), start_tick: 0, duration_tick: 480, key: key, lyric: "あ"]
    Note.new(Keyword.merge(defaults, attrs) |> Enum.into(%{}))
  end

  # ---- new ----

  describe "new/1" do
    test "创建空 Timeline" do
      track_id = "track_01"
      {:ok, tl} = Timeline.new(track_id)
      assert tl.track_id == track_id
      assert tl.note_order == []
      assert tl.seq_map == %{}
      assert tl.tombstones == MapSet.new()
    end
  end

  # ---- generate ----

  describe "generate/1" do
    test "生成递增的 SeqID" do
      {:ok, tl} = Timeline.new("t1")
      {id1, tl} = Timeline.generate(tl)
      {id2, _tl} = Timeline.generate(tl)

      assert id1 > 0
      assert id2 == id1 + 1
    end

    test "从指定 next_seq 起算（反序列化场景）" do
      {:ok, tl} = Timeline.new("t1", next_seq: 100)
      {id, _tl} = Timeline.generate(tl)
      assert id == 100
    end
  end

  # ---- insert_note ----

  describe "insert_note/2" do
    test "插入音符到空 Timeline" do
      {:ok, note} = build_note([])
      {:ok, tl} = Timeline.new("track_01")

      {:ok, tl, note} = Timeline.insert_note(tl, note)
      assert tl.note_order == [note.seq_id]
      assert tl.seq_map[note.seq_id] == note.id
    end

    test "连续插入保持顺序" do
      {:ok, n1} = build_note(start_tick: 0)
      {:ok, n2} = build_note(start_tick: 480)
      {:ok, n3} = build_note(start_tick: 960)
      {:ok, tl} = Timeline.new("t1")

      {:ok, tl, n1} = Timeline.insert_note(tl, n1)
      {:ok, tl, n2} = Timeline.insert_note(tl, n2)
      {:ok, tl, n3} = Timeline.insert_note(tl, n3)

      assert tl.note_order == [n1.seq_id, n2.seq_id, n3.seq_id]
    end

    test "已有 seq_id 的不重新生成" do
      {:ok, note} = build_note(seq_id: 42)
      {:ok, tl} = Timeline.new("t1")

      {:ok, _tl, note} = Timeline.insert_note(tl, note)
      assert note.seq_id == 42
    end
  end

  # ---- insert_note_at ----

  describe "insert_note_at/3" do
    test "中间插入" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order
      {:ok, note} = build_note(start_tick: 480)

      {:ok, tl, note} = Timeline.insert_note_at(tl, note, 1)
      assert tl.note_order == [a, note.seq_id, b, c]
    end

    test "插入到开头" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order
      {:ok, note} = build_note(start_tick: 0)

      {:ok, tl, note} = Timeline.insert_note_at(tl, note, 0)
      assert tl.note_order == [note.seq_id, a, b, c]
    end

    test "超出范围插入末尾" do
      {:ok, tl} = build_timeline_3()
      {:ok, note} = build_note(start_tick: 1440)

      {:ok, tl, note} = Timeline.insert_note_at(tl, note, 999)
      assert List.last(tl.note_order) == note.seq_id
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

      {:ok, tl, orig_seq, new_seq} = Timeline.split_note(tl, n2.seq_id, 240)
      assert tl.note_order == [n1.seq_id, orig_seq, new_seq, n3.seq_id]
      assert orig_seq == n2.seq_id
      assert new_seq != orig_seq
    end

    test "不存在的 seq_id 报错" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.split_note(tl, 99999, 100) == {:error, {:not_found, 99999}}
    end
  end

  # ---- drag_note ----

  describe "drag_note/3" do
    test "拖拽到末尾" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      {:ok, tl} = Timeline.drag_note(tl, b, 2)
      assert tl.note_order == [a, c, b]
    end

    test "拖拽到开头" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      {:ok, tl} = Timeline.drag_note(tl, c, 0)
      assert tl.note_order == [c, a, b]
    end

    test "拖拽墓碑拒绝" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged_note")

      assert Timeline.drag_note(tl, c, 0) == {:error, {:is_tombstone, c}}
    end

    test "seq_id 不存在报错" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.drag_note(tl, 99999, 0) == {:error, {:not_found, 99999}}
    end
  end

  # ---- merge_notes ----

  describe "merge_notes/4" do
    test "合并两个相邻音符：前保留后墓碑" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged_bc")

      assert tl.seq_map[b] == "merged_bc"
      assert MapSet.member?(tl.tombstones, c)
      assert tl.note_order == [a, b, c]
    end

    test "合并已墓碑拒绝" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")
      assert Timeline.merge_notes(tl, c, b, "bad") == {:error, {:is_tombstone, c}}
    end
  end

  # ---- adjacent ----

  describe "adjacent/2" do
    test "中间元素返回 prev/current/next" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      assert Timeline.adjacent(tl, b) == {:ok, {a, b, c}}
    end

    test "首个元素的 prev 为 nil" do
      {:ok, tl} = build_timeline_3()
      [a | _] = tl.note_order

      assert {:ok, {nil, ^a, _}} = Timeline.adjacent(tl, a)
    end

    test "末尾元素的 next 为 nil" do
      {:ok, tl} = build_timeline_3()
      order = tl.note_order
      last = List.last(order)

      assert {:ok, {_, ^last, nil}} = Timeline.adjacent(tl, last)
    end

    test "墓碑返回 :tombstone" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")

      assert Timeline.adjacent(tl, c) == {:tombstone, c}
    end

    test "不存在返回 :not_found" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.adjacent(tl, 99999) == {:error, :not_found}
    end
  end

  # ---- try_match ----

  describe "try_match/2" do
    test "3/3 完全匹配" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 3}
    end

    test "拖拽中间元素破坏 2/3，只剩 current 匹配" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order

      # 拖 b 到最后: [a, c, b] -> adjacent(b) = {c, b, nil}
      # prev: a!=c, next: c!=nil -> 1/3
      {:ok, tl} = Timeline.drag_note(tl, b, 2)
      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 1}
    end

    test "拖拽后 2/3 匹配（prev+current 存活）" do
      # 4 音符: [a, b, c, d]，锚在 {a, b, c}
      # 拖 c 到开头 -> [c, a, b, d] -> adjacent(b) = {a, b, d}
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

      # 锚在 {a, b, c}
      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 3}

      # 拖 c 到开头
      {:ok, tl} = Timeline.drag_note(tl, c, 0)
      assert tl.note_order == [c, a, b, d]
      assert Timeline.try_match(tl, {a, b, c}) == {:ok, 2}
    end

    test "current 是墓碑 -> :tombstone" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")

      assert Timeline.try_match(tl, {b, c, nil}) == {:tombstone, c}
    end

    test "current 不在 Timeline -> :not_found" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.try_match(tl, {nil, 99999, nil}) == {:error, :not_found}
    end

    test "nil==nil 边界算匹配（首音符 prev=nil）" do
      {:ok, tl} = build_timeline_3()
      [a, _b, c] = tl.note_order

      # 首音符三元组 {nil, a, b}
      # 拖拽后变 {nil, a, c} → prev: nil==nil(1) + current: a==a(1) + next: b!=c(0) = 2/3
      assert Timeline.try_match(tl, {nil, a, c}) == {:ok, 2}
    end

    test "nil==nil 边界算匹配（尾音符 next=nil）" do
      {:ok, tl} = build_timeline_3()
      [a, _b, c] = tl.note_order

      # 尾音符三元组 {b, c, nil}
      # 拖拽后变 {a, c, nil} → prev: b!=a(0) + current: c==c(1) + next: nil==nil(1) = 2/3
      assert Timeline.try_match(tl, {a, c, nil}) == {:ok, 2}
    end
  end

  # ---- nearest_active ----

  describe "nearest_active/3" do
    test "向前扫描找到活跃邻居" do
      {:ok, tl} = build_timeline_3()
      [a, b, _c] = tl.note_order
      # b 向前找 → a
      assert Timeline.nearest_active(tl, b, :prev) == {:ok, a}
    end

    test "向后扫描找到活跃邻居" do
      {:ok, tl} = build_timeline_3()
      [_a, b, c] = tl.note_order
      # b 向后找 → c
      assert Timeline.nearest_active(tl, b, :next) == {:ok, c}
    end

    test "跳过墓碑" do
      {:ok, tl} = build_timeline_3()
      [a, b, c] = tl.note_order
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")
      # c 是墓碑，a 向后找，跳过 c 到 b
      # note_order 仍为 [a, b, c]，c 在墓碑中
      assert Timeline.nearest_active(tl, a, :next) == {:ok, b}
    end

    test "没有活跃邻居" do
      {:ok, tl} = build_timeline_3()
      [a | _rest] = tl.note_order
      # 首音符向前找 → 无
      assert Timeline.nearest_active(tl, a, :prev) == {:error, :no_active_neighbor}
    end

    test "不存在的 seq_id" do
      {:ok, tl} = Timeline.new("t1")
      assert Timeline.nearest_active(tl, 99999, :prev) == {:error, :no_active_neighbor}
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
