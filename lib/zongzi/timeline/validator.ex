defmodule Zongzi.Timeline.Validator do
  @moduledoc false

  alias Zongzi.Timeline

  # Validate items
  #
  # - `head` / `tail` exists and same with nodes
  # - 双向链表指针对称
  # - `seq_map` has same status with `tombstones`
  # - `next_seq` 大于所有已分配 seq_id
  @spec validate(Timeline.t()) :: :ok | {:error, term()}
  def validate(%Timeline{} = timeline) do
    with :ok <- validate_head_tail(timeline),
         :ok <- validate_node_consistency(timeline),
         :ok <- validate_seq_map_tombstones(timeline),
         :ok <- validate_next_seq(timeline) do
      :ok
    end
  end

  # ---- Private ----

  defp validate_head_tail(%Timeline{head: nil, tail: nil, nodes: nodes}) do
    if nodes == %{}, do: :ok, else: {:error, {:head_tail_nil_with_nodes, nodes}}
  end

  defp validate_head_tail(%Timeline{head: nil, tail: tail}) do
    {:error, {:head_tail_mismatch, nil, tail}}
  end

  defp validate_head_tail(%Timeline{head: head, tail: nil}) do
    {:error, {:head_tail_mismatch, head, nil}}
  end

  defp validate_head_tail(%Timeline{head: head, tail: tail, nodes: nodes}) do
    cond do
      not Map.has_key?(nodes, head) ->
        {:error, {:head_not_in_nodes, head}}

      not Map.has_key?(nodes, tail) ->
        {:error, {:tail_not_in_nodes, tail}}

      true ->
        {head_prev, _} = Map.fetch!(nodes, head)
        {_, tail_next} = Map.fetch!(nodes, tail)

        if head_prev == nil and tail_next == nil do
          :ok
        else
          {:error, {:head_tail_pointers_invalid, head, tail, head_prev, tail_next}}
        end
    end
  end

  defp validate_node_consistency(%Timeline{nodes: nodes}) do
    Enum.reduce_while(nodes, :ok, fn {seq_id, {prev, next}}, _acc ->
      with :ok <- validate_prev_link(nodes, seq_id, prev),
           :ok <- validate_next_link(nodes, seq_id, next) do
        {:cont, :ok}
      else
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_prev_link(_nodes, _seq_id, nil), do: :ok

  defp validate_prev_link(nodes, seq_id, prev) do
    case Map.fetch(nodes, prev) do
      {:ok, {_, ^seq_id}} -> :ok
      _ -> {:error, {:prev_link_broken, prev, seq_id}}
    end
  end

  defp validate_next_link(_nodes, _seq_id, nil), do: :ok

  defp validate_next_link(nodes, seq_id, next) do
    case Map.fetch(nodes, next) do
      {:ok, {^seq_id, _}} -> :ok
      _ -> {:error, {:next_link_broken, seq_id, next}}
    end
  end

  defp validate_seq_map_tombstones(%Timeline{
         nodes: nodes,
         seq_map: seq_map,
         tombstones: tombstones
       }) do
    with :ok <- validate_nodes_status(nodes, seq_map, tombstones),
         :ok <- validate_seq_map_refs(seq_map, nodes) do
      :ok
    end
  end

  defp validate_nodes_status(nodes, seq_map, tombstones) do
    Enum.reduce_while(nodes, :ok, fn {seq_id, _}, _acc ->
      in_tombstones = MapSet.member?(tombstones, seq_id)
      in_seq_map = Map.has_key?(seq_map, seq_id)

      cond do
        in_tombstones -> {:cont, :ok}
        in_seq_map -> {:cont, :ok}
        true -> {:halt, {:error, {:missing_node, seq_id}}}
      end
    end)
  end

  defp validate_seq_map_refs(seq_map, nodes) do
    Enum.reduce_while(seq_map, :ok, fn {seq_id, _note_id}, _acc ->
      if Map.has_key?(nodes, seq_id) do
        {:cont, :ok}
      else
        {:halt, {:error, {:seq_map_refs_missing_node, seq_id}}}
      end
    end)
  end

  defp validate_next_seq(%Timeline{next_seq: next_seq, nodes: nodes}) do
    if next_seq < 1 do
      {:error, {:invalid_next_seq, next_seq}}
    else
      max_seq = if nodes == %{}, do: 0, else: nodes |> Map.keys() |> Enum.max()

      if next_seq > max_seq,
        do: :ok,
        else: {:error, {:next_seq_not_greater_than_max, next_seq, max_seq}}
    end
  end
end
