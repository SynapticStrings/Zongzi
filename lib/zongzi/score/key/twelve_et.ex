defmodule Zongzi.Score.Key.TwelveET do
  @moduledoc """
  Implement 12ET.

  Internally stored as MIDI numbers (integers).
  """

  use Zongzi.Score.Key

  defstruct [:midi]

  # ---- Key behaviour ----

  @impl true
  def new(midi) when is_number(midi), do: {:ok, %__MODULE__{midi: midi}}

  @impl true
  def from_midi(midi, _ctx), do: new(midi)

  # ---- implement Inner protocal ----

  defimpl Inner, for: __MODULE__ do
    def to_midi(%{midi: midi}), do: midi * 1.0

    def to_frequency(%{midi: midi}, reference), do: reference * :math.pow(2, (midi - 69) / 12)

    def to_score(_key, _type, _ctx), do: {:error, :not_implemented}
  end
end
