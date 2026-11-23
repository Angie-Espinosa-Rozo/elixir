defmodule CpdDoc.TreeDoc do
  @moduledoc """
  Treedoc sequence CRDT for a shared text document.

  Each character has a stable `position_id`. Deletions are stored as
  tombstones, so an old operation cannot make a deleted character visible
  again. A local edit returns the operation that replicas should broadcast.
  """

  @max_character_bytes 4_096

  # Crea el estado minimo del documento, sin caracteres ni marcas de borrado.
  def empty do
    %{characters_by_position: %{}, tombstones: MapSet.new()}
  end

  def new do
    Map.merge(empty(), %{local_counter: 0, last_local_position: nil})
  end

  # Compara dos posiciones segun el recorrido infijo definido por Treedoc.
  # Todas las replicas usan esta regla para mostrar los caracteres en el mismo orden.
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

  # Conserva las entradas de caracteres borradas para futuras operaciones, pero las excluye del texto visible.
  def visible_entries(document) do
    exclude_tombstoned_entries(ordered_entries(document), document.tombstones)
  end

  def text(document) do
    Enum.map_join(visible_entries(document), fn {_position_id, character} -> character end)
  end

  # Construye una posicion entre los vecinos indicados para ubicar un caracter nuevo.
  # Cada paso combina un bit de direccion con un identificador de operacion unico.
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

  # Calcula los niveles necesarios para distribuir una secuencia de inserciones.
  def subtree_levels(height) do
    if height <= 1 do
      1
    else
      ceiling_log2(height, 0) + 1
    end
  end

  # Valida y aplica una insercion local, y devuelve la operacion que se envia a los pares.
  def insert(document, index, character, site) do
    ordered_entries = ordered_entries(document)
    visible_entries = exclude_tombstoned_entries(ordered_entries, document.tombstones)

    cond do
      not is_integer(index) or index < 0 or index > length(visible_entries) ->
        {:error, :invalid_position}

      not valid_character?(character) ->
        {:error, :invalid_character}

      true ->
        # Busca el vecino derecho entre todas las entradas, incluidas las que tienen tombstone.
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

  # Marca como borrado el caracter visible en el indice solicitado.
  def delete(document, index) do
    visible_entries = visible_entries(document)

    if is_integer(index) and index >= 0 and index < length(visible_entries) do
      {position_id, _character} = Enum.at(visible_entries, index)

      # Mantiene la entrada del caracter y registra el borrado para combinarlo con las otras replicas.
      operation = %{type: :delete, position_id: position_id}
      {apply_operation(document, operation), operation}
    else
      {:error, :invalid_position}
    end
  end

  # Integra una operacion recibida desde otro nodo.
  # Aplicar la misma operacion varias veces deja el documento en el mismo estado.
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
    # Combina las entradas de caracteres y los tombstones de ambos documentos.
    # Ante caracteres distintos para una misma posicion, elige el mayor de forma determinista.
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

  # Aplica los mismos limites a las ediciones locales y a los datos recibidos por red.
  # Asi todas las replicas aceptan o rechazan el mismo caracter.
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

  # Comprueba si todos los pasos del prefijo coinciden con el inicio de la posicion.
  defp is_prefix?([], _position), do: true

  defp is_prefix?([step | prefix_rest], [step | position_rest]),
    do: is_prefix?(prefix_rest, position_rest)

  defp is_prefix?(_prefix, _position), do: false
end
