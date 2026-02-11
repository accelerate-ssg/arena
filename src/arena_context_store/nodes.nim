## Node creation and scalar access for the arena context store.

import types
import string_heap

proc addNode(arena: var Arena, node: Node): NodeId =
  ## Internal: append a node and return its ID.
  result = NodeId(uint32(arena.nodes.len))
  arena.nodes.add(node)

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
  arena.nodes[uint32(id)].kind

proc getBool*(arena: Arena, id: NodeId): bool =
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkBool, "Expected bool node, got " & $node.kind
  node.boolVal

proc getInt*(arena: Arena, id: NodeId): int64 =
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkInt, "Expected int node, got " & $node.kind
  node.intVal

proc getFloat*(arena: Arena, id: NodeId): float64 =
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkFloat, "Expected float node, got " & $node.kind
  node.floatVal

proc getStr*(arena: Arena, id: NodeId): string =
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkString, "Expected string node, got " & $node.kind
  readString(arena, node.strOffset, node.strLen)

proc setStr*(arena: var Arena, id: NodeId, val: string) =
  ## Mutate an existing string node's value.
  assert arena.nodes[uint32(id)].kind == nkString
  if val.len == 0:
    updateString(arena, arena.nodes[uint32(id)], newSeq[byte](0))
  else:
    updateString(arena, arena.nodes[uint32(id)], val.toOpenArrayByte(0, val.high))

proc isNull*(arena: Arena, id: NodeId): bool =
  arena.nodes[uint32(id)].kind == nkNull

proc nodeCount*(arena: Arena): int =
  arena.nodes.len
