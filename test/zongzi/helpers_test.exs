defmodule Zongzi.HelpersTest do
  use ExUnit.Case
  import Zongzi.Helpers
  doctest Zongzi.Helpers

  describe "normalize_attrs/2" do
    test "输入数据与键值声明正好匹配" do
      # ...
    end

    test "键值声明不含的输入数据会被滤掉" do
      # ...
    end

    test "输入数据不存在的键值声明也会被滤掉" do
      # ...
    end

    test "输入数据仅允许 Map 与 Keywords 存在" do
      assert normalize_attrs([foo: 1, bar: 2], [:foo]) == {:ok, %{foo: 1}}

      assert normalize_attrs([1, 2], [:foo]) == {:error, {:invalid_attrs, [1, 2]}}

      assert normalize_attrs([{:foo, 1, 2}, bar: nil], [:foo]) == {:error, {:invalid_attrs, [{:foo, 1, 2}, bar: nil]}}
    end

    test "键值声明仅允许元素是原子或元组的列表存在" do
      assert normalize_attrs([foo: 1, bar: 2], nil) == {:error, {:invalid_fields, nil}}

      assert normalize_attrs([foo: 1, bar: 2], [:foo, "nil"]) == {:error, {:invalid_field_spec, "nil"}}
    end
  end
end
