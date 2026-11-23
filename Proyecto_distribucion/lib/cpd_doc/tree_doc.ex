defmodule CpdDoc.TreeDoc do
  @moduledoc """
  Arbol Treedoc para editar texto entre varias replicas.

  Cada caracter tiene una posicion fija. Al borrar dejamos una marca, asi una
  operacion vieja no vuelve a mostrarlo. Cada cambio local devuelve lo que hay
  que compartir con las otras replicas.
  """

  @max_character_bytes 4_096

  # Arranca el documento vacio, sin caracteres ni marcas de borrado.
  def empty do
    %{characters_by_position: %{}, tombstones: MapSet.new()}
  end

  def new do
    Map.merge(empty(), %{local_counter: 0, last_local_position: nil})
  end

  # Compara dos posiciones con el recorrido que define Treedoc.
  # Todas las replicas usan esta regla para mostrar el texto igual.
  def position_before?([], []) do
    false
  end

  def position_before?([], [{bit, _disambiguator} | _rest]) do
    bit == 1
  end

  def position_before?([{bit, _disambiguator} | _rest], []) do
    bit == 0
  end

  def position_before?([step | left_rest], [step | right_rest]) do
    position_before?(left_rest, right_rest)
  end

  def position_before?([left_step | _left_rest], [right_step | _right_rest]) do
    left_step < right_step
  end

  def ordered_entries(document) do
    Enum.sort(Map.to_list(document.characters_by_position), fn {left_position, _left_character},
                                                               {right_position, _right_character} ->
      position_before?(left_position, right_position)
    end)
  end

  # Guarda lo borrado para futuras operaciones, pero lo oculta del texto.
  def visible_entries(document) do
    exclude_tombstoned_entries(ordered_entries(document), document.tombstones)
  end

  def text(document) do
    Enum.map_join(visible_entries(document), fn {_position_id, character} -> character end)
  end

  # Busca una posicion entre los vecinos para poner el caracter nuevo.
  # Cada paso lleva una direccion y un identificador unico.
  def new_position_id(:start, :finish, disambiguator) do
    [{1, disambiguator}]
  end

  def new_position_id(:start, right_position, disambiguator) do
    right_position ++ [{0, disambiguator}]
  end

  def new_position_id(left_position, :finish, disambiguator) do
    left_position ++ [{1, disambiguator}]
  end

  def new_position_id(left_position, right_position, disambiguator) do
    if is_prefix?(left_position, right_position) do
      right_position ++ [{0, disambiguator}]
    else
      left_position ++ [{1, disambiguator}]
    end
  end

  def position_id_for(document, left_position, right_position, disambiguator) do
    {_counter, site} = disambiguator

    if left_position == :start or left_position != document.last_local_position or
         (right_position != :finish and is_prefix?(left_position, right_position)) do
      new_position_id(left_position, right_position, disambiguator)
    else
      available_slot = next_available_slot(left_position, site)

      if available_slot != nil and
           not Map.has_key?(document.characters_by_position, available_slot) and
           position_before?(left_position, available_slot) and
           (right_position == :finish or position_before?(available_slot, right_position)) do
        available_slot
      else
        extend_position(left_position, disambiguator)
      end
    end
  end

  # Calcula cuantos niveles hacen falta para insertar varios caracteres.
  def subtree_levels(height) do
    if height <= 1 do
      1
    else
      ceiling_log2(height, 0) + 1
    end
  end

  # Revisa e inserta un caracter; tambien devuelve la operacion para los pares.
  def insert(document, index, character, site) do
    ordered_entries = ordered_entries(document)
    visible_entries = exclude_tombstoned_entries(ordered_entries, document.tombstones)

    cond do
      not is_integer(index) or index < 0 or index > length(visible_entries) ->
        {:error, :invalid_position}

      not valid_character?(character) ->
        {:error, :invalid_character}

      true ->
        # Busca el vecino derecho, incluso si esta marcado como borrado.
        left_position = previous_position(visible_entries, index)
        right_position = next_position(ordered_entries, left_position)
        next_counter = document.local_counter + 1
        disambiguator = {next_counter, site}

        position_id =
          position_id_for(document, left_position, right_position, disambiguator)

        operation = %{type: :insert, position_id: position_id, character: character}

        updated_document =
          %{
            apply_operation(document, operation)
            | local_counter: next_counter,
              last_local_position: position_id
          }

        {updated_document, operation}
    end
  end

  # Marca como borrado el caracter que esta en ese indice.
  def delete(document, index) do
    visible_entries = visible_entries(document)

    if is_integer(index) and index >= 0 and index < length(visible_entries) do
      {position_id, _character} = Enum.at(visible_entries, index)

      # Conserva el caracter y guarda la marca para compartirla con los pares.
      operation = %{type: :delete, position_id: position_id}
      {apply_operation(document, operation), operation}
    else
      {:error, :invalid_position}
    end
  end

  # Aplica una operacion que llego de otro nodo.
  # Repetirla no cambia el resultado.
  def apply_operation(document, %{type: :insert, position_id: position_id, character: character}) do
    update = %{empty() | characters_by_position: %{position_id => character}}
    merge(document, update)
  end

  def apply_operation(document, %{type: :delete, position_id: position_id}) do
    update = %{empty() | tombstones: MapSet.new([position_id])}
    merge(document, update)
  end

  def apply_operation(document, _unknown_operation), do: document

  def merge(left_document, right_document) do
    # Junta los caracteres y las marcas de borrado de ambos documentos.
    # Si chocan dos caracteres, elige uno siempre con la misma regla.
    %{
      left_document
      | characters_by_position:
          Map.merge(
            left_document.characters_by_position,
            right_document.characters_by_position,
            fn _position_id, left_character, right_character ->
              max(left_character, right_character)
            end
          ),
        tombstones: MapSet.union(left_document.tombstones, right_document.tombstones)
    }
  end

  # Usa los mismos limites para cambios locales y mensajes de red.
  # Asi todas las replicas aceptan o rechazan lo mismo.
  defp valid_character?(character) when is_binary(character) do
    byte_size(character) <= @max_character_bytes and String.valid?(character) and
      match?([_], String.graphemes(character))
  end

  defp valid_character?(_character), do: false

  defp exclude_tombstoned_entries(ordered_entries, tombstones) do
    Enum.reject(ordered_entries, fn {position_id, _character} ->
      MapSet.member?(tombstones, position_id)
    end)
  end

  defp previous_position(_visible_entries, 0) do
    :start
  end

  defp previous_position(visible_entries, index) do
    {position_id, _character} = Enum.at(visible_entries, index - 1)
    position_id
  end

  defp next_position([], :start) do
    :finish
  end

  defp next_position([{position_id, _character} | _rest], :start) do
    position_id
  end

  defp next_position(ordered_entries, left_position) do
    case Enum.drop_while(ordered_entries, fn {position_id, _character} ->
           position_id != left_position
         end) do
      [_left_entry, {right_position, _right_character} | _rest] -> right_position
      _other -> :finish
    end
  end

  defp extend_position(position_id, disambiguator) do
    position_id ++
      [{1, disambiguator}] ++
      List.duplicate({0, disambiguator}, subtree_levels(length(position_id)) - 1)
  end

  defp next_available_slot(position_id, site) do
    {_bit, disambiguator} = List.last(position_id)
    {_counter, owner_site} = disambiguator

    {position_prefix, owned_steps} =
      Enum.split_while(position_id, fn {_step_bit, step_disambiguator} ->
        step_disambiguator != disambiguator
      end)

    case owned_steps do
      [{1, _step_disambiguator} | relative_steps] ->
        if owner_site == site and
             Enum.all?(relative_steps, fn {_step_bit, step_disambiguator} ->
               step_disambiguator == disambiguator
             end) do
          next_slot(
            position_prefix ++ [{1, disambiguator}],
            relative_steps,
            disambiguator,
            subtree_levels(length(position_prefix))
          )
        else
          nil
        end

      _other ->
        nil
    end
  end

  defp next_slot(root_position, relative_steps, disambiguator, levels) do
    if length(relative_steps) < levels - 1 do
      root_position ++
        relative_steps ++
        [{1, disambiguator}] ++
        List.duplicate({0, disambiguator}, levels - 2 - length(relative_steps))
    else
      case Enum.drop_while(Enum.reverse(relative_steps), fn {bit, _step_disambiguator} ->
             bit == 1
           end) do
        [] -> nil
        [_step | remaining_steps] -> root_position ++ Enum.reverse(remaining_steps)
      end
    end
  end

  defp ceiling_log2(height, exponent) do
    if Integer.pow(2, exponent) >= height do
      exponent
    else
      ceiling_log2(height, exponent + 1)
    end
  end

  # Revisa si una posicion empieza igual que su prefijo.
  defp is_prefix?([], _position), do: true

  defp is_prefix?([step | prefix_rest], [step | position_rest]),
    do: is_prefix?(prefix_rest, position_rest)

  defp is_prefix?(_prefix, _position), do: false
end
