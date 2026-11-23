defmodule CpdDoc.Protocol do
  @moduledoc """
  Validates and converts messages used by the Treedoc Nerves implementation.

  Remote operations use `{:remote, %{op: :ins | :del, from: actor, vc: clock, pos: position}}`.
  """

  @max_position_depth 10_000
  @max_vector_clock_size 10_000
  @max_character_bytes 4_096

  def name, do: Crdt.Replica
#Importante: esta es la manera en la que se envian los elementos
  def encode_operation(
        %{type: :insert, position_id: position_id, character: character},
        actor,
        clock
      ) do
    {:remote,
     %{op: :ins, from: actor, vc: clock, pos: to_wire_position(position_id), ch: character}}
  end

  def encode_operation(%{type: :delete, position_id: position_id}, actor, clock) do
    {:remote, %{op: :del, from: actor, vc: clock, pos: to_wire_position(position_id)}}
  end

  def parse(%{op: :ins, from: actor, vc: clock, pos: position_id, ch: character} = message) do
    if valid_base?(actor, clock, position_id) and valid_character?(character) do
      {:ok, Map.take(message, [:op, :from, :vc, :pos, :ch])}
    else
      :ignore
    end
  end

  def parse(%{op: :del, from: actor, vc: clock, pos: position_id} = message) do
    if valid_base?(actor, clock, position_id) do
      {:ok, Map.take(message, [:op, :from, :vc, :pos])}
    else
      :ignore
    end
  end

  def parse(_message), do: :ignore

  def to_tree_operation(%{op: :ins, pos: position_id, ch: character}) do
    %{type: :insert, position_id: from_wire_position(position_id), character: character}
  end

  def to_tree_operation(%{op: :del, pos: position_id}) do
    %{type: :delete, position_id: from_wire_position(position_id)}
  end

  defp valid_base?(actor, clock, position_id) do
    is_atom(actor) and not is_nil(actor) and valid_clock?(clock) and
      is_integer(Map.get(clock, actor)) and Map.get(clock, actor) >= 1 and
      valid_position?(position_id)
  end

  defp valid_clock?(clock) when is_map(clock) and map_size(clock) <= @max_vector_clock_size do
    Enum.all?(clock, fn {actor, sequence} ->
      is_atom(actor) and not is_nil(actor) and is_integer(sequence) and sequence >= 0
    end)
  end

  defp valid_clock?(_clock), do: false

  defp valid_position?(position_id), do: validate_steps(position_id, 0)
  defp validate_steps([], depth), do: depth > 0

  defp validate_steps([{bit, sequence, actor} | rest], depth)
       when bit in [0, 1] and is_integer(sequence) and sequence >= 1 and is_atom(actor) and
              not is_nil(actor) and depth < @max_position_depth do
    validate_steps(rest, depth + 1)
  end

  defp validate_steps(_steps, _depth), do: false

  defp valid_character?(character) when is_binary(character) do
    byte_size(character) <= @max_character_bytes and String.valid?(character) and
      match?([_], String.graphemes(character))
  end

  defp valid_character?(_character), do: false

  defp to_wire_position(position_id) do
    Enum.map(position_id, fn {bit, {sequence, {actor, _incarnation}}} ->
      {bit, sequence, actor}
    end)
  end

  defp from_wire_position(position_id) do
    Enum.map(position_id, fn {bit, sequence, actor} ->
      {bit, {sequence, {actor, 1}}}
    end)
  end
end
