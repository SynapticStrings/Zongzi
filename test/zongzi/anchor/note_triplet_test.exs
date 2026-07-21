defmodule Zongzi.Anchor.NoteTripletTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Intervention, Timeline, Util.ID, Anchor.Context}
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Anchor.NoteTriplet

  defp ctx(opts \\ %{}), do: Context.new(opts)

  defp build_timeline_3 do
    {:ok, n1} = build_note(0)
    {:ok, n2} = build_note(480)
    {:ok, n3} = build_note(960)
    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    {:ok, tl, {n1.seq_id, n2.seq_id, n3.seq_id}, {n1, n2, n3}}
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

  describe "3/3 完全匹配" do
    test "无变更时返回 :preserve" do
      {:ok, tl, {a, b, c}, {_n1, _n2, _n3}} = build_timeline_3()
      int = build_intervention({a, b, c})
      assert NoteTriplet.rebase(int, tl, ctx()) == {:ok, :preserve}
    end
  end

  describe "2/3 → rebase" do
    test "split 后旧锚重新捕获三元组" do
      {:ok, tl, {a, b, c}, {_n1, n2, _n3}} = build_timeline_3()
      int = build_intervention({a, b, c})
      {:ok, tl, _before, after_note} = Timeline.split_note(tl, n2, 720, "new_split_id")
      assert {:ok, {:rebase, updated}} = NoteTriplet.rebase(int, tl, ctx())
      assert updated.anchor == {a, n2.seq_id, after_note.seq_id}
    end
  end

  describe "1/3 → conflict" do
    test "drag 后只剩 current 匹配" do
      {:ok, tl, {a, b, c}, {_n1, _n2, _n3}} = build_timeline_3()
      int = build_intervention({a, b, c})
      {:ok, tl} = Timeline.move_note(tl, b, c, :after)
      assert NoteTriplet.rebase(int, tl, ctx()) == {:conflict, :adjacency_lost}
    end
  end

  describe "tombstone → merged_away" do
    test "merge 后目标 seq_id 变成墓碑" do
      {:ok, tl, {_a, b, c}, {_n1, n2, n3}} = build_timeline_3()
      int = build_intervention({b, c, nil})
      {:ok, tl, _merged} = Timeline.merge_notes(tl, n2, n3, "merged_id")
      assert NoteTriplet.rebase(int, tl, ctx()) == {:conflict, :merged_away}
    end
  end

  describe "delete tombstone / missing → relocate" do
    test "delete 后 push 到活跃邻居" do
      {:ok, tl, {a, b, c}, {_n1, _n2, _n3}} = build_timeline_3()
      # 锚在 b 上，删除 b
      int = build_intervention({a, b, c})
      {:ok, tl} = Timeline.delete_note(tl, b)
      assert {:ok, {:relocate, _relocated, meta}} = NoteTriplet.rebase(int, tl, ctx())
      assert meta.from == b
      assert meta.to == c
      assert meta.method == :nearest_active
    end

    test "delete 后 prev 方向 push" do
      {:ok, tl, {a, b, c}, {_n1, _n2, _n3}} = build_timeline_3()
      int = build_intervention({a, b, c})
      {:ok, tl} = Timeline.delete_note(tl, b)

      assert {:ok, {:relocate, _relocated, meta}} =
               NoteTriplet.rebase(int, tl, ctx(orphan_direction: :prev))

      assert meta.to == a
    end

    test "孤儿找不到邻居 → conflict" do
      {:ok, tl, {a, _b, _c}, _notes} = build_timeline_3()
      int = build_intervention({a, 99999, nil})
      assert NoteTriplet.rebase(int, tl, ctx()) == {:conflict, :adjacency_lost}
    end

    test "orphan_direction 为 never 时直接报 conflict" do
      {:ok, tl, {a, b, c}, {_n1, _n2, _n3}} = build_timeline_3()
      int = build_intervention({a, b, c})
      {:ok, tl} = Timeline.delete_note(tl, b)
      assert NoteTriplet.rebase(int, tl, ctx(orphan_direction: :never)) == {:conflict, :relocate_forbidden}
    end
  end
end
