defmodule CpdDoc.Replica do
  @moduledoc "Owns the local Treedoc document and exchanges operations with peers."

  use GenServer

  alias CpdDoc.{Causal, Protocol, TreeDoc}

  @process_name Crdt.Replica

  def start_link(arguments), do: GenServer.start_link(__MODULE__, arguments, name: @process_name)

  def insert(index, character), do: GenServer.call(@process_name, {:insert, index, character})
  def delete(index), do: GenServer.call(@process_name, {:delete, index})
  def text(), do: GenServer.call(@process_name, :text)

  def broadcast(message) do
    Enum.each(Node.list(), fn node_name -> GenServer.cast({@process_name, node_name}, message) end)

    :ok
  end

  @impl true
  def init(_arguments) do
    :net_kernel.monitor_nodes(true)
    actor = unique_actor()
    {:ok, %{document: TreeDoc.new(), actor: actor, clock: %{}, buffer: [], history: []}}
  end

  @impl true
  def handle_call({:insert, index, character}, _from, state) do
    case TreeDoc.insert(state.document, index, character, {state.actor, 1}) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {document, operation} ->
        {_sequence, clock} = Causal.next_local(state.clock, state.actor)
        message = Protocol.encode_operation(operation, state.actor, clock)
        state = %{state | document: document, clock: clock, history: [message | state.history]}
        broadcast(message)
        {:reply, :ok, state}
    end
  end

  def handle_call({:delete, index}, _from, state) do
    case TreeDoc.delete(state.document, index) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {document, operation} ->
        {_sequence, clock} = Causal.next_local(state.clock, state.actor)
        message = Protocol.encode_operation(operation, state.actor, clock)
        state = %{state | document: document, clock: clock, history: [message | state.history]}
        broadcast(message)
        {:reply, :ok, state}
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

    Enum.reduce(events, %{state | clock: clock, buffer: buffer}, fn delivered_message,
                                                                    current_state ->
      operation = Protocol.to_tree_operation(delivered_message)
      document = TreeDoc.apply_operation(current_state.document, operation)
      wrapped_message = {:remote, delivered_message}
      forward_to_peers(wrapped_message)

      %{current_state | document: document, history: [wrapped_message | current_state.history]}
    end)
  end

  defp forward_to_peers(message) do
    # La operacion se retransmite despues de quedar lista para aplicarse en orden causal.
    Enum.each(Node.list(), fn peer ->
      GenServer.cast({@process_name, peer}, message)
    end)
  end

  defp broadcast_to_all(message), do: broadcast(message)

  defp unique_actor do
    suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    String.to_atom("#{node()}-#{suffix}")
  end
end
