# Mensajes que usan las replicas

La replica se registra como `Crdt.Replica`. Los cambios se mandan como mensajes
asincronos de GenServer, con el mismo formato que usa la implementacion de Nerves:

```elixir
{:remote, %{op: :ins, from: actor, vc: %{actor => sequence},
            pos: [{bit, sequence, actor}], ch: "a"}}
{:remote, %{op: :del, from: actor, vc: %{actor => sequence},
            pos: [{bit, sequence, actor}]}}
{:hello, actor}
```

`op` puede ser `:ins` o `:del`; `from` identifica quien hizo el cambio; `vc` es
el reloj vectorial; `pos` guarda los pasos de la posicion; y cada paso tiene un
bit (`0` o `1`), una secuencia y un actor. `ch` trae un solo grafema UTF-8.
La funcion `insert/2` puede recibir un texto completo, pero lo manda como varias
operaciones `:ins`, una por grafema. El formato de red no cambia.

Al arrancar, cada replica crea un actor nuevo para no repetir identificadores.
La Pi guarda las operaciones en `/data/cpd_doc/operations.log` y las recupera
al reiniciar. El reloj causal espera operaciones anteriores y descarta mensajes
repetidos.

Se conserva el nombre del proceso y el formato que espera la otra implementacion
de Nerves. El orden Treedoc y las reglas para aplicar cambios son las de este
proyecto.
