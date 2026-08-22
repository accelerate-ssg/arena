## Node creation and scalar access for the arena context store.

import types
import string_heap
import tracking

proc addNode(arena: var Arena, node: Node): NodeId =
  ## Internal: append a node and return its ID.
  result = NodeId(uint32(arena.nodes.len))
  arena.nodes.add(node)
  if arena.originStack.len > 0:
    arena.nodeOrigins.add(arena.originStack[^1])
  else:
    arena.nodeOrigins.add(InvalidOriginId)
  arena.recordAccess(akWrite, result)

proc newNull*(arena: var Arena): NodeId =
  addNode(arena, Node(kind: nkNull))

proc newBool*(arena: var Arena, val: bool): NodeId =
  addNode(arena, Node(kind: nkBool, boolVal: val))

proc newInt*(arena: var Arena, val: int64): NodeId =
  addNode(arena, Node(kind: nkInt, intVal: val))

proc newFloat*(arena: var Arena, val: float64): NodeId =
  addNode(arena, Node(kind: nkFloat, floatVal: val))

proc newStr*(arena: var Arena, val: string): NodeId =
  let (offset, length, cap) = arena.allocString(val)
  addNode(arena, Node(kind: nkString, strOffset: offset, strLen: length, strCap: cap))

proc kind*(arena: Arena, id: NodeId): NodeKind =
  arena.recordAccess(akRead, id)
  arena.nodes[uint32(id)].kind

proc getBool*(arena: Arena, id: NodeId): bool =
  arena.recordAccess(akRead, id)
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkBool, "Expected bool node, got " & $node.kind
  node.boolVal

proc getInt*(arena: Arena, id: NodeId): int64 =
  arena.recordAccess(akRead, id)
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkInt, "Expected int node, got " & $node.kind
  node.intVal

proc getFloat*(arena: Arena, id: NodeId): float64 =
  arena.recordAccess(akRead, id)
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkFloat, "Expected float node, got " & $node.kind
  node.floatVal

proc getStr*(arena: Arena, id: NodeId): string =
  arena.recordAccess(akRead, id)
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkString, "Expected string node, got " & $node.kind
  readString(arena, node.strOffset, node.strLen)

proc setStr*(arena: var Arena, id: NodeId, val: string) =
  ## Mutate an existing string node's value.
  arena.recordAccess(akWrite, id)
  assert arena.nodes[uint32(id)].kind == nkString
  if val.len == 0:
    updateString(arena, arena.nodes[uint32(id)], newSeq[byte](0))
  else:
    updateString(arena, arena.nodes[uint32(id)], val.toOpenArrayByte(0, val.high))

proc setBool*(arena: var Arena, id: NodeId, val: bool) =
  ## Mutate an existing bool node's value.
  arena.recordAccess(akWrite, id)
  assert arena.nodes[uint32(id)].kind == nkBool
  arena.nodes[uint32(id)].boolVal = val

proc setInt*(arena: var Arena, id: NodeId, val: int64) =
  ## Mutate an existing int node's value.
  arena.recordAccess(akWrite, id)
  assert arena.nodes[uint32(id)].kind == nkInt
  arena.nodes[uint32(id)].intVal = val

proc setFloat*(arena: var Arena, id: NodeId, val: float64) =
  ## Mutate an existing float node's value.
  arena.recordAccess(akWrite, id)
  assert arena.nodes[uint32(id)].kind == nkFloat
  arena.nodes[uint32(id)].floatVal = val

proc isNull*(arena: Arena, id: NodeId): bool =
  arena.recordAccess(akRead, id)
  arena.nodes[uint32(id)].kind == nkNull

proc nodeCount*(arena: Arena): int =
  arena.nodes.len
