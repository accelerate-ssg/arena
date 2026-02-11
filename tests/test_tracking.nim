import std/unittest
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects
import arena_context_store/api
import arena_context_store/tracking

suite "Tracking - Consumer Management":
  test "no consumer active by default":
    var arena = initArena()
    check arena.currentConsumer() == InvalidConsumerId

  test "push consumer sets current":
    var arena = initArena()
    arena.pushConsumer(1)
    check arena.currentConsumer() == 1'u32

  test "pop consumer restores previous":
    var arena = initArena()
    arena.pushConsumer(1)
    arena.pushConsumer(2)
    check arena.currentConsumer() == 2'u32
    arena.popConsumer()
    check arena.currentConsumer() == 1'u32
    arena.popConsumer()
    check arena.currentConsumer() == InvalidConsumerId

suite "Tracking - Write Recording":
  test "newInt records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let n = arena.newInt(42)
    arena.popConsumer()
    let writes = arena.writeSet(1)
    check n in writes

  test "newStr records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let n = arena.newStr("hello")
    arena.popConsumer()
    check n in arena.writeSet(1)

  test "newBool records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let n = arena.newBool(true)
    arena.popConsumer()
    check n in arena.writeSet(1)

  test "newFloat records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let n = arena.newFloat(3.14)
    arena.popConsumer()
    check n in arena.writeSet(1)

  test "newNull records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let n = arena.newNull()
    arena.popConsumer()
    check n in arena.writeSet(1)

  test "newArr records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let a = arena.newArr()
    arena.popConsumer()
    check a in arena.writeSet(1)

  test "newObj records a write":
    var arena = initArena()
    arena.pushConsumer(1)
    let o = arena.newObj()
    arena.popConsumer()
    check o in arena.writeSet(1)

  test "objSet records write on the object":
    var arena = initArena()
    let obj = arena.newObj()
    let val = arena.newInt(1)
    arena.pushConsumer(1)
    arena.objSet(obj, "key", val)
    arena.popConsumer()
    check obj in arena.writeSet(1)

  test "arrPush records write on the array":
    var arena = initArena()
    let arr = arena.newArr()
    let val = arena.newInt(1)
    arena.pushConsumer(1)
    arena.arrPush(arr, val)
    arena.popConsumer()
    check arr in arena.writeSet(1)

  test "no writes recorded without consumer":
    var arena = initArena()
    discard arena.newInt(42)
    check arena.writeSet(1).len == 0

suite "Tracking - Read Recording":
  test "getInt records a read":
    var arena = initArena()
    let n = arena.newInt(42)
    arena.pushConsumer(1)
    discard arena.getInt(n)
    arena.popConsumer()
    check n in arena.readSet(1)

  test "getStr records a read":
    var arena = initArena()
    let n = arena.newStr("hello")
    arena.pushConsumer(1)
    discard arena.getStr(n)
    arena.popConsumer()
    check n in arena.readSet(1)

  test "getBool records a read":
    var arena = initArena()
    let n = arena.newBool(true)
    arena.pushConsumer(1)
    discard arena.getBool(n)
    arena.popConsumer()
    check n in arena.readSet(1)

  test "getFloat records a read":
    var arena = initArena()
    let n = arena.newFloat(3.14)
    arena.pushConsumer(1)
    discard arena.getFloat(n)
    arena.popConsumer()
    check n in arena.readSet(1)

  test "isNull records a read":
    var arena = initArena()
    let n = arena.newNull()
    arena.pushConsumer(1)
    discard arena.isNull(n)
    arena.popConsumer()
    check n in arena.readSet(1)

  test "kind records a read":
    var arena = initArena()
    let n = arena.newInt(42)
    arena.pushConsumer(1)
    discard arena.kind(n)
    arena.popConsumer()
    check n in arena.readSet(1)

  test "objGet records a read on the object":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "key", arena.newInt(1))
    arena.pushConsumer(1)
    discard arena.objGet(obj, "key")
    arena.popConsumer()
    check obj in arena.readSet(1)

  test "arrGet records a read on the array":
    var arena = initArena()
    let arr = arena.newArr()
    arena.arrPush(arr, arena.newInt(1))
    arena.pushConsumer(1)
    discard arena.arrGet(arr, 0)
    arena.popConsumer()
    check arr in arena.readSet(1)

  test "arrLen records a read":
    var arena = initArena()
    let arr = arena.newArr()
    arena.pushConsumer(1)
    discard arena.arrLen(arr)
    arena.popConsumer()
    check arr in arena.readSet(1)

  test "objLen records a read":
    var arena = initArena()
    let obj = arena.newObj()
    arena.pushConsumer(1)
    discard arena.objLen(obj)
    arena.popConsumer()
    check obj in arena.readSet(1)

  test "no reads recorded without consumer":
    var arena = initArena()
    let n = arena.newInt(42)
    discard arena.getInt(n)
    check arena.readSet(1).len == 0

