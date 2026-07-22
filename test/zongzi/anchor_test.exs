defmodule Zongzi.AnchorTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Intervention, Timeline, Anchor, Anchor.Context, Util.ID}
  alias Zongzi.Score.{Note, Key}

  defp ctx(opts \\ %{}), do: Context.new(opts)

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

  defp build_timeline_4 do
    {:ok, n1} = build_note(0)
    {:ok, n2} = build_note(480)
    {:ok, n3} = build_note(960)
    {:ok, n4} = build_note(1440)
    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    {:ok, tl, n4} = Timeline.insert_note(tl, n4)
    {:ok, tl, {n1.seq_id, n2.seq_id, n3.seq_id, n4.seq_id}, {n1, n2, n3, n4}}
  end

  defp build_intervention(anchor, id \\ "int_01") do
    %Intervention{
      id: id,
      channel: :pitch,
      anchor: anchor,
      payload: %{delta: 100},
      snapshot: %{}
    }
  end

  describe "empty batch" do
    test "returns empty lists" do
      {:ok, tl, {_a, _b, _c, _d}, _notes} = build_timeline_4()
      result = Anchor.rebase_all([], tl)
      assert result.survived == []
      assert result.conflicts == []
    end
  end

  describe "all preserve" do
    test "3/3 match → all survived unchanged" do
      {:ok, tl, {a, b, c, d}, _notes} = build_timeline_4()
      int1 = build_intervention({a, b, c}, "int1")
      int2 = build_intervention({b, c, d}, "int2")
      result = Anchor.rebase_all([int1, int2], tl)
      assert length(result.survived) == 2
      assert result.conflicts == []
    end
  end

  describe "rebase (2/3)" do
    test "split 后 anchor 自动更新 → survived" do
      {:ok, tl, {a, b, c, _d}, {_n1, n2, _n3, _n4}} = build_timeline_4()
      int = build_intervention({a, b, c})
      # split b → b + new_seq
      {:ok, tl, _before, after_note} = Timeline.split_note(tl, n2, 720, "split_id")
      result = Anchor.rebase_all([int], tl)
      assert length(result.survived) == 1
      assert result.conflicts == []
      [updated] = result.survived
      assert updated.anchor == {a, b, after_note.seq_id}
    end
  end

  describe "relocate (delete tombstone)" do
    test "delete 后 push 到活跃邻居 → survived" do
      {:ok, tl, {a, b, c, _d}, _notes} = build_timeline_4()
      int = build_intervention({a, b, c})
      {:ok, tl} = Timeline.delete_note(tl, b)
      result = Anchor.rebase_all([int], tl)
      assert length(result.survived) == 1
      assert result.conflicts == []
      [relocated] = result.survived
      {_, new_focus, _} = relocated.anchor
      assert new_focus == c
    end
  end

  describe "conflict" do
    test "drag 破坏邻接 → adjacency_lost" do
      {:ok, tl, {a, b, c, d}, _notes} = build_timeline_4()
      int = build_intervention({a, b, c})
      {:ok, tl} = Timeline.move_note(tl, b, d, :after)
      result = Anchor.rebase_all([int], tl)
      assert result.survived == []
      assert [{^int, :adjacency_lost}] = result.conflicts
    end

    test "merge tombstone → merged_away" do
      {:ok, tl, {_a, b, c, d}, {_n1, n2, n3, _n4}} = build_timeline_4()
      # int anchor on c
      int = build_intervention({b, c, d}, "int_c")
      {:ok, tl, _merged} = Timeline.merge_notes(tl, n2, n3, "merged")
      result = Anchor.rebase_all([int], tl)
      assert result.survived == []
      assert [{^int, :merged_away}] = result.conflicts
    end

    test "orphan no neighbor → adjacency_lost" do
      {:ok, tl, {a, _b, _c, _d}, _notes} = build_timeline_4()
      int = build_intervention({a, 99999, nil})
      result = Anchor.rebase_all([int], tl)
      assert result.survived == []
      assert [{^int, :adjacency_lost}] = result.conflicts
    end
  end

  describe "mixed: survive + conflict in one batch" do
    test "split int1 survives, drag int2 conflicts" do
      {:ok, tl, {a, b, c, d}, {_n1, n2, _n3, _n4}} = build_timeline_4()
      int1 = build_intervention({a, b, c}, "int1")
      int2 = build_intervention({b, c, d}, "int2")
      # split keeps int1 alive, drag breaks int2
      {:ok, tl, _before, after_note} = Timeline.split_note(tl, n2, 720, "split_id")
      {:ok, tl} = Timeline.move_note(tl, c, a, :before)
      result = Anchor.rebase_all([int1, int2], tl)
      assert length(result.survived) == 1
      assert length(result.conflicts) == 1
      [survived] = result.survived
      [{conflict_int, reason}] = result.conflicts
      assert survived.anchor == {a, b, after_note.seq_id}
      assert conflict_int.id == "int2"
      assert reason == :adjacency_lost
    end
  end

  describe "custom strategy per intervention" do
    test "intervention with nil strategy uses default NoteTriplet" do
      {:ok, tl, {a, b, c, d}, _notes} = build_timeline_4()
      int1 = build_intervention({a, b, c}, "int1")
      int2 = build_intervention({b, c, d}, "int2")
      # Delete both b and c — both should relocate via NoteTriplet.nearest_active
      {:ok, tl} = Timeline.delete_note(tl, b)
      {:ok, tl} = Timeline.delete_note(tl, c)
      result = Anchor.rebase_all([int1, int2], tl)
      assert length(result.survived) == 2
      assert result.conflicts == []
    end

    test "intervention carries explicit strategy module, it is used" do
      {:ok, tl, {a, b, c, _d}, _notes} = build_timeline_4()
      int = build_intervention({a, b, c})
      int = %{int | strategy: {Zongzi.Anchor.NoteTriplet, %Zongzi.Anchor.NoteTriplet.Options{}}}
      {:ok, tl} = Timeline.delete_note(tl, b)
      result = Anchor.rebase_all([int], tl)
      assert length(result.survived) == 1
      assert result.conflicts == []
    end
  end

  # Module defined here for default_strategy override test
  defmodule AlwaysPreserve do
    @behaviour Zongzi.Anchor.Strategy
    @impl true
    def referenced_seqs(%{anchor: {p, c, n}}), do: Enum.reject([p, c, n], &is_nil/1)
    def referenced_seqs(_), do: []

    @impl true
    def rebase(_int, _tl, _ctx, _opts), do: {:ok, :preserve}

    @impl true
    def choose_host(_f, _tl, _ctx, _opts), do: {:conflict, :no_host}
  end

  describe "default_strategy override" do
    test "opts default_strategy replaces nil strategy" do
      {:ok, tl, {a, b, c, _d}, _notes} = build_timeline_4()
      int = build_intervention({a, b, c})

      result = Anchor.rebase_all([int], tl, ctx(), default_strategy: AlwaysPreserve)
      assert result.survived == [int]
      assert result.conflicts == []
    end
  end
end
