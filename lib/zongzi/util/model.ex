defmodule Zongzi.Util.Model do
  @moduledoc """
  领域模型。

  通过 `use Zongzi.Util.Model, keys: [...], id_prefix: "xxx"` 自动生成：

  - 结构体定义
  - `new/1` — 必须显式提供 `:id`（纯函数，不自动生成）
  - `validate/1`
  - `update/2`

  ## ID 生成

  `new/1` 不再自动生成 ID。调用方使用 `Zongzi.Util.ID.generate_id/1` 生成后传入。
  这保证 Domain 层不依赖随机数。

  ## 业务函数的编写（推荐）

  返回 `{:ok, result}` 或 `{:error, reason}` 。
  """

  @doc "检查领域模型是否合法。"
  @callback validate(model :: struct()) :: {:ok, struct()} | {:error, term()}
  @optional_callbacks [validate: 1]

  defmacro __using__(opts) do
    # 开发错误就直接 raise 吧。
    keys = Keyword.fetch!(opts, :keys)
    id_prefix = Keyword.get(opts, :id_prefix)

    quote do
      import Zongzi.Helpers, only: [normalize_attrs: 2]

      @behaviour Zongzi.Util.Model

      @keys unquote(keys)
      defstruct @keys

      @doc "根据属性创建新的结构体。`:id` 必须显式提供。"
      def new(attrs) do
        with {:ok, normalized} <- normalize_attrs(attrs, @keys) do
          case Map.fetch(normalized, :id) do
            :error ->
              {:error, {:missing_id, unquote(id_prefix)}}

            {:ok, id} ->
              struct(__MODULE__, Map.put(normalized, :id, id))
              |> validate()
          end
        end
      end

      @doc "修改已有结构体的属性（不允许修改 ID）"
      def update(model, attrs) do
        with {:ok, normalized} <- normalize_attrs(attrs, @keys),
             :ok <- if(Map.has_key?(normalized, :id), do: {:error, :id_immutable}, else: :ok),
             new_model = struct(model, normalized) do
          validate(new_model)
        end
      end

      @impl true
      def validate(model), do: {:ok, model}
      defoverridable new: 1, update: 2, validate: 1
    end
  end
end
