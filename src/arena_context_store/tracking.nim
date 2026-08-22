## Always-on access tracking for the arena context store.
##
## Every read and write operation is recorded when a consumer is active
## (pushed via pushConsumer). Consumers are identified by uint32 IDs.
## Use readSet/iterateSet/writeSet to query which nodes a consumer accessed.
##
## Accesses distinguish reads of a node's own value (akRead with NoEdge),
## traversals of a single container edge (akRead with an edge index), and
## dependencies on a container's whole edge set (akIterate). See AccessRecord
## in types.nim for the invalidation semantics.

import types

# --- Consumer management ---

proc pushConsumer*(arena: var Arena, consumerId: uint32) =
  ## Push a consumer onto the context stack. All subsequent reads/writes
  ## will be attributed to this consumer.
  arena.consumerStack.add(consumerId)

proc popConsumer*(arena: var Arena) =
  ## Pop the current consumer from the context stack.
  assert arena.consumerStack.len > 0, "Consumer stack underflow"
  arena.consumerStack.setLen(arena.consumerStack.len - 1)

proc currentConsumer*(arena: Arena): uint32 =
  ## Return the current consumer ID, or InvalidConsumerId if none.
  if arena.consumerStack.len > 0:
    arena.consumerStack[^1]
  else:
    InvalidConsumerId

# --- Internal recording ---

proc recordAccess*(arena: var Arena, kind: AccessKind, nodeId: NodeId,
                   edge: uint32 = NoEdge) =
  ## Record an access if a consumer is active. Called by read/write procs.
  ## `edge` is the entry index (objects) or child index (arrays) when the
  ## access traversed a single edge of a container.
  if arena.consumerStack.len > 0:
    arena.accesses.add(AccessRecord(
      kind: kind,
      nodeId: nodeId,
      edge: edge,
      consumerId: arena.consumerStack[^1],
    ))

# --- Query ---

proc readSet*(arena: Arena, consumerId: uint32): seq[NodeId] =
  ## Return unique NodeIds read by the given consumer.
  for rec in arena.accesses:
    if rec.consumerId == consumerId and rec.kind == akRead:
      var found = false
      for existing in result:
        if existing == rec.nodeId:
          found = true
          break
      if not found:
        result.add(rec.nodeId)

proc iterateSet*(arena: Arena, consumerId: uint32): seq[NodeId] =
  ## Return unique NodeIds whose edge set the given consumer depends on
  ## (iteration, length checks, and missed lookups).
  for rec in arena.accesses:
    if rec.consumerId == consumerId and rec.kind == akIterate:
      var found = false
      for existing in result:
        if existing == rec.nodeId:
          found = true
          break
      if not found:
        result.add(rec.nodeId)

proc writeSet*(arena: Arena, consumerId: uint32): seq[NodeId] =
  ## Return unique NodeIds written by the given consumer.
  for rec in arena.accesses:
    if rec.consumerId == consumerId and rec.kind == akWrite:
      var found = false
      for existing in result:
        if existing == rec.nodeId:
          found = true
          break
      if not found:
        result.add(rec.nodeId)

proc clearTracking*(arena: var Arena) =
  ## Remove all access records.
  arena.accesses.setLen(0)

proc clearTracking*(arena: var Arena, consumerId: uint32) =
  ## Remove access records for a specific consumer.
  var i = 0
  while i < arena.accesses.len:
    if arena.accesses[i].consumerId == consumerId:
      arena.accesses.delete(i)
    else:
      i += 1
