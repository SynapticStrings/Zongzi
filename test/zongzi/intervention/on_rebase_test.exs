defmodule Zongzi.Intervention.OnRebaseTest do
  use ExUnit.Case, async: true

  alias Zongzi.{Intervention, Timeline, Anchor, Util.ID}
  alias Zongzi.Score.{Note, Key}

  defmodule MockPitchDeclaration do
    @behaviour Zongzi.Intervention.Declaration

    @impl true
    def scope(_int, _tl), do: {0, 1000}

    @impl true
    def snapshot(_proj, _int), do: %{}

    @impl true
    def resolve(_int, _proj), do: {:ok, :stub}

    # @impl true
    def on_rebase(%{anchor: {_prev, _cur, _next}} = int, %{decision: :rebase}, _tl) do
      child_a = %{int | id: int.id <> "_a", payload: %{segment: :before}}
      child_b = %{int | id: int.id <> "_b", payload: %{segment: :after}}
      {:split, [child_a, child_b]}
    end

    def on_rebase(int, _meta, _tl), do: {:ok, int}
  end

  defp note(start_tick) do
    {:ok, key} = Key.TwelveET.new(60)
    id = ID.generate_id("Note_")
    Note.new(%{id: id, start_tick: start_tick, duration_tick: 480, key: key})
  end

  defp build_3 do
    {:ok, n1} = note(0)
    {:ok, n2} = note(480)
    {:ok, n3} = note(960)
    {:ok, tl} = Timeline.new("t1")
    {:ok, tl, n1} = Timeline.insert_note(tl, n1)
    {:ok, tl, n2} = Timeline.insert_note(tl, n2)
    {:ok, tl, n3} = Timeline.insert_note(tl, n3)
    {tl, n1, n2, n3}
  end

  test "split after rebase: on_rebase splits into children" do
    {tl, n1, n2, n3} = build_3()
    int = %Intervention{
      id: "iv1",
      channel: :pitch,
      anchor: {n1.seq_id, n2.seq_id, n3.seq_id},
      payload: %{curve: :full},
      snapshot: %{},
      scope: nil,
      strategy: nil,
      declaration: MockPitchDeclaration
    }

    {:ok, tl, _before, _after} = Timeline.split_note(tl, n2, 720, "split_id")

    result = Anchor.rebase_all([int], tl)
    assert result.conflicts == []
    assert length(result.survived) == 2
    assert Enum.find(result.survived, &(&1.id == "iv1_a"))
    assert Enum.find(result.survived, &(&1.id == "iv1_b"))
  end

  test "preserve: on_rebase returns ok unchanged" do
    {tl, n1, n2, n3} = build_3()
    int = %Intervention{
      id: "iv1",
      channel: :pitch,
      anchor: {n1.seq_id, n2.seq_id, n3.seq_id},
      payload: %{},
      snapshot: %{},
      scope: nil,
      strategy: nil,
      declaration: MockPitchDeclaration
    }

    result = Anchor.rebase_all([int], tl)
    assert result.conflicts == []
    assert [single] = result.survived
    assert single.id == "iv1"
  end

  test "no declaration field -> fall through, no crash" do
    {tl, n1, n2, n3} = build_3()
    int = %Intervention{
      id: "iv1",
      channel: :pitch,
      anchor: {n1.seq_id, n2.seq_id, n3.seq_id},
      payload: %{},
      snapshot: %{},
      scope: nil,
      strategy: nil,
      declaration: nil
    }

    {:ok, tl, _before, _after} = Timeline.split_note(tl, n2, 720, "split_id")
    result = Anchor.rebase_all([int], tl)
    assert result.conflicts == []
    assert length(result.survived) == 1
  end
end
