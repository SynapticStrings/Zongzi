defmodule Zongzi.Timeline.SeqIDTest do
  use ExUnit.Case, async: true

  alias Zongzi.Timeline.SeqID

  describe "compare/2" do
    test "较小 → :lt" do
      assert SeqID.compare(1, 2) == :lt
    end

    test "较大 → :gt" do
      assert SeqID.compare(2, 1) == :gt
    end

    test "相同 → :eq" do
      assert SeqID.compare(42, 42) == :eq
    end
  end
end
