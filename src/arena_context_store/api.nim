## High-level Nim-native API for the arena context store.
##
## Provides idiomatic Nim operators: [], len, kind, iterators.

import types
import nodes
import arrays
import objects

proc `[]`*(arena: Arena, id: NodeId, key: string): NodeId =
  ## Object key access.
  objGet(arena, id, key)

proc `[]`*(arena: Arena, id: NodeId, index: int): NodeId =
  ## Array index access.
  arrGet(arena, id, index)

proc len*(arena: Arena, id: NodeId): int =
  ## Return length for arrays and objects.
  let k = arena.kind(id)
  case k
  of nkArray: arrLen(arena, id)
  of nkObject: objLen(arena, id)
  else: raise newException(ValueError, "len not supported for " & $k)

proc set*(arena: var Arena, obj: NodeId, key: string, val: NodeId) =
  ## Set a key-value pair on an object.
  objSet(arena, obj, key, val)

proc add*(arena: var Arena, arr: NodeId, val: NodeId) =
  ## Push a value onto an array.
  arrPush(arena, arr, val)

iterator items*(arena: Arena, id: NodeId): NodeId =
  ## Iterate over array children.
  for child in arrItems(arena, id):
    yield child

iterator pairs*(arena: Arena, id: NodeId): (string, NodeId) =
  ## Iterate over object key-value pairs.
  for pair in objPairs(arena, id):
    yield pair
