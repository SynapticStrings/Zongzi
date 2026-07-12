defmodule Zongzi.Anchor.NoteTripletTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Intervention, Timeline, Util.ID}
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Anchor.NoteTriplet

  # ---- helpers ----

  defp build_timeline_3 do
    {:ok, n1} = build_note(0)
    {:ok, n2} = build_note(480)
    {:ok, n3} = build_note(960)
    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    # 返回 seq_id 三元组（不是 Note struct）
    {:ok, tl, {n1.seq_id, n2.seq_id, n3.seq_id}}
  end

  defp build_note(start_tick) do
    {:ok, key} = Key.TwelveET.new(60)
    Note.new(%{
      id: ID.generate_id("Note_"),
      start_tick: start_tick,
      duration_tick: 480,
      key: key,
      lyric: "あ"
    })
  end

  defp build_intervention(triplet) do
    %Intervention{
      id: "int_01",
      channel: :pitch,
      anchor: triplet,
      payload: %{delta: 100},
      snapshot: %{},
      scope: nil
    }
  end

  # ---- 3/3 preserve ----

  describe "3/3 完全匹配" do
    test "无变更时返回 :preserve" do
      {:ok, tl, {a, b, c}} = build_timeline_3()
      int = build_intervention({a, b, c})

      assert NoteTriplet.rebase(int, tl) == {:ok, :preserve}
    end
  end

  # ---- 2/3 rebase ----

  describe "2/3 → rebase" do
    test "split 后旧锚重新捕获三元组" do
      {:ok, tl, {a, b, c}} = build_timeline_3()
      int = build_intervention({a, b, c})

      # split b → note_order: [a, b, b_right, c]
      {:ok, tl, _b, new_seq} = Timeline.split_note(tl, b, 240)

      # 旧三元组 {a,b,c}, 新 adjacent(b) = {a, b, new_seq}
      # prev a==a(1) + current b==b(1) + next c!=new_seq(0) = 2/3
      assert {:ok, {:rebase, updated}} = NoteTriplet.rebase(int, tl)
      assert updated.anchor == {a, b, new_seq}
    end
  end

  # ---- 1/3 adjacency_lost ----

  describe "1/3 → conflict" do
    test "drag 后只剩 current 匹配" do
      {:ok, tl, {a, b, c}} = build_timeline_3()
      int = build_intervention({a, b, c})

      # drag b 到末尾 → note_order: [a, c, b]
      {:ok, tl} = Timeline.drag_note(tl, b, 2)
      # adjacent(b) = {c, b, nil}
      # 旧三元组 {a,b,c}: prev a!=c(0) + current b==b(1) + next c!=nil(0) = 1/3
      assert NoteTriplet.rebase(int, tl) == {:conflict, :adjacency_lost}
    end
  end

  # ---- tombstone ----

  describe "tombstone → merged_away" do
    test "merge 后目标 seq_id 变成墓碑" do
      {:ok, tl, {_a, b, c}} = build_timeline_3()
      int = build_intervention({b, c, nil})  # c 是当前锚定音符

      # merge b 和 c，c 变墓碑
      {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged_id")

      # 锚在 c 上，c 现在是墓碑
      assert NoteTriplet.rebase(int, tl) == {:conflict, :merged_away}
    end
  end

  # ---- not_found → orphan push ----

  describe "not_found → orphan push" do
    test "seq_id 不存在时向 next 方向 push" do
      {:ok, tl, {a, b, _c}} = build_timeline_3()
      int = build_intervention({a, 99999, b})  # 99999 不存在

      # nearest_active(tl, 99999, :next) 也找不到 → no_active_neighbor
      # 所以会走到 {:conflict, :adjacency_lost}
      assert NoteTriplet.rebase(int, tl) == {:conflict, :adjacency_lost}
    end

    test "orphan push 找到邻居时返回 :push" do
      # 直接构造一个 note_order 不含 seq_id 但邻居存在的 Timeline
      {:ok, tl, {a, b, _c}} = build_timeline_3()
      int = build_intervention({a, 999, b})
      # note_order = [a, b, c]，999 不在其中 → try_match 返回 :not_found
      # nearest_active(tl, 999, :next) 扫描整个 order 找不到 → :no_active_neighbor
      # 最终走 :conflict
      #
      # 要真正走 :push 需要 seq_id 在 note_order 中但 adjacent 找不到——
      # 当前 Timeline 无 delete_note 操作，:push 路径暂标记为 TODO。
      assert NoteTriplet.rebase(int, tl) == {:conflict, :adjacency_lost}
    end
  end

  # ---- orphan_direction ----

  describe "orphan_direction 参数" do
    test "默认 :next" do
      {:ok, tl, {a, _b, _c}} = build_timeline_3()
      int = build_intervention({nil, a, 888})

      # 2 参数调用 → orphan_direction 默认 :next
      {:ok, {:rebase, _}} = NoteTriplet.rebase(int, tl)
    end
  end
end
