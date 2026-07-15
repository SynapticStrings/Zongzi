defmodule Zongzi.EngineContractTest do
  use ExUnit.Case, async: true

  defmodule CheckOnlyEngine do
    @behaviour Zongzi.Engine

    @impl true
    def check(req) do
      segments = Map.fetch!(req, :segments)
      intervs = Map.get(req, :interventions, [])
      params = Map.get(req, :params, %{})

      with :ok <- validate_params(params) do
        {:ok,
         %{
           phase: :check,
           n_segments: length(segments),
           resolved: intervs,
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

  defmodule FullEngine do
    @behaviour Zongzi.Engine

    @impl true
    def check(%{segments: segments}) when is_list(segments) do
      {:ok, %{phase: :check, n_segments: length(segments)}}
    end

    @impl true
    def render(%{segments: segments}) when is_list(segments) do
      {:ok, %{phase: :render, n_segments: length(segments), audio: :stub}}
    end
  end

  alias Zongzi.Windowing.Segment

  test "check-only: render optional" do
    assert function_exported?(CheckOnlyEngine, :check, 1)
    refute function_exported?(CheckOnlyEngine, :render, 1)

    {:ok, seg} = Segment.new(0, 480, [1])

    assert {:ok, %{phase: :check, n_segments: 1, conflicts: []}} =
             CheckOnlyEngine.check(%{segments: [seg], interventions: [], params: %{energy: 0.5}})
  end

  test "invalid params" do
    {:ok, seg} = Segment.new(0, 480, [1])

    assert {:error, {:invalid_param, {:energy, 2}}} =
             CheckOnlyEngine.check(%{segments: [seg], params: %{energy: 2}})
  end

  test "check artifact is not render artifact" do
    {:ok, a} = Segment.new(0, 480, [1])
    {:ok, b} = Segment.new(1000, 2000, [2])

    assert {:ok, %{phase: :check, n_segments: 2}} =
             FullEngine.check(%{segments: [a, b]})

    assert {:ok, %{phase: :render, n_segments: 2, audio: :stub}} =
             FullEngine.render(%{segments: [a, b]})
  end

  test "whole track is just one segment" do
    {:ok, whole} = Segment.new(0, 10_000, [1, 2, 3])
    assert {:ok, %{n_segments: 1}} = FullEngine.check(%{segments: [whole]})
  end
end
