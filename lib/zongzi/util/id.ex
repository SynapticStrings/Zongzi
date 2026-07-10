defmodule Zongzi.Util.ID do
  @typedoc "声明 ID"
  @type t :: binary()
  @typedoc "用于说明是什么对象的 ID"
  @type t(_t) :: binary()

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
