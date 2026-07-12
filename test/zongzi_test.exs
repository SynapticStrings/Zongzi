defmodule ZongziTest do
  use ExUnit.Case
  doctest Zongzi
  doctest Zongzi.Helpers

  test "模板" do
    assert 1 + 1 == 2
  end
end
