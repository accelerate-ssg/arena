import std/[unittest, sequtils, algorithm]
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects

suite "Object - Creation":
  test "create empty object":
    var arena = initArena()
    let obj = arena.newObj()
    check arena.kind(obj) == nkObject
    check arena.objLen(obj) == 0

  test "create object with custom capacity":
    var arena = initArena()
    let obj = arena.newObj(initialCap = 32)
    check arena.objLen(obj) == 0

  test "multiple objects are independent":
    var arena = initArena()
    let o1 = arena.newObj()
    let o2 = arena.newObj()
    check o1 != o2
    check arena.objLen(o1) == 0
    check arena.objLen(o2) == 0

suite "Object - Set and Get":
  test "set and get single key":
    var arena = initArena()
    let obj = arena.newObj()
    let val = arena.newStr("hello")
    arena.objSet(obj, "greeting", val)
    check arena.objLen(obj) == 1
    check arena.objGet(obj, "greeting") == val
    check arena.getStr(arena.objGet(obj, "greeting")) == "hello"

  test "set and get multiple keys":
    var arena = initArena()
    let obj = arena.newObj()
    let v1 = arena.newStr("Alice")
    let v2 = arena.newInt(30)
    let v3 = arena.newBool(true)
    arena.objSet(obj, "name", v1)
    arena.objSet(obj, "age", v2)
    arena.objSet(obj, "active", v3)
    check arena.objLen(obj) == 3
    check arena.getStr(arena.objGet(obj, "name")) == "Alice"
    check arena.getInt(arena.objGet(obj, "age")) == 30
    check arena.getBool(arena.objGet(obj, "active")) == true

  test "get nonexistent key returns InvalidNodeId":
    var arena = initArena()
    let obj = arena.newObj()
    check arena.objGet(obj, "missing") == InvalidNodeId

  test "overwrite existing key":
    var arena = initArena()
    let obj = arena.newObj()
    let v1 = arena.newStr("old")
    let v2 = arena.newStr("new")
    arena.objSet(obj, "key", v1)
    check arena.getStr(arena.objGet(obj, "key")) == "old"
    arena.objSet(obj, "key", v2)
    check arena.objLen(obj) == 1  # still 1 entry
    check arena.getStr(arena.objGet(obj, "key")) == "new"

  test "keys are case-sensitive":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "Name", arena.newStr("upper"))
    arena.objSet(obj, "name", arena.newStr("lower"))
    check arena.objLen(obj) == 2
    check arena.getStr(arena.objGet(obj, "Name")) == "upper"
    check arena.getStr(arena.objGet(obj, "name")) == "lower"

  test "empty string key":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "", arena.newInt(42))
    check arena.objLen(obj) == 1
    check arena.getInt(arena.objGet(obj, "")) == 42

  test "unicode keys":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "名前", arena.newStr("太郎"))
    check arena.getStr(arena.objGet(obj, "名前")) == "太郎"

suite "Object - Has":
  test "objHas returns true for existing key":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "key", arena.newNull())
    check arena.objHas(obj, "key") == true

  test "objHas returns false for missing key":
    var arena = initArena()
    let obj = arena.newObj()
    check arena.objHas(obj, "missing") == false

suite "Object - Capacity Growth":
  test "grow beyond initial capacity":
    var arena = initArena()
    let obj = arena.newObj(initialCap = 2)
    arena.objSet(obj, "a", arena.newInt(1))
    arena.objSet(obj, "b", arena.newInt(2))
    # This triggers reallocation
    arena.objSet(obj, "c", arena.newInt(3))
    check arena.objLen(obj) == 3
    check arena.getInt(arena.objGet(obj, "a")) == 1
    check arena.getInt(arena.objGet(obj, "b")) == 2
    check arena.getInt(arena.objGet(obj, "c")) == 3

  test "many keys (stress test - linear scan)":
    var arena = initArena()
    let obj = arena.newObj(initialCap = 2)
    let count = 100
    for i in 0 ..< count:
      arena.objSet(obj, "key" & $i, arena.newInt(int64(i)))
    check arena.objLen(obj) == count
    for i in 0 ..< count:
      check arena.getInt(arena.objGet(obj, "key" & $i)) == int64(i)

suite "Object - Index Access":
  test "get key by index":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "first", arena.newInt(1))
    arena.objSet(obj, "second", arena.newInt(2))
    check arena.objGetKey(obj, 0) == "first"
    check arena.objGetKey(obj, 1) == "second"

  test "get value by index":
    var arena = initArena()
    let obj = arena.newObj()
    let v1 = arena.newInt(10)
    let v2 = arena.newInt(20)
    arena.objSet(obj, "a", v1)
    arena.objSet(obj, "b", v2)
    check arena.objGetVal(obj, 0) == v1
    check arena.objGetVal(obj, 1) == v2

suite "Object - Iteration":
  test "iterate empty object":
    var arena = initArena()
    let obj = arena.newObj()
    var count = 0
    for key, val in arena.objPairs(obj):
      count += 1
    check count == 0

  test "iterate object pairs":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "x", arena.newInt(1))
    arena.objSet(obj, "y", arena.newInt(2))
    arena.objSet(obj, "z", arena.newInt(3))
    var keys: seq[string]
    var vals: seq[int64]
    for key, val in arena.objPairs(obj):
      keys.add(key)
      vals.add(arena.getInt(val))
    check keys == @["x", "y", "z"]
    check vals == @[1'i64, 2, 3]

  test "iterate object keys":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "alpha", arena.newNull())
    arena.objSet(obj, "beta", arena.newNull())
    var keys: seq[string]
    for key in arena.objKeys(obj):
      keys.add(key)
    check keys == @["alpha", "beta"]

suite "Object - Nested":
  test "object containing objects":
    var arena = initArena()
    let outer = arena.newObj()
    let inner = arena.newObj()
    arena.objSet(inner, "nested_key", arena.newStr("nested_val"))
    arena.objSet(outer, "child", inner)
    let got = arena.objGet(outer, "child")
    check arena.kind(got) == nkObject
    check arena.getStr(arena.objGet(got, "nested_key")) == "nested_val"

  test "object containing arrays":
    var arena = initArena()
    let obj = arena.newObj()
    let arr = newArr(arena)
    arrPush(arena, arr, arena.newInt(1))
    arrPush(arena, arr, arena.newInt(2))
    arena.objSet(obj, "items", arr)
    let gotArr = arena.objGet(obj, "items")
    check arena.kind(gotArr) == nkArray

  test "independent objects don't interfere after growth":
    var arena = initArena()
    let o1 = arena.newObj(initialCap = 2)
    let o2 = arena.newObj(initialCap = 2)
    # Fill both past capacity
    for i in 0 ..< 10:
      arena.objSet(o1, "a" & $i, arena.newInt(int64(i)))
      arena.objSet(o2, "b" & $i, arena.newInt(int64(i * 100)))
    # Verify both are intact
    for i in 0 ..< 10:
      check arena.getInt(arena.objGet(o1, "a" & $i)) == int64(i)
      check arena.getInt(arena.objGet(o2, "b" & $i)) == int64(i * 100)
