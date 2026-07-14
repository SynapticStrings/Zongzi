defmodule Zongzi.EngineContractTest do
  use ExUnit.Case, async: true

  defmodule CheckOnlyEngine do
    @behaviour Zongzi.Engine

    @impl true
    def check_whole(req) do
      ivs = Map.get(req, :interventions, [])
      params = Map.get(req, :params, %{})

      with :ok <- validate_params(params) do
        {:ok,
         %{
           phase: :check,
           resolved: ivs,
           conflicts: [],
           params: params
         }}
      end
    end

    defp validate_params(params) when is_map(params) do
      case Map.get(params, :energy) do
        nil -> :ok
        e when is_number(e) and e >= 0 and e <= 1 -> :ok
        bad -> {:error, {:invalid_param, {:energy, bad}}}
      end
    end
  end

  defmodule FullPhraseEngine do
    @behaviour Zongzi.Engine

    @impl true
    def check_whole(req), do: {:ok, %{phase: :check, coverage: :whole, req_keys: Map.keys(req)}}

    @impl true
    def check_partial(%{slices: slices} = req) when is_list(slices) do
      {:ok,
       %{phase: :check, coverage: :partial, n_slices: length(slices), req_keys: Map.keys(req)}}
    end

    @impl true
    def render_whole(_req), do: {:ok, %{phase: :render, coverage: :whole, audio: :stub}}

    @impl true
    def render_partial(%{slices: slices}) when is_list(slices) do
      {:ok, %{phase: :render, coverage: :partial, n_slices: length(slices), audio: :stub}}
    end
  end

  alias Zongzi.Windowing.Slice

  test "check-only engine: optional callbacks not required" do
    assert function_exported?(CheckOnlyEngine, :check_whole, 1)
    refute function_exported?(CheckOnlyEngine, :render_whole, 1)
    refute function_exported?(CheckOnlyEngine, :check_partial, 1)

    assert {:ok, %{phase: :check, conflicts: []}} =
             CheckOnlyEngine.check_whole(%{interventions: [], params: %{energy: 0.5}})
  end

  test "check-only engine: invalid non-intervention param" do
    assert {:error, {:invalid_param, {:energy, 2}}} =
             CheckOnlyEngine.check_whole(%{params: %{energy: 2}})
  end

  test "full engine: check artifact is not render artifact" do
    {:ok, slice} = Slice.new(0, 480, [1])

    assert {:ok, %{phase: :check, coverage: :partial, n_slices: 1}} =
             FullPhraseEngine.check_partial(%{slices: [slice]})

    assert {:ok, %{phase: :render, coverage: :partial, audio: :stub}} =
             FullPhraseEngine.render_partial(%{slices: [slice]})
  end

  test "full engine: whole path" do
    assert {:ok, %{phase: :check, coverage: :whole}} = FullPhraseEngine.check_whole(%{})
    assert {:ok, %{phase: :render, audio: :stub}} = FullPhraseEngine.render_whole(%{})
  end
end
