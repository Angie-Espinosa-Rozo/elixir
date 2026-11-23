# Prueba manual de red. Ejecútala solo en una computadora; en la otra inicia
# el mismo proyecto con IEx y espera la conexión.
# Variable requerida: PEER_NODE, por ejemplo "doc@172.20.10.4".

alias CpdDoc.Replica

case System.get_env("PEER_NODE") do
  nil ->
    raise "Set PEER_NODE to the full remote node name, for example PEER_NODE=doc@172.20.10.4"

  remote_node_name ->
    remote_node = String.to_atom(remote_node_name)

    unless Node.alive?() do
      raise "Start Elixir with --name and --cookie before running this file"
    end

    unless Node.connect(remote_node) do
      raise "Could not connect to #{remote_node_name}; check the IP, cookie, and firewall"
    end

    unless Node.ping(remote_node) == :pong and
             :rpc.call(remote_node, Process, :whereis, [Crdt.Replica]) != nil do
      raise "The remote node is not responding or its Crdt.Replica process is not running"
    end

    # Primero espera que el historial previo de ambas réplicas se intercambie.
    initial_sync_complete =
      Enum.reduce_while(1..50, false, fn _, _accumulator ->
        remote_text = :rpc.call(remote_node, CpdDoc.Replica, :text, [])

        if remote_text == Replica.text() do
          {:halt, true}
        else
          Process.sleep(200)
          {:cont, false}
        end
      end)

    unless initial_sync_complete do
      raise "Initial operation history did not synchronize within 10 seconds"
    end

    # Escoge una letra ausente del texto para que la comprobación sea visible.
    local_text_before_test = Replica.text()

    test_character =
      Enum.find(String.graphemes("QZXWVKJH"), fn character ->
        not String.contains?(local_text_before_test, character)
      end)

    if test_character == nil, do: raise("Choose another text or add more test characters")

    :ok = Replica.insert(0, test_character)

    replicas_converged =
      Enum.reduce_while(1..50, false, fn _, _accumulator ->
        local_text = Replica.text()
        remote_text = :rpc.call(remote_node, CpdDoc.Replica, :text, [])

        if remote_text == local_text do
          {:halt, true}
        else
          Process.sleep(200)
          {:cont, false}
        end
      end)

    if replicas_converged do
      IO.puts("OK: both nodes show the same text: #{inspect(Replica.text())}")
    else
      raise "The nodes connected, but the document did not converge within 10 seconds"
    end
end
