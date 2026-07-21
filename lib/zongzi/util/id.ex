defmodule Zongzi.Util.ID do
  @moduledoc """
  A module that declares the IDs of domain entities.

  Yes, it's simply identity.
  """

  @typedoc "Declare something's ID."
  @type t :: binary()

  @typedoc """
  Identify ID of what.

  Like `t:Enumerable.t/1`, it just for good looking in document.
  """
  @type t(_any_model) :: t()

  @doc """
  Generates the ID of the new object.

  This is a utility function used by the caller (Kernel/adapter layer); Domain's `Model.new/1` does not call it automatically.
  Require the caller to explicitly pass in `:id`.
  """
  @spec generate_id(nil | binary()) :: t()
  def generate_id(id_prefix) do
    (id_prefix || "") <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
