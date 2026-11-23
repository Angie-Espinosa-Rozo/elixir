# Proyecto de distribución: Treedoc operation-based

Este paquete contiene una sola aplicación: un documento distribuido Treedoc.
Cada nodo mantiene una réplica local, genera una operación por edición y la
envía a los otros nodos. No hay servidor central.

## Ejecutar en un computador

Desde esta carpeta:

```sh
mix deps.get
MIX_TARGET=host mix test test/tree_doc_operation_test.exs
MIX_TARGET=host iex --name doc1@127.0.0.1 --cookie cpd2026 -S mix
```

Para una segunda réplica local, abre otra terminal y usa otro nombre:

```sh
MIX_TARGET=host iex --name doc2@127.0.0.1 --cookie cpd2026 -S mix
```

Conecta los nodos desde cualquiera de las sesiones:

```elixir
Node.connect(:"doc2@127.0.0.1")
```

Ambos nodos deben usar nombres largos (`--name`) y la misma cookie. En IEx:

```elixir
CpdDoc.Replica.insert(0, "h")
CpdDoc.Replica.delete(0)
CpdDoc.Replica.text()
```

## Probar dos computadores

1. En el computador receptor inicia el proyecto con su IP:

   ```sh
   MIX_TARGET=host iex --name doc@192.168.1.24 --cookie cpd2026 -S mix
   ```

2. En el computador que ejecutará la prueba, inicia IEx indicando su IP y el
   nombre completo del receptor:

   ```sh
   PEER_NODE=doc@192.168.1.24 MIX_TARGET=host iex --name doc@192.168.1.23 --cookie cpd2026 -S mix
   ```

3. Ejecuta el archivo de integración:

   ```elixir
   Code.require_file("scripts/test_two_computers.exs")
   ```

El script conecta los nodos, espera a que intercambien su historial, inserta un
carácter de prueba y comprueba que ambas réplicas converjan. Se ejecuta en una
sola computadora; en la otra basta con dejar IEx iniciado.

## Archivos principales

- `lib/cpd_doc/tree_doc.ex`: ordering, position IDs, edits, and operation application.
- `lib/cpd_doc/protocol.ex`: shared wire format and message validation.
- `lib/cpd_doc/causal.ex`: vector clocks and causal delivery.
- `lib/cpd_doc/replica.ex`: `Crdt.Replica` process, API, broadcast, and in-memory history.
- `lib/cpd_doc/discovery.ex` and `lib_target/network.ex`: network node discovery.
- `test/tree_doc_operation_test.exs`: local tests for the operation-based Treedoc.
- `scripts/test_two_computers.exs`: manual test between two computers.
- `PROTOCOL.md`: contrato de mensajes de esta implementación.
- `CRDT.md`: explicación de las reglas de convergencia.

El historial se mantiene en memoria. Si todos los nodos se apagan, se pierde el
documento. El nombre del proceso y el formato de mensajes siguen el contrato de
la implementación Nerves adjunta; ambas máquinas de la prueba deben usar el
mismo formato y las mismas reglas de orden Treedoc.

## Raspberry Pi

La configuración de Nerves está en `config/` y `lib_target/`. Para compilar el
firmware de una Pi 4, configura las credenciales del Wi-Fi y ejecuta:

```sh
export MIX_TARGET=rpi4 HOTSPOT_SSID="nombre_del_wifi" HOTSPOT_PSK="clave_del_wifi"
mix deps.get
mix firmware
mix burn
```
