import std/[unittest, strutils, math]
import arena_context_store/types
import arena_context_store/nodes

suite "Node Storage - Null":
  test "create null node":
    var arena = initArena()
    let id = arena.newNull()
    check arena.kind(id) == nkNull
    check arena.isNull(id)

  test "multiple null nodes get distinct IDs":
    var arena = initArena()
    let id1 = arena.newNull()
    let id2 = arena.newNull()
    check id1 != id2
    check arena.kind(id1) == nkNull
    check arena.kind(id2) == nkNull

suite "Node Storage - Bool":
  test "create true node":
    var arena = initArena()
    let id = arena.newBool(true)
    check arena.kind(id) == nkBool
    check arena.getBool(id) == true

  test "create false node":
    var arena = initArena()
    let id = arena.newBool(false)
    check arena.kind(id) == nkBool
    check arena.getBool(id) == false

  test "multiple bools are independent":
    var arena = initArena()
    let t = arena.newBool(true)
    let f = arena.newBool(false)
    check arena.getBool(t) == true
    check arena.getBool(f) == false

suite "Node Storage - Int":
  test "create zero":
    var arena = initArena()
    let id = arena.newInt(0)
    check arena.kind(id) == nkInt
    check arena.getInt(id) == 0

  test "create positive int":
    var arena = initArena()
    let id = arena.newInt(42)
    check arena.getInt(id) == 42

  test "create negative int":
    var arena = initArena()
    let id = arena.newInt(-100)
    check arena.getInt(id) == -100

  test "create int64 max":
    var arena = initArena()
    let id = arena.newInt(int64.high)
    check arena.getInt(id) == int64.high

  test "create int64 min":
    var arena = initArena()
    let id = arena.newInt(int64.low)
    check arena.getInt(id) == int64.low

suite "Node Storage - Float":
  test "create zero float":
    var arena = initArena()
    let id = arena.newFloat(0.0)
    check arena.kind(id) == nkFloat
    check arena.getFloat(id) == 0.0

  test "create positive float":
    var arena = initArena()
    let id = arena.newFloat(3.14159)
    check abs(arena.getFloat(id) - 3.14159) < 1e-10

  test "create negative float":
    var arena = initArena()
    let id = arena.newFloat(-273.15)
    check abs(arena.getFloat(id) - (-273.15)) < 1e-10

  test "create very small float":
    var arena = initArena()
    let id = arena.newFloat(1e-300)
    check arena.getFloat(id) == 1e-300

  test "create very large float":
    var arena = initArena()
    let id = arena.newFloat(1e300)
    check arena.getFloat(id) == 1e300

  test "NaN stored correctly":
    var arena = initArena()
    let id = arena.newFloat(NaN)
    check classify(arena.getFloat(id)) == fcNan

  test "Infinity stored correctly":
    var arena = initArena()
    let id = arena.newFloat(Inf)
    check arena.getFloat(id) == Inf

suite "Node Storage - String":
  test "create empty string":
    var arena = initArena()
    let id = arena.newStr("")
    check arena.kind(id) == nkString
    check arena.getStr(id) == ""

  test "create simple string":
    var arena = initArena()
    let id = arena.newStr("hello")
    check arena.getStr(id) == "hello"

  test "create UTF-8 string":
    var arena = initArena()
    let id = arena.newStr("日本語テスト")
    check arena.getStr(id) == "日本語テスト"

  test "create long string":
    var arena = initArena()
    let longStr = 'x'.repeat(50000)
    let id = arena.newStr(longStr)
    check arena.getStr(id) == longStr

  test "mutate string in place":
    var arena = initArena()
    let id = arena.newStr("hello world")
    arena.setStr(id, "hi")
    check arena.getStr(id) == "hi"

  test "mutate string with relocation":
    var arena = initArena()
    let id = arena.newStr("hi")
    let longStr = 'y'.repeat(10000)
    arena.setStr(id, longStr)
    check arena.getStr(id) == longStr

  test "multiple strings stored independently":
    var arena = initArena()
    let ids = @[
      arena.newStr("alpha"),
      arena.newStr("beta"),
      arena.newStr("gamma"),
      arena.newStr("delta"),
    ]
    check arena.getStr(ids[0]) == "alpha"
    check arena.getStr(ids[1]) == "beta"
    check arena.getStr(ids[2]) == "gamma"
    check arena.getStr(ids[3]) == "delta"

suite "Node Storage - Mixed":
  test "node count tracks correctly":
    var arena = initArena()
    check arena.nodeCount() == 0
    discard arena.newNull()
    check arena.nodeCount() == 1
    discard arena.newBool(true)
    check arena.nodeCount() == 2
    discard arena.newInt(42)
    check arena.nodeCount() == 3

  test "interleaved type creation":
    var arena = initArena()
    let n = arena.newNull()
    let b = arena.newBool(true)
    let i = arena.newInt(99)
    let f = arena.newFloat(2.718)
    let s = arena.newStr("test")
    check arena.kind(n) == nkNull
    check arena.kind(b) == nkBool
    check arena.kind(i) == nkInt
    check arena.kind(f) == nkFloat
    check arena.kind(s) == nkString
    check arena.getBool(b) == true
    check arena.getInt(i) == 99
    check abs(arena.getFloat(f) - 2.718) < 1e-10
    check arena.getStr(s) == "test"

  test "NodeId stability":
    var arena = initArena()
    let id0 = arena.newStr("first")
    # Create many more nodes
    for i in 0 ..< 1000:
      discard arena.newInt(int64(i))
    # Original ID still valid
    check arena.getStr(id0) == "first"

  test "isNull only true for null nodes":
    var arena = initArena()
    let n = arena.newNull()
    let b = arena.newBool(false)
    let i = arena.newInt(0)
    let f = arena.newFloat(0.0)
    let s = arena.newStr("")
    check arena.isNull(n) == true
    check arena.isNull(b) == false
    check arena.isNull(i) == false
    check arena.isNull(f) == false
    check arena.isNull(s) == false

suite "Nodes - Scalar Mutation":
  test "setBool mutates in place":
    var arena = initArena()
    let n = arena.newBool(false)
    arena.setBool(n, true)
    check arena.getBool(n) == true

  test "setInt mutates in place":
    var arena = initArena()
    let n = arena.newInt(1)
    arena.setInt(n, 99)
    check arena.getInt(n) == 99

  test "setFloat mutates in place":
    var arena = initArena()
    let n = arena.newFloat(1.5)
    arena.setFloat(n, 2.25)
    check arena.getFloat(n) == 2.25

  test "scalar mutation does not add nodes":
    var arena = initArena()
    let n = arena.newInt(1)
    let count = arena.nodeCount
    arena.setInt(n, 2)
    check arena.nodeCount == count

suite "Nodes - Kind Safety":
  test "wrong-kind access raises ValueError":
    var arena = initArena()
    let n = arena.newInt(42)
    expect ValueError:
      discard arena.getStr(n)
    expect ValueError:
      discard arena.getBool(n)
    expect ValueError:
      arena.setStr(n, "nope")

  test "kind checks survive release builds":
    # expectKind is a real raise, not an assert: this suite is also run
    # with -d:release by run_tests semantics if ever added; the check
    # here documents the contract either way.
    var arena = initArena()
    let s = arena.newStr("text")
    expect ValueError:
      discard arena.getInt(s)
