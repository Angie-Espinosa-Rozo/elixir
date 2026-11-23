# Convergence rules

Each inserted character receives a stable Treedoc position. Concurrent
insertions are ordered by the position path, so all replicas display them in the
same order. A deletion adds a tombstone; it does not erase the original
character record. Therefore, receiving a deletion before its insertion still
leaves the character hidden.

`CpdDoc.Causal` uses vector clocks to deliver each operation only after its
causal dependencies have arrived. Duplicate operations are ignored, and
operations waiting for a missing predecessor remain buffered. Newly delivered
operations are forwarded to connected peers and recorded in the in-memory
history for reconnect synchronization.

These rules converge while at least one running replica retains the history.
The project does not persist the document across a complete shutdown.
