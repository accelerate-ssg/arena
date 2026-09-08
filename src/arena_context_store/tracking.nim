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
##
## The log lives behind a ref (Arena.tracking) so recording works through an
## immutable Arena: read procs never need var access. Setting Arena.tracking
## to nil disables tracking entirely.

import types

# --- Consumer management ---

proc pushConsumer*(arena: Arena, consumerId: uint32) =
  ## Push a consumer onto the context stack. All subsequent reads/writes
  ## will be attributed to this consumer.
  assert arena.tracking != nil, "Tracking is disabled"
  arena.tracking.consumerStack.add(consumerId)

proc popConsumer*(arena: Arena) =
  ## Pop the current consumer from the context stack.
  assert arena.tracking != nil, "Tracking is disabled"
  assert arena.tracking.consumerStack.len > 0, "Consumer stack underflow"
  arena.tracking.consumerStack.setLen(arena.tracking.consumerStack.len - 1)

proc currentConsumer*(arena: Arena): uint32 =
  ## Return the current consumer ID, or InvalidConsumerId if none.
  if arena.tracking != nil and arena.tracking.consumerStack.len > 0:
    arena.tracking.consumerStack[^1]
  else:
    InvalidConsumerId

# --- Internal recording ---

proc recordAccess*(arena: Arena, kind: AccessKind, nodeId: NodeId,
                   edge: uint32 = NoEdge) =
  ## Record an access if a consumer is active. Called by read/write procs.
  ## `edge` is the entry index (objects) or child index (arrays) when the
  ## access traversed a single edge of a container.
  if arena.tracking != nil and arena.tracking.consumerStack.len > 0:
    arena.tracking.accesses.add(AccessRecord(
      kind: kind,
      nodeId: nodeId,
      edge: edge,
      consumerId: arena.tracking.consumerStack[^1],
    ))

# --- Query ---

proc accesses*(arena: Arena): seq[AccessRecord] =
  ## The raw access log. Empty if tracking is disabled.
  if arena.tracking != nil:
    arena.tracking.accesses
  else:
    @[]

proc accessSet(arena: Arena, consumerId: uint32, kind: AccessKind): seq[NodeId] =
  ## Unique NodeIds the consumer touched with the given access kind.
  ## Iterates the log in place — the `accesses` proc would copy it.
  if arena.tracking == nil:
    return
  for rec in arena.tracking.accesses:
    if rec.consumerId == consumerId and rec.kind == kind:
      var found = false
      for existing in result:
        if existing == rec.nodeId:
          found = true
          break
      if not found:
        result.add(rec.nodeId)

proc readSet*(arena: Arena, consumerId: uint32): seq[NodeId] =
  ## Return unique NodeIds read by the given consumer.
  arena.accessSet(consumerId, akRead)

proc iterateSet*(arena: Arena, consumerId: uint32): seq[NodeId] =
  ## Return unique NodeIds whose edge set the given consumer depends on
  ## (iteration, length checks, and missed lookups).
  arena.accessSet(consumerId, akIterate)

proc writeSet*(arena: Arena, consumerId: uint32): seq[NodeId] =
  ## Return unique NodeIds written by the given consumer.
  arena.accessSet(consumerId, akWrite)

proc clearTracking*(arena: Arena) =
  ## Remove all access records.
  if arena.tracking != nil:
    arena.tracking.accesses.setLen(0)

proc clearTracking*(arena: Arena, consumerId: uint32) =
  ## Remove access records for a specific consumer.
  ##
  ## Single-pass compaction: `seq.delete` shifts the whole tail per
  ## removed record, which turned this into an accidental quadratic —
  ## called once per content file against an access log that grows with
  ## every load, it dominated large builds (98% of load-phase samples on
  ## a 3,200-file site).
  if arena.tracking == nil:
    return
  var j = 0
  for i in 0 ..< arena.tracking.accesses.len:
    if arena.tracking.accesses[i].consumerId != consumerId:
      if j != i:
        arena.tracking.accesses[j] = move arena.tracking.accesses[i]
      j.inc
  arena.tracking.accesses.setLen(j)

proc retireSubtree*(arena: Arena, id: NodeId) =
  ## Record a write on every node of a subtree that is being replaced
  ## wholesale, and on every edge of each container in it. Readers that
  ## reached those nodes directly — through a handle rather than an edge
  ## from an ancestor — are invalidated like any other reader of what
  ## was rebound. Reads nothing into the log while walking.
  if arena.tracking == nil or arena.tracking.consumerStack.len == 0:
    return
  var stack = @[id]
  while stack.len > 0:
    let node = stack.pop()
    if node == InvalidNodeId:
      continue
    arena.recordAccess(akWrite, node)
    let n = arena.nodes[uint32(node)]
    case n.kind
    of nkArray:
      for i in 0'u32 ..< n.childLen:
        arena.recordAccess(akWrite, node, i)
        stack.add(arena.children[n.childOffset + i])
    of nkObject:
      for i in 0'u32 ..< n.entryCount:
        arena.recordAccess(akWrite, node, i)
        stack.add(arena.entries[n.entryOffset + i].valueNode)
    else:
      discard
