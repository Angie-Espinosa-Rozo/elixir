# Prueba manual de red. Corre esto en una maquina y deja IEx abierto en la otra.
# PEER_NODE lleva el nombre completo del otro nodo, por ejemplo "doc@172.20.10.4".

alias CpdDoc.Replica

case System.get_env("PEER_NODE") do
  nil ->
    raise "Define PEER_NODE con el nombre completo del otro nodo, por ejemplo PEER_NODE=doc@172.20.10.4"

  remote_node_name ->
    remote_node = String.to_atom(remote_node_name)

    unless Node.alive?() do
      raise "Arranca Elixir con --name y --cookie antes de correr este archivo"
    end

    unless Node.connect(remote_node) do
      raise "No pude conectar con #{remote_node_name}; revisa la IP, la cookie y el firewall"
    end

    unless Node.ping(remote_node) == :pong and
             :rpc.call(remote_node, Process, :whereis, [Crdt.Replica]) != nil do
      raise "El otro nodo no responde o no tiene corriendo Crdt.Replica"
    end

    # Primero espera a que las dos replicas intercambien su historial.
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
      raise "El historial no se sincronizo en 10 segundos"
    end

    # Escoge una letra que no este en el texto para que se note el cambio.
    local_text_before_test = Replica.text()

    test_character =
      Enum.find(String.graphemes("QZXWVKJH"), fn character ->
        not String.contains?(local_text_before_test, character)
      end)

    if test_character == nil, do: raise("Cambia el texto o agrega mas letras para probar")

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
      IO.puts("Listo: los dos nodos muestran el mismo texto: #{inspect(Replica.text())}")
    else
      raise "Los nodos conectaron, pero el documento no quedo igual en 10 segundos"
    end
end
