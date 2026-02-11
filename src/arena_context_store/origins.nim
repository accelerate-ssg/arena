## Origin tracking for the arena context store.
##
## Each node can be tagged with an OriginId identifying where it came from.
## Origins form a linked list via the `previous` field, enabling overwrite
## history traversal.

import types

# --- Source interning ---

proc registerSource*(arena: var Arena, path: string): uint32 =
  ## Intern a source path. Returns existing index if already registered.
  for i in 0 ..< arena.sources.len:
    if arena.sources[i] == path:
      return uint32(i)
  result = uint32(arena.sources.len)
  arena.sources.add(path)

proc getSourcePath*(arena: Arena, sourceId: uint32): string =
  ## Look up a source path by its interned ID.
  arena.sources[sourceId]

# --- Origin registration ---

proc registerOrigin*(arena: var Arena, format: SourceFormat, sourceId: uint32,
                     offset: uint32 = 0,
                     previous: OriginId = InvalidOriginId): OriginId =
  ## Create a new origin record. Returns its OriginId.
  result = OriginId(uint32(arena.origins.len))
  arena.origins.add(Origin(
    format: format,
    sourceId: sourceId,
    offset: offset,
    previous: previous,
  ))

proc registerOrigin*(arena: var Arena, format: SourceFormat, path: string,
                     offset: uint32 = 0,
                     previous: OriginId = InvalidOriginId): OriginId =
  ## Convenience: registers source path and creates origin in one call.
  let sourceId = arena.registerSource(path)
  arena.registerOrigin(format, sourceId, offset, previous)

proc getOrigin*(arena: Arena, id: OriginId): Origin =
  ## Look up an Origin record by OriginId.
  arena.origins[uint32(id)]

# --- Push/pop context ---

proc pushOrigin*(arena: var Arena, origin: OriginId) =
  ## Push an origin onto the context stack. All subsequent node creation
  ## will be tagged with this origin until popOrigin is called.
  arena.originStack.add(origin)

proc popOrigin*(arena: var Arena) =
  ## Pop the current origin from the context stack.
  assert arena.originStack.len > 0, "Origin stack underflow"
  arena.originStack.setLen(arena.originStack.len - 1)

proc currentOrigin*(arena: Arena): OriginId =
  ## Return the current origin (top of stack), or InvalidOriginId if empty.
  if arena.originStack.len > 0:
    arena.originStack[^1]
  else:
    InvalidOriginId

# --- Node origin access ---

proc setNodeOrigin*(arena: var Arena, id: NodeId, origin: OriginId) =
  ## Manually set the origin for a node.
  let idx = int(uint32(id))
  assert idx < arena.nodeOrigins.len, "NodeId out of range for nodeOrigins"
  arena.nodeOrigins[idx] = origin

proc getNodeOrigin*(arena: Arena, id: NodeId): OriginId =
  ## Get the origin for a node. Returns InvalidOriginId if not set.
  let idx = int(uint32(id))
  if idx < arena.nodeOrigins.len:
    arena.nodeOrigins[idx]
  else:
    InvalidOriginId

# --- History traversal ---

proc originHistory*(arena: Arena, id: NodeId): seq[OriginId] =
  ## Walk the origin linked list from current to root.
  ## Returns [current, previous, previous-previous, ...].
  ## Empty seq if the node has no origin.
  let oid = arena.getNodeOrigin(id)
  if oid == InvalidOriginId:
    return @[]
  result = @[oid]
  var current = arena.getOrigin(oid).previous
  while current != InvalidOriginId:
    result.add(current)
    current = arena.getOrigin(current).previous

proc originDepth*(arena: Arena, id: NodeId): int =
  ## How many times this node's value was overwritten.
  ## 0 = fresh (or no origin), 1 = overwritten once, etc.
  let history = arena.originHistory(id)
  if history.len <= 1:
    0
  else:
    history.len - 1
