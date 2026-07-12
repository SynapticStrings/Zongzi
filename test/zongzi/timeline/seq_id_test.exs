defmodule Zongzi.Timeline.SeqIDTest do
  use ExUnit.Case, async: true

  alias Zongzi.Timeline.SeqID

  describe "generate/0" do
    test "生成正整数的 SeqID" do
      id = SeqID.generate()
      assert is_integer(id) and id > 0
    end

    test "连续生成是严格递增的" do
      a = SeqID.generate()
      b = SeqID.generate()
      c = SeqID.generate()

      assert a < b
      assert b < c
    end

    test "批量生成的 ID 互不重复" do
      ids = for _ <- 1..1000, do: SeqID.generate()
      assert length(Enum.uniq(ids)) == 1000
    end
  end

  describe "compare/2" do
    test "较小 → :lt" do
      a = SeqID.generate()
      b = SeqID.generate()
      assert SeqID.compare(a, b) == :lt
    end

    test "较大 → :gt" do
      a = SeqID.generate()
      b = SeqID.generate()
      assert SeqID.compare(b, a) == :gt
    end

    test "相同 → :eq" do
      a = SeqID.generate()
      assert SeqID.compare(a, a) == :eq
    end
  end

  describe "类型规格" do
    test "SeqID 是 pos_integer" do
      id = SeqID.generate()
      assert is_integer(id)
      refute id <= 0
    end
  end
end