suite "Tracking - API Level":
  test "bracket access on object records read":
    var arena = initArena()
    let obj = arena.newObj()
    arena.set(obj, "key", arena.newInt(1))
    arena.pushConsumer(1)
    discard arena[obj, "key"]
    arena.popConsumer()
    check obj in arena.readSet(1)

  test "bracket access on array records read":
    var arena = initArena()
    let arr = arena.newArr()
    arena.add(arr, arena.newInt(1))
    arena.pushConsumer(1)
    discard arena[arr, 0]
    arena.popConsumer()
    check arr in arena.readSet(1)

  test "API set records write":
    var arena = initArena()
    let obj = arena.newObj()
    arena.pushConsumer(1)
    arena.set(obj, "key", arena.newInt(1))
    arena.popConsumer()
    check obj in arena.writeSet(1)

  test "API add records write":
    var arena = initArena()
    let arr = arena.newArr()
    arena.pushConsumer(1)
    arena.add(arr, arena.newInt(1))
    arena.popConsumer()
    check arr in arena.writeSet(1)

  test "API len records read":
    var arena = initArena()
    let arr = arena.newArr()
    arena.pushConsumer(1)
    discard arena.len(arr)
    arena.popConsumer()
    check arr in arena.readSet(1)

suite "Tracking - Multiple Consumers":
  test "different consumers have independent sets":
    var arena = initArena()
    let n1 = arena.newInt(1)
    let n2 = arena.newInt(2)
    arena.pushConsumer(1)
    discard arena.getInt(n1)
    arena.popConsumer()
    arena.pushConsumer(2)
    discard arena.getInt(n2)
    arena.popConsumer()
    check n1 in arena.readSet(1)
    check n1 notin arena.readSet(2)
    check n2 in arena.readSet(2)
    check n2 notin arena.readSet(1)

  test "same node read by multiple consumers":
    var arena = initArena()
    let n = arena.newInt(42)
    arena.pushConsumer(1)
    discard arena.getInt(n)
    arena.popConsumer()
    arena.pushConsumer(2)
    discard arena.getInt(n)
    arena.popConsumer()
    check n in arena.readSet(1)
    check n in arena.readSet(2)

  test "writeSet and readSet are distinct":
    var arena = initArena()
    arena.pushConsumer(1)
    let n = arena.newInt(42)  # write
    discard arena.getInt(n)    # read
    arena.popConsumer()
    check n in arena.writeSet(1)
    check n in arena.readSet(1)

suite "Tracking - Clear and Query":
  test "clearTracking removes all records":
    var arena = initArena()
    arena.pushConsumer(1)
    discard arena.newInt(42)
    arena.popConsumer()
    check arena.writeSet(1).len > 0
    arena.clearTracking()
    check arena.writeSet(1).len == 0

  test "clearTracking for specific consumer":
    var arena = initArena()
    arena.pushConsumer(1)
    discard arena.newInt(1)
    arena.popConsumer()
    arena.pushConsumer(2)
    let n2 = arena.newInt(2)
    arena.popConsumer()
    arena.clearTracking(1)
    check arena.writeSet(1).len == 0
    check n2 in arena.writeSet(2)

  test "readSet returns unique NodeIds":
    var arena = initArena()
    let n = arena.newInt(42)
    arena.pushConsumer(1)
    discard arena.getInt(n)
    discard arena.getInt(n)
    discard arena.getInt(n)
    arena.popConsumer()
    let reads = arena.readSet(1)
    # Should contain n exactly once
    var count = 0
    for id in reads:
      if id == n: count += 1
    check count == 1
