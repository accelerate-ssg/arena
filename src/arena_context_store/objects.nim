## Object operations for the arena context store.
##
## Objects store key-value pairs in the entries buffer.
## Key lookup uses linear scan for <=16 entries (Phase 1).

import types
import string_heap

proc newObj*(arena: var Arena, initialCap: int = 8): NodeId =
  ## Create a new empty object node.
  let offset = uint32(arena.entries.len)
  let cap = uint32(initialCap)
  # Reserve capacity slots
  for i in 0 ..< initialCap:
    arena.entries.add(Entry(keyOffset: 0, keyLen: 0, valueNode: InvalidNodeId))
  result = NodeId(uint32(arena.nodes.len))
  arena.nodes.add(Node(kind: nkObject, entryOffset: offset, entryCount: 0,
                        entryCap: cap, trieOffset: 0))
  if arena.originStack.len > 0:
    arena.nodeOrigins.add(arena.originStack[^1])
  else:
    arena.nodeOrigins.add(InvalidOriginId)

proc objLen*(arena: Arena, id: NodeId): int =
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkObject, "Expected object node, got " & $node.kind
  int(node.entryCount)

proc keysMatch(arena: Arena, entry: Entry, key: string): bool =
  ## Check if an entry's key matches the given string.
  if entry.keyLen != uint32(key.len):
    return false
  for i in 0'u32 ..< entry.keyLen:
    if char(arena.strings[entry.keyOffset + i]) != key[i]:
      return false
  true

proc objGet*(arena: Arena, id: NodeId, key: string): NodeId =
  ## Look up a key in the object. Returns InvalidNodeId if not found.
  ## Uses linear scan (Phase 1).
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkObject, "Expected object node, got " & $node.kind
  for i in 0'u32 ..< node.entryCount:
    let entry = arena.entries[node.entryOffset + i]
    if keysMatch(arena, entry, key):
      return entry.valueNode
  InvalidNodeId

proc objSet*(arena: var Arena, id: NodeId, key: string, val: NodeId) =
  ## Set a key-value pair. Overwrites if key exists, appends if not.
  var node = arena.nodes[uint32(id)]
  assert node.kind == nkObject, "Expected object node, got " & $node.kind

  # Check if key already exists
  for i in 0'u32 ..< node.entryCount:
    let entry = arena.entries[node.entryOffset + i]
    if keysMatch(arena, entry, key):
      # Update existing entry
      arena.entries[node.entryOffset + i].valueNode = val
      return

  # Key not found — append
  if node.entryCount < node.entryCap:
    let (keyOff, keyLen, _) = arena.allocString(key)
    arena.entries[node.entryOffset + node.entryCount] = Entry(
      keyOffset: keyOff, keyLen: keyLen, valueNode: val
    )
    node.entryCount += 1
    arena.nodes[uint32(id)] = node
  else:
    # Must relocate — double capacity
    let newCap = max(node.entryCap * 2, 8'u32)
    let newOffset = uint32(arena.entries.len)
    # Copy existing entries
    for i in 0'u32 ..< node.entryCount:
      arena.entries.add(arena.entries[node.entryOffset + i])
    # Add the new entry
    let (keyOff, keyLen, _) = arena.allocString(key)
    arena.entries.add(Entry(keyOffset: keyOff, keyLen: keyLen, valueNode: val))
    # Fill remaining capacity
    for i in node.entryCount + 1 ..< newCap:
      arena.entries.add(Entry(keyOffset: 0, keyLen: 0, valueNode: InvalidNodeId))
    node.entryOffset = newOffset
    node.entryCount += 1
    node.entryCap = newCap
    arena.nodes[uint32(id)] = node

proc objHas*(arena: Arena, id: NodeId, key: string): bool =
  objGet(arena, id, key) != InvalidNodeId

proc objGetKey*(arena: Arena, id: NodeId, index: int): string =
  ## Get the key at a given index in the object's entries.
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkObject
  assert index >= 0 and uint32(index) < node.entryCount
  let entry = arena.entries[node.entryOffset + uint32(index)]
  readString(arena, entry.keyOffset, entry.keyLen)

proc objGetVal*(arena: Arena, id: NodeId, index: int): NodeId =
  ## Get the value NodeId at a given index in the object's entries.
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkObject
  assert index >= 0 and uint32(index) < node.entryCount
  arena.entries[node.entryOffset + uint32(index)].valueNode

iterator objPairs*(arena: Arena, id: NodeId): (string, NodeId) =
  ## Iterate over key-value pairs in the object.
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkObject
  for i in 0'u32 ..< node.entryCount:
    let entry = arena.entries[node.entryOffset + i]
    yield (readString(arena, entry.keyOffset, entry.keyLen), entry.valueNode)

iterator objKeys*(arena: Arena, id: NodeId): string =
  ## Iterate over keys in the object.
  let node = arena.nodes[uint32(id)]
  assert node.kind == nkObject
  for i in 0'u32 ..< node.entryCount:
    let entry = arena.entries[node.entryOffset + i]
    yield readString(arena, entry.keyOffset, entry.keyLen)
