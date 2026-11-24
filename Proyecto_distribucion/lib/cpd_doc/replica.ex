defmodule CpdDoc.Replica do
  @moduledoc "Maneja el documento local y comparte los cambios con las otras replicas."

  use GenServer
  require Logger

  alias CpdDoc.{Causal, OperationLog, Protocol, TreeDoc}

  @process_name Crdt.Replica

  def start_link(arguments), do: GenServer.start_link(__MODULE__, arguments, name: @process_name)

  def insert(index, text), do: GenServer.call(@process_name, {:insert, index, text})
  def delete(index), do: delete(index, 1)
  def delete(index, count), do: GenServer.call(@process_name, {:delete, index, count})
  def text(), do: GenServer.call(@process_name, :text)

  def broadcast(message) do
    Enum.each(Node.list(), fn node_name -> GenServer.cast({@process_name, node_name}, message) end)

    :ok
  end

  @impl true
  def init(_arguments) do
    :net_kernel.monitor_nodes(true)
    actor = unique_actor()

    initial_state = %{
      document: TreeDoc.new(),
      actor: actor,
      clock: %{},
      buffer: [],
      history: []
    }

    case load_history(initial_state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, {:operation_log_load_failed, reason}}
    end
  end

  @impl true
  def handle_call({:insert, index, text}, _from, state) do
    with :ok <- validate_insert_index(state.document, index),
         {:ok, graphemes} <- split_text(text),
         {:ok, updated_state, messages} <- insert_graphemes(index, graphemes, state) do
      chronological_messages = Enum.reverse(messages)

      case persist_operations(chronological_messages) do
        :ok ->
          Enum.each(chronological_messages, &broadcast/1)
          {:reply, :ok, updated_state}

        {:error, reason} ->
          {:reply, {:error, {:persistence, reason}}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, index, count}, _from, state) do
    with :ok <- validate_delete_range(state.document, index, count),
         {:ok, updated_state, messages} <- delete_graphemes(index, count, state) do
      chronological_messages = Enum.reverse(messages)

      case persist_operations(chronological_messages) do
        :ok ->
          Enum.each(chronological_messages, &broadcast/1)
          {:reply, :ok, updated_state}

        {:error, reason} ->
          {:reply, {:error, {:persistence, reason}}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:text, _from, state), do: {:reply, TreeDoc.text(state.document), state}
  def handle_call(_request, _from, state), do: {:reply, {:error, :unknown_call}, state}

  @impl true
  def handle_cast({:remote, raw_message}, state) do
    case Protocol.parse(raw_message) do
      {:ok, message} -> {:noreply, receive_operation(message, state)}
      :ignore -> {:noreply, state}
    end
  end

  def handle_cast({:hello, _peer_actor}, state) do
    Enum.each(Enum.reverse(state.history), &broadcast_to_all/1)
    {:noreply, state}
  end

  def handle_cast(_unknown_message, state), do: {:noreply, state}

  @impl true
  def handle_info({:nodeup, node_name}, state) do
    Enum.each(Enum.reverse(state.history), fn message ->
      GenServer.cast({@process_name, node_name}, message)
    end)

    GenServer.cast({@process_name, node_name}, {:hello, state.actor})
    {:noreply, state}
  end

  def handle_info(_unknown_message, state), do: {:noreply, state}

  defp receive_operation(message, state) do
    {clock, buffer, events} = Causal.receive_message(state.clock, state.buffer, message)

    if events == [] do
      %{state | clock: clock, buffer: buffer}
    else
      wrapped_messages = Enum.map(events, &{:remote, &1})

      case persist_operations(wrapped_messages) do
        :ok ->
          Enum.reduce(events, %{state | clock: clock, buffer: buffer}, fn delivered_message,
                                                                          current_state ->
            operation = Protocol.to_tree_operation(delivered_message)
            document = TreeDoc.apply_operation(current_state.document, operation)
            wrapped_message = {:remote, delivered_message}
            forward_to_peers(wrapped_message)

            %{
              current_state
              | document: document,
                history: [wrapped_message | current_state.history]
            }
          end)

        {:error, reason} ->
          Logger.error("Could not persist received operations: #{inspect(reason)}")
          %{state | buffer: Enum.uniq(state.buffer ++ [message])}
      end
    end
  end

  defp forward_to_peers(message) do
    # Se reenvia cuando ya se puede aplicar en el orden correcto.
    Enum.each(Node.list(), fn peer ->
      GenServer.cast({@process_name, peer}, message)
    end)
  end

  defp broadcast_to_all(message), do: broadcast(message)

  defp load_history(state) do
    case operation_log_path() do
      nil ->
        {:ok, state}

      path ->
        case OperationLog.load(path) do
          {:ok, messages} ->
            {:ok, Enum.reduce(messages, state, &restore_operation/2)}

          {:error, reason} ->
            Logger.error("Could not load operation history from #{path}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp restore_operation({:remote, raw_message}, state) do
    {:ok, message} = Protocol.parse(raw_message)
    operation = Protocol.to_tree_operation(message)
    document = TreeDoc.apply_operation(state.document, operation)
    clock = Map.put(state.clock, message.from, message.vc[message.from])
    %{state | document: document, clock: clock, history: [{:remote, message} | state.history]}
  end

  defp persist_operations(messages) do
    case operation_log_path() do
      nil -> :ok
      path -> OperationLog.append(path, messages)
    end
  end

  defp operation_log_path, do: Application.get_env(:cpd_doc, :operation_log_path)

  defp validate_insert_index(document, index) do
    visible_length = length(TreeDoc.visible_entries(document))

    if is_integer(index) and index >= 0 and index <= visible_length,
      do: :ok,
      else: {:error, :invalid_position}
  end

  defp validate_delete_range(document, index, count) do
    visible_length = length(TreeDoc.visible_entries(document))

    if is_integer(index) and is_integer(count) and index >= 0 and count >= 0 and
         index <= visible_length and index + count <= visible_length,
       do: :ok,
       else: {:error, :invalid_position}
  end

  defp split_text(text) when is_binary(text) do
    if String.valid?(text),
      do: {:ok, String.graphemes(text)},
      else: {:error, :invalid_character}
  end

  defp split_text(_text), do: {:error, :invalid_character}

  defp insert_graphemes(index, graphemes, state) do
    graphemes
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state, []}, fn {grapheme, offset},
                                              {:ok, current_state, messages} ->
      case TreeDoc.insert(
             current_state.document,
             index + offset,
             grapheme,
             {current_state.actor, 1}
           ) do
        {:error, reason} ->
          {:halt, {:error, reason}}

        {document, operation} ->
          {_sequence, clock} = Causal.next_local(current_state.clock, current_state.actor)
          message = Protocol.encode_operation(operation, current_state.actor, clock)

          updated_state = %{
            current_state
            | document: document,
              clock: clock,
              history: [message | current_state.history]
          }

          {:cont, {:ok, updated_state, [message | messages]}}
      end
    end)
  end

  defp delete_graphemes(_index, 0, state), do: {:ok, state, []}

  defp delete_graphemes(index, count, state) do
    Enum.reduce_while(1..count, {:ok, state, []}, fn _number, {:ok, current_state, messages} ->
      case TreeDoc.delete(current_state.document, index) do
        {:error, reason} ->
          {:halt, {:error, reason}}

        {document, operation} ->
          {_sequence, clock} = Causal.next_local(current_state.clock, current_state.actor)
          message = Protocol.encode_operation(operation, current_state.actor, clock)

          updated_state = %{
            current_state
            | document: document,
              clock: clock,
              history: [message | current_state.history]
          }

          {:cont, {:ok, updated_state, [message | messages]}}
      end
    end)
  end

  defp unique_actor do
    suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    String.to_atom("#{node()}-#{suffix}")
  end
end
