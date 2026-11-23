# Treedoc operation-based wire format

The replica registers under `Crdt.Replica`. Operations are sent as asynchronous
GenServer casts, using the same message shape as the supplied Nerves reference.

```elixir
{:remote, %{op: :ins, from: actor, vc: %{actor => sequence},
            pos: [{bit, sequence, actor}], ch: "a"}}
{:remote, %{op: :del, from: actor, vc: %{actor => sequence},
            pos: [{bit, sequence, actor}]}}
{:hello, actor}
```

`op` is `:ins` or `:del`; `from` is the logical actor; `vc` is a vector clock;
`pos` is a non-empty list of `{bit, sequence, actor}` steps; `bit` is `0` or
`1`; sequence values are positive in positions and non-negative in clocks; and
`ch` contains exactly one UTF-8 grapheme. The decoder bounds position depth and
clock size and ignores malformed messages.

The replica creates a fresh logical actor when it starts. This avoids reusing
operation identifiers after a restart without adding a disk log. Operations are
kept in memory, replayed on reconnection, and requested from peers with `hello`.
The causal buffer waits for missing earlier operations and the vector clock
ignores duplicates.

The compatibility process name and wire fields match the supplied Nerves
implementation. The Treedoc ordering and operation semantics remain those of
this project; this does not add durable storage.
