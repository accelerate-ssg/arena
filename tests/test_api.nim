import std/unittest
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects
import arena_context_store/api
import arena_context_store/tracking

suite "API - Bracket Access":
  test "object bracket access by key":
    var arena = initArena()
    let obj = arena.newObj()
    let val = arena.newStr("value")
    arena.objSet(obj, "key", val)
    check arena[obj, "key"] == val
    check arena.getStr(arena[obj, "key"]) == "value"

  test "array bracket access by index":
    var arena = initArena()
    let arr = arena.newArr()
    let val = arena.newInt(42)
    arena.arrPush(arr, val)
    check arena[arr, 0] == val
    check arena.getInt(arena[arr, 0]) == 42

  test "chained bracket access":
    var arena = initArena()
    let obj = arena.newObj()
    let arr = arena.newArr()
    let inner = arena.newObj()
    arena.objSet(inner, "deep", arena.newStr("found"))
    arena.arrPush(arr, inner)
    arena.objSet(obj, "items", arr)
    # obj["items"][0]["deep"] == "found"
    check arena.getStr(arena[arena[arena[obj, "items"], 0], "deep"]) == "found"

suite "API - Len":
  test "len of array":
    var arena = initArena()
    let arr = arena.newArr()
    check arena.len(arr) == 0
    arena.arrPush(arr, arena.newNull())
    check arena.len(arr) == 1

  test "len of object":
    var arena = initArena()
    let obj = arena.newObj()
    check arena.len(obj) == 0
    arena.objSet(obj, "a", arena.newNull())
    check arena.len(obj) == 1

  test "len of scalar raises":
    var arena = initArena()
    let i = arena.newInt(5)
    expect ValueError:
      discard arena.len(i)

suite "API - Set and Add":
  test "set on object via API":
    var arena = initArena()
    let obj = arena.newObj()
    let val = arena.newStr("hello")
    arena.set(obj, "greeting", val)
    check arena.getStr(arena[obj, "greeting"]) == "hello"

  test "add to array via API":
    var arena = initArena()
    let arr = arena.newArr()
    arena.add(arr, arena.newInt(1))
    arena.add(arr, arena.newInt(2))
    check arena.len(arr) == 2
    check arena.getInt(arena[arr, 0]) == 1
    check arena.getInt(arena[arr, 1]) == 2

suite "API - Iteration":
  test "items iterator over array":
    var arena = initArena()
    let arr = arena.newArr()
    arena.add(arr, arena.newInt(10))
    arena.add(arr, arena.newInt(20))
    arena.add(arr, arena.newInt(30))
    var vals: seq[int64]
    for child in arena.items(arr):
      vals.add(arena.getInt(child))
    check vals == @[10'i64, 20, 30]

  test "pairs iterator over object":
    var arena = initArena()
    let obj = arena.newObj()
    arena.set(obj, "name", arena.newStr("test"))
    arena.set(obj, "version", arena.newInt(1))
    var keys: seq[string]
    for key, val in arena.pairs(obj):
      keys.add(key)
    check keys == @["name", "version"]

suite "API - Immutable Reads":
  proc buildArena(): Arena =
    var arena = initArena()
    let obj = arena.newObj()
    let arr = arena.newArr()
    arena.add(arr, arena.newInt(1))
    arena.set(obj, "title", arena.newStr("hello"))
    arena.set(obj, "items", arr)
    arena

  test "reads work through a let binding":
    let arena = buildArena()
    let root = NodeId(0)
    check arena.kind(root) == nkObject
    check arena.getStr(arena[root, "title"]) == "hello"
    check arena.len(arena[root, "items"]) == 1
    for key, val in arena.pairs(root):
      discard
    for child in arena.items(arena[root, "items"]):
      discard

  test "reads through a let binding still record accesses":
    let arena = buildArena()
    let root = NodeId(0)
    arena.pushConsumer(7)
    discard arena.getStr(arena[root, "title"])
    arena.popConsumer()
    check arena[root, "title"] in arena.readSet(7)

  test "nil tracking disables recording":
    var arena = buildArena()
    arena.tracking = nil
    let root = NodeId(0)
    check arena.currentConsumer() == InvalidConsumerId
    discard arena.getStr(arena[root, "title"])
    check arena.accesses.len == 0
