defmodule Zongzi.Timeline.SeqIDTest do
  use ExUnit.Case, async: true

  alias Zongzi.Timeline.SeqID

  # generate/0 已移除——SeqID 生成权移交 Timeline.generate/1。
  # 对应测试见 timeline_test.exs。

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

  describe "类型规格" do
    test "SeqID 是 pos_integer" do
      assert is_integer(1)
      refute 1 <= 0
    end
  end
end
