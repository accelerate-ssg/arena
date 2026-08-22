## Array operations for the arena context store.
##
## Array children are stored in a contiguous buffer of NodeId values.

import types
import tracking

proc newArr*(arena: var Arena, initialCap: int = 4): NodeId =
  ## Create a new empty array node.
  let offset = uint32(arena.children.len)
  let cap = uint32(initialCap)
  # Reserve capacity slots
  for i in 0 ..< initialCap:
    arena.children.add(InvalidNodeId)
  result = NodeId(uint32(arena.nodes.len))
  arena.nodes.add(Node(kind: nkArray, childOffset: offset, childLen: 0, childCap: cap))
  if arena.originStack.len > 0:
    arena.nodeOrigins.add(arena.originStack[^1])
  else:
    arena.nodeOrigins.add(InvalidOriginId)
  arena.recordAccess(akWrite, result)

proc arrLen*(arena: Arena, id: NodeId): int =
  ## The length depends on the whole child set, so this is an iterate.
  arena.recordAccess(akIterate, id)
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkArray, "Expected array node, got " & $node.kind
  int(node.childLen)

proc arrGet*(arena: Arena, id: NodeId, index: int): NodeId =
  ## Get child at index. Raises on out-of-bounds.
  arena.recordAccess(akRead, id, uint32(index))
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkArray, "Expected array node, got " & $node.kind
  assert index >= 0 and uint32(index) < node.childLen, "Array index out of bounds: " & $index
  arena.children[node.childOffset + uint32(index)]

proc arrPush*(arena: var Arena, id: NodeId, val: NodeId) =
  ## Append a value to the array.
  var node = arena.nodes[uint32(id)]
  assert node.kind == nkArray, "Expected array node, got " & $node.kind
  # The written edge is the slot the new element lands in.
  arena.recordAccess(akWrite, id, node.childLen)

  if node.childLen < node.childCap:
    # Fits in existing capacity
    arena.children[node.childOffset + node.childLen] = val
    node.childLen += 1
    arena.nodes[uint32(id)] = node
  else:
    # Must relocate — double capacity
    let newCap = max(node.childCap * 2, 4'u32)
    let newOffset = uint32(arena.children.len)
    # Copy existing children
    for i in 0'u32 ..< node.childLen:
      arena.children.add(arena.children[node.childOffset + i])
    # Add the new child
    arena.children.add(val)
    # Fill remaining capacity with invalid
    for i in node.childLen + 1 ..< newCap:
      arena.children.add(InvalidNodeId)
    node.childOffset = newOffset
    node.childLen += 1
    node.childCap = newCap
    arena.nodes[uint32(id)] = node

iterator arrItems*(arena: Arena, id: NodeId): NodeId =
  ## Iterate over array children.
  arena.recordAccess(akIterate, id)
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkArray
  for i in 0'u32 ..< node.childLen:
    yield arena.children[node.childOffset + i]
