defmodule Zongzi.Anchor.ScoredHostTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Intervention, Timeline, Anchor.Context}
  alias Zongzi.Score.{Note, Key}
  alias Zongzi.Anchor.ScoredHost

  defp ctx(opts \\ %{}), do: Context.new(opts)

  defp build_tl(notes) do
    {:ok, tl} = Timeline.new("t1")
    {tl, acc} =
      Enum.reduce(notes, {tl, []}, fn note, {tl, acc} ->
        {:ok, tl, note} = Timeline.insert_note(tl, note)
        {tl, acc ++ [note]}
      end)
    {tl, acc}
  end

  defp note(midi, overrides \\ %{}) do
    id = "N_#{midi}_#{System.unique_integer([:positive])}"
    {:ok, key} = Key.TwelveET.new(midi)
    {:ok, n} =
      Note.new(
        Map.merge(%{id: id, start_tick: 0, duration_tick: 480, key: key}, overrides)
      )
    n
  end

  defp int_at(seq_id, prev, next_) do
    %Intervention{id: "int_1", channel: :pitch, anchor: {prev, seq_id, next_},
                  payload: %{}, snapshot: %{}, scope: nil, strategy: nil}
  end

  describe "preserve" do
    test "3/3 match" do
      {tl, [a, b, c]} = build_tl([note(60), note(62), note(64)])
      int = int_at(b.seq_id, a.seq_id, c.seq_id)
      assert ScoredHost.rebase(int, tl, ctx()) == {:ok, :preserve}
    end
  end

  describe "rebase" do
    test "2/3 after split" do
      {tl, [a, b, c]} = build_tl([note(60), note(62), note(64)])
      int = int_at(b.seq_id, a.seq_id, c.seq_id)
      {:ok, tl, _b, new_seq} = Timeline.split_note(tl, b.seq_id, 240)
      assert {:ok, {:rebase, updated}} = ScoredHost.rebase(int, tl, ctx())
      assert updated.anchor == {a.seq_id, b.seq_id, new_seq}
    end
  end

  describe "merged_away" do
    test "merge tombstone" do
      {tl, [a, b]} = build_tl([note(60), note(62)])
      int = int_at(b.seq_id, nil, nil)
      {:ok, tl} = Timeline.merge_notes(tl, a.seq_id, b.seq_id, "merged")
      assert ScoredHost.rebase(int, tl, ctx()) == {:conflict, :merged_away}
    end
  end

  describe "relocate: same key wins" do
    test "prefers candidate with same MIDI" do
      {tl, [c, d, d2, e]} = build_tl([note(60), note(62), note(62), note(64)])
      int = int_at(d.seq_id, c.seq_id, d2.seq_id)
      {:ok, tl} = Timeline.delete_note(tl, d.seq_id)

      notes_map = %{c.seq_id => c, d2.seq_id => d2, e.seq_id => e}
      focus = d

      assert {:ok, {:relocate, _relocated, meta}} =
               ScoredHost.rebase(int, tl, ctx(notes_by_seq: notes_map, focus_note: focus))
      assert meta.to == d2.seq_id
      assert meta.method == :scored
      assert meta.from == d.seq_id
    end
  end

  describe "relocate: tie" do
    test "all same-window, no key match" do
      {tl, [c, d, f, g]} = build_tl([note(60), note(62), note(65), note(67)])
      int = int_at(d.seq_id, c.seq_id, f.seq_id)
      {:ok, tl} = Timeline.delete_note(tl, d.seq_id)

      notes_map = %{c.seq_id => c, f.seq_id => f, g.seq_id => g}
      focus = d

      assert {:conflict, :ambiguous_host} =
               ScoredHost.rebase(int, tl, ctx(notes_by_seq: notes_map, focus_note: focus))
    end
  end

  describe "relocate: cross-window forbid" do
    test "candidate in different window excluded" do
      {tl, [c, d, e, g]} = build_tl([note(60), note(62), note(64), note(67)])
      int = int_at(d.seq_id, c.seq_id, e.seq_id)
      {:ok, tl} = Timeline.delete_note(tl, d.seq_id)

      notes_map = %{c.seq_id => c, e.seq_id => e, g.seq_id => g}
      seq_to_window = %{c.seq_id => "w1", d.seq_id => "w1", e.seq_id => "w2", g.seq_id => "w2"}
      focus = d

      assert {:ok, {:relocate, _relocated, meta}} =
               ScoredHost.rebase(int, tl,
                 ctx(notes_by_seq: notes_map, seq_to_window: seq_to_window, focus_note: focus))
      assert meta.to == c.seq_id
    end
  end

  describe "relocate: no candidates" do
    test "sole note deleted" do
      {tl, [c]} = build_tl([note(60)])
      int = int_at(c.seq_id, nil, nil)
      {:ok, tl} = Timeline.delete_note(tl, c.seq_id)
      assert ScoredHost.rebase(int, tl, ctx()) == {:conflict, :no_host}
    end
  end

  describe "choose_host/4 callback" do
    test "returns best with scores" do
      {tl, [c, d, d2, e]} = build_tl([note(60), note(62), note(62), note(64)])
      {:ok, tl} = Timeline.delete_note(tl, d.seq_id)

      notes_map = %{c.seq_id => c, d2.seq_id => d2, e.seq_id => e}
      focus = d

      assert {:ok, best, %{scores: scores}} =
               ScoredHost.choose_host(d.seq_id, tl,
                 ctx(notes_by_seq: notes_map, focus_note: focus), [])
      assert best == d2.seq_id
      score_vals = Enum.map(scores, &elem(&1, 1))
      assert score_vals == Enum.sort(score_vals, :desc)
    end

    test "tie → ambiguous_host" do
      {tl, [c, d, f, g]} = build_tl([note(60), note(62), note(65), note(67)])
      {:ok, tl} = Timeline.delete_note(tl, d.seq_id)

      notes_map = %{c.seq_id => c, f.seq_id => f, g.seq_id => g}
      focus = d

      assert {:conflict, :ambiguous_host} =
               ScoredHost.choose_host(d.seq_id, tl,
                 ctx(notes_by_seq: notes_map, focus_note: focus), [])
    end
  end
end
