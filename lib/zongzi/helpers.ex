defmodule Zongzi.Helpers do
  @moduledoc "Some helpers."

  @doc """
  规整属性，仅保留 `fields` 中声明的键。

  输入合法会返回 `{:ok, normalized_result}` ，输入需要满足：

  - `attrs`: 包括 Map 以及 Keywords
  - `fields`: 列表，元素包括原子以及元组

  否则会返回对应的错误。

  ### 用例

      iex> Zongzi.Helpers.normalize_attrs(
      ...> [name: "初音ミク", platform: {:yamaha, :vocaloid}, extra: "公主殿下赛高！",
      ...> unrealted_context: %{blabla: nil}], [:name, :platform, extra: ""])
      {:ok,
      %{
        extra: "公主殿下赛高！",
        name: "初音ミク",
        platform: {:yamaha, :vocaloid}
      }}

      iex> Zongzi.Helpers.normalize_attrs(%{foo: "a"}, 1)
      {:error, {:invalid_fields, 1}}
  """
  @spec normalize_attrs(any(), any()) :: {:ok, map()} | {:error, term()}
  def normalize_attrs(attrs, fields) do
    with {:ok, allowed_set} <- build_allowed_set(fields),
         {:ok, pairs} <- to_pairs(attrs) do
      result =
        for {k, v} <- pairs,
            normalized_key = normalize_key(k),
            not is_nil(normalized_key),
            normalized_key in allowed_set,
            into: %{},
            do: {normalized_key, v}

      {:ok, result}
    end
  end

  # 检查允许集

  defp build_allowed_set(fields) when is_list(fields) do
    Enum.reduce_while(fields, {:ok, MapSet.new()}, fn
      {k, _default}, {:ok, acc} when is_atom(k) ->
        {:cont, {:ok, MapSet.put(acc, k)}}

      k, {:ok, acc} when is_atom(k) ->
        {:cont, {:ok, MapSet.put(acc, k)}}

      other, _acc ->
        {:halt, {:error, {:invalid_field_spec, other}}}
    end)
  end

  defp build_allowed_set(other), do: {:error, {:invalid_fields, other}}

  # 检查属性

  defp to_pairs(attrs) when is_map(attrs), do: {:ok, attrs}

  defp to_pairs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) or Enum.all?(attrs, &match?({_, _}, &1)) do
      {:ok, attrs}
    else
      {:error, {:invalid_attrs, attrs}}
    end
  end

  defp to_pairs(other), do: {:error, {:invalid_attrs, other}}

  # 标准化

  defp normalize_key(k) when is_atom(k), do: k

  defp normalize_key(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> nil
    end
  end

  defp normalize_key(_), do: nil
end
