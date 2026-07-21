defmodule Zongzi.Util.Object do
  @moduledoc """
  Value Object generator.

  write `use Zongzi.Util.Object, keys: [...]`, and generate:

  - struct defination
  - `new/1`
  - `validate/1`
  - `update/2`
  """

  @callback validate(new_object :: struct()) :: {:ok, struct()} | {:error, term()}
  @optional_callbacks [validate: 1]

  defmacro __using__(opts) do
    # Similar to Domain, this usually indicates a problem with the code, also raise error.
    keys = Keyword.fetch!(opts, :keys)

    quote do
      import Zongzi.Helpers, only: [normalize_attrs: 2]

      @keys unquote(keys)
      defstruct @keys

      @behaviour Zongzi.Util.Object

      @doc "Create a new VO based on the properties."
      def new(attrs) do
        with {:ok, normalized} <- normalize_attrs(attrs, @keys),
             obj = struct(__MODULE__, normalized),
             {:ok, obj} <- validate(obj) do
          {:ok, obj}
        end
      end

      @doc "Modify the property of an existing VO."
      def update(obj, attrs) do
        with {:ok, normalized} <- normalize_attrs(attrs, @keys),
             new_obj = struct(obj, normalized),
             {:ok, new_obj} <- validate(new_obj) do
          {:ok, new_obj}
        end
      end

      @impl true
      def validate(obj), do: {:ok, obj}
      defoverridable validate: 1
    end
  end
end
