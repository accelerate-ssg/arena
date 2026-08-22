## JSON loader for the arena context store.
##
## Parses JSON data and builds an arena tree. Uses pushOrigin/popOrigin
## to auto-tag all created nodes with the source file origin.

import std/json
import types
import nodes
import arrays
import objects
import origins
import loader

proc fromJson*(arena: var Arena, j: JsonNode): NodeId =
  ## Recursively convert a JsonNode tree into arena nodes. Nodes are
  ## tagged with the current origin, if one is pushed.
  case j.kind
  of JNull:
    arena.newNull()
  of JBool:
    arena.newBool(j.getBool())
  of JInt:
    arena.newInt(j.getInt())
  of JFloat:
    arena.newFloat(j.getFloat())
  of JString:
    arena.newStr(j.getStr())
  of JArray:
    let arr = arena.newArr(initialCap = j.len)
    for child in j:
      arrPush(arena, arr, arena.fromJson(child))
    arr
  of JObject:
    let obj = arena.newObj(initialCap = j.len)
    for key, val in j:
      objSet(arena, obj, key, arena.fromJson(val))
    obj

proc jsonLoader*(arena: var Arena, data: string, path: string): NodeId =
  ## Parse JSON string and load into arena with origin tracking.
  let oid = arena.registerOrigin(sfJson, path)
  arena.pushOrigin(oid)
  let parsed = parseJson(data)
  result = arena.fromJson(parsed)
  arena.popOrigin()

proc registerJsonLoader*(arena: var Arena) =
  ## Register the JSON loader for .json files.
  arena.registerLoader("json", @[".json"], jsonLoader)

proc toJson*(arena: Arena, id: NodeId): JsonNode =
  ## Convert an arena node tree back to a JsonNode.
  case arena.kind(id)
  of nkNull:
    result = newJNull()
  of nkBool:
    result = newJBool(arena.getBool(id))
  of nkInt:
    result = newJInt(arena.getInt(id))
  of nkFloat:
    result = newJFloat(arena.getFloat(id))
  of nkString:
    result = newJString(arena.getStr(id))
  of nkArray:
    result = newJArray()
    for child in arrItems(arena, id):
      result.add(arena.toJson(child))
  of nkObject:
    result = newJObject()
    for key, val in objPairs(arena, id):
      result[key] = arena.toJson(val)
