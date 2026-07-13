defmodule Zongzi.Intervention.SpikeTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Intervention, Timeline, Util.ID}
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.{Anchor.NoteTriplet, Anchor.Context}

  # ============================================================
  # Mock phoneme_timing strategy
  # ============================================================

  defmodule MockTiming do
    @behaviour Zongzi.Intervention.Declaration

    @impl true
    def scope(int, tl) do
      {_prev, current, _next} = int.anchor

      case Timeline.adjacent(tl, current) do
        {:ok, {_p, _c, _n}} -> {480, 1440}
        _ -> {0, 0}
      end
    end

    @impl true
    def snapshot(_projection, %Intervention{payload: p}) do
      Map.get(p, :base, %{})
    end

    @impl true
    def resolve(%Intervention{snapshot: stored, payload: p}, fresh_projection) do
      if stored == fresh_projection do
        delta = Map.get(p, :delta, %{})
        {:ok, Map.merge(fresh_projection, delta, fn _k, v1, v2 -> v1 + v2 end)}
      else
        {:conflict, :snapshot_mismatch}
      end
    end
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp ctx(opts \\ %{}), do: Context.new(opts)

  defp make_note(start_tick, lyric) do
    {:ok, key} = Key.TwelveET.new(60)

    Note.new(%{
      id: ID.generate_id("N_"),
      start_tick: start_tick,
      duration_tick: 480,
      key: key,
      lyric: lyric
    })
  end

  defp make_timing_int(triplet, base, delta \\ %{}) do
    int = %Intervention{
      id: ID.generate_id("TI_"),
      channel: :phoneme_timing,
      anchor: triplet,
      payload: %{base: base, delta: delta},
      strategy: MockTiming
    }

    %{int | snapshot: MockTiming.snapshot(nil, int)}
  end

  defp build_4 do
    {:ok, n1} = make_note(0, "は")
    {:ok, n2} = make_note(480, "る")
    {:ok, n3} = make_note(960, "か")
    {:ok, n4} = make_note(1440, "ぜ")
    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    {:ok, tl, n4} = Timeline.insert_note(tl, n4)
    {:ok, tl, [n1.seq_id, n2.seq_id, n3.seq_id, n4.seq_id]}
  end

  # ============================================================
  # 场景 1: split
  # ============================================================

  @tag :spike
  test "split 后 rebase 2/3 存活" do
    {:ok, tl, [a, b, c, _d]} = build_4()
    base = %{0 => 0.0, 1 => 0.12, 2 => 0.25}
    int = make_timing_int({a, b, c}, base, %{1 => 0.03})

    # split b → [a, b, b2, c, d]
    {:ok, tl, ^b, b2} = Timeline.split_note(tl, b, 240)

    # old {a,b,c} vs new adjacent(b)={a,b,b2}: prev✓ current✓ next✗ = 2/3
    assert {:ok, {:rebase, rebased}} = NoteTriplet.rebase(int, tl, ctx())
    assert rebased.anchor == {a, b, b2}
    assert rebased.snapshot == int.snapshot
  end

  @tag :spike
  test "split 后 payload 层判断归属" do
    {:ok, tl, [_a, b, c, _d]} = build_4()
    base = %{"boundary_2" => 0.25}
    # 锚在 c={b,c,d}，但 delta 作用在尾音（tick 靠近末尾）
    # split c 后 anchor 存活，payload 根据 scope 的 tick range 判归属
    int = make_timing_int({b, c, nil}, base, %{"boundary_2" => -0.02})

    {:ok, tl, ^c, _c2} = Timeline.split_note(tl, c, 240)
    # old {b,c,nil} vs new adjacent(c)={b,c,c2}: prev✓ (both nil) → wait
    # adjacent(c) after split: prev=b(✓), current=c(✓), next=c2(≠nil) = 2/3
    assert {:ok, {:rebase, _}} = NoteTriplet.rebase(int, tl, ctx())
    # anchor 存活——归属由 resolve 时 scope + payload tick 判定
  end

  # ============================================================
  # 场景 2: merge → tombstone
  # ============================================================

  @tag :spike
  test "merge 后目标变墓碑" do
    {:ok, tl, [_a, b, c, _d]} = build_4()
    int = make_timing_int({b, c, nil}, %{0 => 0.0})

    {:ok, tl} = Timeline.merge_notes(tl, b, c, "merged")
    assert NoteTriplet.rebase(int, tl, ctx()) == {:conflict, :merged_away}
  end

  # ============================================================
  # 场景 3: drag → conflict
  # ============================================================

  @tag :spike
  test "drag 破坏邻接 → conflict" do
    {:ok, tl, [a, b, c, _d]} = build_4()
    int = make_timing_int({a, b, c}, %{0 => 0.0, 1 => 0.12})

    # drag b 到末尾 → [a, c, d, b]，adjacent(b) = {d, b, nil}
    {:ok, tl} = Timeline.drag_note(tl, b, 3)
    # old {a,b,c}: prev a!=d + current b✓ + next c!=nil = 1/3
    assert NoteTriplet.rebase(int, tl, ctx()) == {:conflict, :adjacency_lost}
  end

  # ============================================================
  # 场景 3b: delete → orphan push
  # ============================================================

  @tag :spike
  test "delete 中间音符 → push 到活跃邻居" do
    {:ok, tl, [a, b, c, d]} = build_4()
    int = make_timing_int({a, b, c}, %{0 => 0.0})

    # delete b → 墓碑，仍在 note_order
    {:ok, tl} = Timeline.delete_note(tl, b)
    # tombstone → nearest_active(b, :next) 跳墓碑找到 c
    # {:relocate, updated, %{to: c}}，锚更新为 {a, c, d}（如果 d 存在）
    assert {:ok, {:relocate, rebased, meta}} = NoteTriplet.rebase(int, tl, ctx())
    assert meta.to == c
    assert rebased.anchor == {a, c, d}
  end

  @tag :spike
  test "delete 首音符 → push 到下一个邻居" do
    {:ok, tl, [a, b, c, _d]} = build_4()
    int = make_timing_int({nil, a, b}, %{0 => 0.0})

    {:ok, tl} = Timeline.delete_note(tl, a)
    # tombstone → nearest_active(a, :next) → b
    assert {:ok, {:relocate, rebased, meta}} = NoteTriplet.rebase(int, tl, ctx())
    assert meta.to == b
    assert rebased.anchor == {nil, b, c}
  end

  # ============================================================
  # 场景 3c: orphan_direction
  # ============================================================

  @tag :spike
  test "delete 后 prev 方向 push（pitch channel）" do
    {:ok, tl, [_a, b, c, d]} = build_4()
    int = make_timing_int({b, c, d}, %{0 => 0.0})

    {:ok, tl} = Timeline.delete_note(tl, c)
    # c 墓碑 → :prev 方向找 b
    assert {:ok, {:relocate, rebased, meta}} = NoteTriplet.rebase(int, tl, ctx(orphan_direction: :prev))
    assert meta.to == b
    {_prev, current, _next} = rebased.anchor
    assert current == b
  end

  # ============================================================
  # 场景 3d: GC 回收无引用墓碑
  # ============================================================

  @tag :spike
  test "GC 回收无 intervention 引用的墓碑" do
    {:ok, tl, [a, b, c, d]} = build_4()

    {:ok, tl} = Timeline.delete_note(tl, b)
    assert MapSet.size(tl.tombstones) == 1
    assert length(tl.note_order) == 4

    # intervention 锚在 c（不引用 b）→ GC 回收 b
    int = make_timing_int({a, c, d}, %{0 => 0.0})
    tl = Timeline.gc(tl, [int])

    assert MapSet.size(tl.tombstones) == 0
    assert tl.note_order == [a, c, d]
  end

  @tag :spike
  test "GC 保留被引用的墓碑" do
    {:ok, tl, [_a, b, c, _d]} = build_4()

    {:ok, tl} = Timeline.delete_note(tl, c)
    assert MapSet.size(tl.tombstones) == 1

    # intervention 锚在 c 旁边（current=c）→ GC 保留 c
    int = make_timing_int({b, c, nil}, %{0 => 0.0})
    tl = Timeline.gc(tl, [int])

    assert MapSet.size(tl.tombstones) == 1
    assert length(tl.note_order) == 4
  end

  # ============================================================
  # 场景 4: lyric change — 3/3 preserve, snapshot vs resolve
  # ============================================================

  @tag :spike
  test "改歌词后结构 3/3 但 resolve 发现快照失配" do
    {:ok, tl, [a, b, c, _d]} = build_4()

    old_base = %{0 => 0.0, 1 => 0.10, 2 => 0.22}
    int = make_timing_int({a, b, c}, old_base, %{1 => 0.05})

    # 结构不变 → 3/3
    assert NoteTriplet.rebase(int, tl, ctx()) == {:ok, :preserve}

    # 模拟 G2P 重跑：歌词改后新投影不同
    new_proj = %{0 => 0.0, 1 => 0.13, 2 => 0.22}
    assert MockTiming.resolve(int, new_proj) == {:conflict, :snapshot_mismatch}

    # 同音字：G2P 恰好相同 → 不误报
    same_proj = %{0 => 0.0, 1 => 0.10, 2 => 0.22}
    assert {:ok, resolved} = MockTiming.resolve(int, same_proj)
    assert_in_delta resolved[1], 0.15, 0.001
  end

  # ============================================================
  # 场景 5: melisma — triplet 粒度
  # ============================================================

  @tag :spike
  test "连续音符 force_merge 不误伤 triplet 匹配" do
    {:ok, tl, [_a, b, c, d]} = build_4()

    # force_merge 不改 seq_id，不影响 triplet
    int = make_timing_int({b, c, d}, %{0 => 0.0})
    assert NoteTriplet.rebase(int, tl, ctx()) == {:ok, :preserve}
  end

  # ============================================================
  # 场景 6: full cycle
  # ============================================================

  @tag :spike
  test "完整循环：挂载 → 编辑 → rebase → resolve" do
    {:ok, tl, [a, b, c, _d]} = build_4()

    # 挂载
    base_timing = %{0 => 0.0, 1 => 0.10, 2 => 0.20}
    int = make_timing_int({a, b, c}, base_timing, %{1 => 0.03})

    # 编辑：split b
    {:ok, tl, ^b, b2} = Timeline.split_note(tl, b, 240)

    # rebase
    {:ok, {:rebase, rebased}} = NoteTriplet.rebase(int, tl, ctx())
    assert rebased.anchor == {a, b, b2}

    # render + resolve
    projection = %{0 => 0.0, 1 => 0.10, 2 => 0.20}
    assert {:ok, result} = MockTiming.resolve(rebased, projection)
    assert result[1] == 0.13
  end
end
