defmodule Zongzi.Score.Tick do
  @moduledoc "Tick is time unit for SVS editor side."

  @type numeric_tick :: non_neg_integer()
  @type dynamic_tick :: :dynamic_tick

  @typedoc "incluade specific positive integer tick and variable `:dynamic_tick`."
  @type t :: numeric_tick() | dynamic_tick()

  @spec get_dynamic_tick() :: dynamic_tick()
  def get_dynamic_tick, do: :dynamic_tick

  # ---- Guards ----

  defguard is_dynamic_tick(maybe_tick) when maybe_tick == :dynamic_tick
  defguard is_numeric_tick(maybe_tick) when is_integer(maybe_tick) and maybe_tick >= 0
  defguard is_tick(maybe_tick) when is_dynamic_tick(maybe_tick) or is_numeric_tick(maybe_tick)
end
