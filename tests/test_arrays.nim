import std/unittest
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays

suite "Array - Creation":
  test "create empty array":
    var arena = initArena()
    let arr = arena.newArr()
    check arena.kind(arr) == nkArray
    check arena.arrLen(arr) == 0

  test "create array with custom capacity":
    var arena = initArena()
    let arr = arena.newArr(initialCap = 16)
    check arena.arrLen(arr) == 0
    # Should not fail when pushing up to 16 items without reallocation

  test "multiple arrays are independent":
    var arena = initArena()
    let a1 = arena.newArr()
    let a2 = arena.newArr()
    check a1 != a2
    check arena.arrLen(a1) == 0
    check arena.arrLen(a2) == 0

suite "Array - Push and Get":
  test "push single element":
    var arena = initArena()
    let arr = arena.newArr()
    let val = arena.newInt(42)
    arena.arrPush(arr, val)
    check arena.arrLen(arr) == 1
    check arena.arrGet(arr, 0) == val

  test "push multiple elements":
    var arena = initArena()
    let arr = arena.newArr()
    var ids: seq[NodeId]
    for i in 0 ..< 5:
      let id = arena.newInt(int64(i * 10))
      ids.add(id)
      arena.arrPush(arr, id)
    check arena.arrLen(arr) == 5
    for i in 0 ..< 5:
      check arena.arrGet(arr, i) == ids[i]
      check arena.getInt(arena.arrGet(arr, i)) == int64(i * 10)

  test "push mixed types":
    var arena = initArena()
    let arr = arena.newArr()
    let n = arena.newNull()
    let b = arena.newBool(true)
    let i = arena.newInt(7)
    let f = arena.newFloat(1.5)
    let s = arena.newStr("test")
    arena.arrPush(arr, n)
    arena.arrPush(arr, b)
    arena.arrPush(arr, i)
    arena.arrPush(arr, f)
    arena.arrPush(arr, s)
    check arena.arrLen(arr) == 5
    check arena.kind(arena.arrGet(arr, 0)) == nkNull
    check arena.getBool(arena.arrGet(arr, 1)) == true
    check arena.getInt(arena.arrGet(arr, 2)) == 7
    check arena.getFloat(arena.arrGet(arr, 3)) == 1.5
    check arena.getStr(arena.arrGet(arr, 4)) == "test"

suite "Array - Capacity Growth":
  test "push beyond initial capacity triggers reallocation":
    var arena = initArena()
    let arr = arena.newArr(initialCap = 2)
    # Push 2 items (fills capacity)
    arena.arrPush(arr, arena.newInt(1))
    arena.arrPush(arr, arena.newInt(2))
    check arena.arrLen(arr) == 2
    # Push 3rd triggers realloc
    arena.arrPush(arr, arena.newInt(3))
    check arena.arrLen(arr) == 3
    # All values still accessible
    check arena.getInt(arena.arrGet(arr, 0)) == 1
    check arena.getInt(arena.arrGet(arr, 1)) == 2
    check arena.getInt(arena.arrGet(arr, 2)) == 3

  test "push many elements (stress test)":
    var arena = initArena()
    let arr = arena.newArr(initialCap = 2)
    let count = 1000
    for i in 0 ..< count:
      arena.arrPush(arr, arena.newInt(int64(i)))
    check arena.arrLen(arr) == count
    # Spot check values
    check arena.getInt(arena.arrGet(arr, 0)) == 0
    check arena.getInt(arena.arrGet(arr, 500)) == 500
    check arena.getInt(arena.arrGet(arr, 999)) == 999

suite "Array - Iteration":
  test "iterate empty array":
    var arena = initArena()
    let arr = arena.newArr()
    var count = 0
    for child in arena.arrItems(arr):
      count += 1
    check count == 0

  test "iterate array with elements":
    var arena = initArena()
    let arr = arena.newArr()
    for i in 0 ..< 5:
      arena.arrPush(arr, arena.newInt(int64(i)))
    var collected: seq[int64]
    for child in arena.arrItems(arr):
      collected.add(arena.getInt(child))
    check collected == @[0'i64, 1, 2, 3, 4]

  test "iterate after reallocation":
    var arena = initArena()
    let arr = arena.newArr(initialCap = 2)
    for i in 0 ..< 10:
      arena.arrPush(arr, arena.newInt(int64(i)))
    var collected: seq[int64]
    for child in arena.arrItems(arr):
      collected.add(arena.getInt(child))
    check collected.len == 10
    for i in 0 ..< 10:
      check collected[i] == int64(i)

suite "Array - Independent Arrays":
  test "pushing to one array does not affect another":
    var arena = initArena()
    let a1 = arena.newArr()
    let a2 = arena.newArr()
    arena.arrPush(a1, arena.newInt(1))
    arena.arrPush(a1, arena.newInt(2))
    arena.arrPush(a2, arena.newStr("a"))
    check arena.arrLen(a1) == 2
    check arena.arrLen(a2) == 1
    check arena.getInt(arena.arrGet(a1, 0)) == 1
    check arena.getStr(arena.arrGet(a2, 0)) == "a"

  test "arrays can contain other arrays":
    var arena = initArena()
    let outer = arena.newArr()
    let inner1 = arena.newArr()
    let inner2 = arena.newArr()
    arena.arrPush(inner1, arena.newInt(1))
    arena.arrPush(inner1, arena.newInt(2))
    arena.arrPush(inner2, arena.newStr("hello"))
    arena.arrPush(outer, inner1)
    arena.arrPush(outer, inner2)
    check arena.arrLen(outer) == 2
    let gotInner1 = arena.arrGet(outer, 0)
    let gotInner2 = arena.arrGet(outer, 1)
    check arena.kind(gotInner1) == nkArray
    check arena.arrLen(gotInner1) == 2
    check arena.getInt(arena.arrGet(gotInner1, 0)) == 1
    check arena.kind(gotInner2) == nkArray
    check arena.getStr(arena.arrGet(gotInner2, 0)) == "hello"
