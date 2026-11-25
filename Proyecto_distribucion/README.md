# Proyecto de distribucion: Treedoc por operaciones

Este paquete contiene una sola aplicación: un documento distribuido Treedoc.
Cada nodo mantiene una réplica local, genera una operación por edición y la
envía a los otros nodos. No hay servidor central.

Cada caracter tiene una posicion fija. Al borrar, Treedoc deja una marca para
que un mensaje atrasado no lo muestre de nuevo. El reloj vectorial espera los
cambios anteriores y descarta los repetidos.

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
CpdDoc.Replica.insert(1, "ola, mundo")
CpdDoc.Replica.delete(0)
CpdDoc.Replica.text()
```

`insert/2` acepta un texto completo y lo divide en grafemas para insertarlos
desde la posición indicada. Cada grafema se transmite como una operación del
protocolo existente.

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

- `lib/cpd_doc/tree_doc.ex`: posiciones, inserciones, borrados y aplicacion de cambios.
- `lib/cpd_doc/protocol.ex`: formato de mensajes y validacion.
- `lib/cpd_doc/causal.ex`: reloj vectorial y entrega ordenada de cambios.
- `lib/cpd_doc/replica.ex`: proceso `Crdt.Replica`, API e historial.
- `lib/cpd_doc/operation_log.ex`: guardado y recuperacion del historial.
- `lib/cpd_doc/discovery.ex` y `lib_target/boot.ex`: arranque y busqueda de pares.
- `test/`: pruebas locales del Treedoc y de la red.
- `scripts/test_two_computers.exs`: prueba manual entre dos computadores.
- `PROTOCOL.md`: formato de mensajes que comparten las replicas.

La Pi conserva el historial en `/data/cpd_doc/operations.log`, incluso al
reiniciar. La replica de la laptop solo lo guarda en memoria. Para que dos
maquinas se entiendan, ambas deben usar el mismo formato de mensajes y las
mismas reglas de orden Treedoc.

## Raspberry Pi

La configuración de Nerves está en `config/` y `lib_target/`. Para compilar el
firmware de una Pi 4, configura las credenciales del Wi-Fi y ejecuta:

```sh
export MIX_TARGET=rpi4 HOTSPOT_SSID="cpd2026" HOTSPOT_PSK="1234567890"
mix deps.get
mix firmware
mix burn
```

Al arrancar, la Pi espera a que `wlan0` reciba una dirección IPv4. Entonces
inicia automáticamente el nodo distribuido `doc@<IP>`, la réplica y el
descubrimiento de pares. Para comprobarlo desde la consola SSH de Nerves:

```elixir
Node.self()
Process.whereis(Crdt.Replica)
CpdDoc.Replica.text()
```

En la Pi, la replica guarda las operaciones aceptadas en
`/data/cpd_doc/operations.log` y reconstruye el documento al arrancar. En la
laptop, la replica solo vive en memoria. El archivo de la Pi crece con el uso y
por ahora no se compacta solo.

### Editor en el monitor conectado a la Pi

Conecta un monitor por HDMI y un teclado USB. En la consola IEx que aparece en
ese monitor (no en una sesión SSH), ejecuta:

```elixir
CpdDoc.Editor.start()
```

Escribe el texto y pulsa Enter. Luego indica `s` para agregar un salto de línea
o `n` para continuar el texto en la misma línea. Usa `:d N` para borrar los
últimos N caracteres, `:clear` para borrar todo el documento compartido y
`:exit` para regresar a IEx. La pantalla se actualiza al recibir cambios
remotos.
