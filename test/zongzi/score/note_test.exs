defmodule Zongzi.NoteTest do
  use ExUnit.Case, async: true

  alias Zongzi.Util.ID
  alias Zongzi.Score.{Note, Key}
  doctest Note, import: true

  describe "Note sequence ID test" do
    test "new/1 leaves seq_id nil when not provided" do
      {:ok, key} = Key.TwelveET.new(60)

      {:ok, note} =
        Note.new(
          id: ID.generate_id("Note_"),
          start_tick: 0,
          duration_tick: 480,
          key: key,
          lyric: "あ"
        )

      assert is_nil(note.seq_id)
    end

    test "new/1 respects explicit seq_id" do
      {:ok, key} = Key.TwelveET.new(60)

      {:ok, note} =
        Note.new(
          id: ID.generate_id("Note_"),
          start_tick: 0,
          duration_tick: 480,
          key: key,
          lyric: "い",
          seq_id: 999
        )

      assert note.seq_id == 999
    end

    # 移至 timeline_test.exs——seq_id 现由 Timeline.generate/1 分配
    test "consecutive notes via Timeline get monotonically increasing seq_id" do
      {:ok, key} = Key.TwelveET.new(60)

      {:ok, n1} =
        Note.new(
          id: ID.generate_id("Note_"),
          start_tick: 0,
          duration_tick: 480,
          key: key,
          lyric: "あ"
        )

      {:ok, n2} =
        Note.new(
          id: ID.generate_id("Note_"),
          start_tick: 480,
          duration_tick: 480,
          key: key,
          lyric: "い"
        )

      {:ok, tl} = Zongzi.Timeline.new("t1")
      {:ok, tl, n1} = Zongzi.Timeline.insert_note(tl, n1)
      {:ok, _tl, n2} = Zongzi.Timeline.insert_note(tl, n2)
      assert n1.seq_id < n2.seq_id
    end

    test "existing Note.new calls still work (backward compat)" do
      {:ok, key} = Key.TwelveET.new(60)

      {:ok, note} =
        Note.new(
          id: ID.generate_id("Note_"),
          start_tick: 100,
          duration_tick: 200,
          key: key,
          lyric: "う"
        )

      assert note.start_tick == 100
      assert note.duration_tick == 200
      assert note.lyric == "う"
      assert is_nil(note.seq_id)
    end
  end
end
