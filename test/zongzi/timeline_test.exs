defmodule Zongzi.TimelineTest do
  use ExUnit.Case

  test "关于刻的声明" do
    # guard macros cannot be called directly in tests; use require + guard context
    require Zongzi.Timeline.Tick
    assert Zongzi.Timeline.Tick.is_numeric_tick(480)
    assert Zongzi.Timeline.Tick.is_dynamic_tick(:dynamic_tick)
  end

  describe "刻与小节的互换" do
    test "单拍子" do
      # 3/4 => 八个八分音符，拍数可以被 3 整除（有 3 * 2 个八分音符）
    end

    # 复拍子

    # 混合拍子
    # e.g. 3/8 + 2/8 + 2/8

    # 散拍子
  end

  describe "刻与秒的互换" do
    # ...
  end

  # 小节与秒经过刻的转换
end
