defmodule Zongzi.Util.ID do
  @moduledoc """
  声明领域实体的 ID 的模块。

  对，单纯就是 ID 罢了。
  """

  @typedoc "声明 ID"
  @type t :: binary()

  @typedoc """
  用于说明是什么对象的 ID。

  底层没什么，单纯问了文档好看罢了，就像 `t:Enumerable.t/1` 一样。
  """
  @type t(_t) :: t()

  @doc """
  生成新对象的 ID。

  这是调用方（Kernel/适配器层）使用的工具函数，Domain 的 `Model.new/1` 不会自动调用它。
  纯函数内核要求调用方显式传入 `:id`。
  """
  @spec generate_id(nil | binary()) :: t()
  def generate_id(id_prefix) do
    (id_prefix || "") <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
