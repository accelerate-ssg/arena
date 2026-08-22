import std/unittest
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects
import arena_context_store/origins
import arena_context_store/api

suite "Origins - Source Registration":
  test "register a source path":
    var arena = initArena()
    let id = arena.registerSource("data/config.json")
    check id == 0'u32
    check arena.getSourcePath(id) == "data/config.json"

  test "register same path returns same id (dedup)":
    var arena = initArena()
    let id1 = arena.registerSource("data/config.json")
    let id2 = arena.registerSource("data/config.json")
    check id1 == id2

  test "register different paths get distinct ids":
    var arena = initArena()
    let id1 = arena.registerSource("a.json")
    let id2 = arena.registerSource("b.yaml")
    let id3 = arena.registerSource("c.csv")
    check id1 != id2
    check id2 != id3

  test "lookup source path by id":
    var arena = initArena()
    let id = arena.registerSource("/path/to/file.json")
    check arena.getSourcePath(id) == "/path/to/file.json"

suite "Origins - Origin Registration":
  test "register origin with format and sourceId":
    var arena = initArena()
    let srcId = arena.registerSource("test.json")
    let oid = arena.registerOrigin(sfJson, srcId)
    check oid != InvalidOriginId
    let origin = arena.getOrigin(oid)
    check origin.format == sfJson
    check origin.sourceId == srcId
    check origin.offset == 0
    check origin.previous == InvalidOriginId

  test "register origin with offset":
    var arena = initArena()
    let srcId = arena.registerSource("test.json")
    let oid = arena.registerOrigin(sfJson, srcId, offset = 42)
    let origin = arena.getOrigin(oid)
    check origin.offset == 42

  test "register origin with previous (chain)":
    var arena = initArena()
    let srcId1 = arena.registerSource("base.json")
    let srcId2 = arena.registerSource("override.yaml")
    let oid1 = arena.registerOrigin(sfJson, srcId1)
    let oid2 = arena.registerOrigin(sfYaml, srcId2, previous = oid1)
    let origin2 = arena.getOrigin(oid2)
    check origin2.format == sfYaml
    check origin2.previous == oid1

  test "register origin with path convenience":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "data/file.json")
    let origin = arena.getOrigin(oid)
    check origin.format == sfJson
    check arena.getSourcePath(origin.sourceId) == "data/file.json"

suite "Origins - Push/Pop Context":
  test "empty stack returns InvalidOriginId":
    var arena = initArena()
    check arena.currentOrigin() == InvalidOriginId

  test "push sets current origin":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    check arena.currentOrigin() == oid

  test "pop restores previous":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    arena.popOrigin()
    check arena.currentOrigin() == InvalidOriginId

  test "nested push/pop":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "a.json")
    let oid2 = arena.registerOrigin(sfYaml, "b.yaml")
    arena.pushOrigin(oid1)
    check arena.currentOrigin() == oid1
    arena.pushOrigin(oid2)
    check arena.currentOrigin() == oid2
    arena.popOrigin()
    check arena.currentOrigin() == oid1
    arena.popOrigin()
    check arena.currentOrigin() == InvalidOriginId

suite "Origins - Auto-Tagging":
  test "nodes created with pushed origin are tagged":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    let n1 = arena.newInt(42)
    let n2 = arena.newStr("hello")
    let n3 = arena.newBool(true)
    arena.popOrigin()
    check arena.getNodeOrigin(n1) == oid
    check arena.getNodeOrigin(n2) == oid
    check arena.getNodeOrigin(n3) == oid

  test "nodes created without pushed origin are untagged":
    var arena = initArena()
    let n = arena.newInt(42)
    check arena.getNodeOrigin(n) == InvalidOriginId

  test "pop stops tagging":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    let n1 = arena.newInt(1)
    arena.popOrigin()
    let n2 = arena.newInt(2)
    check arena.getNodeOrigin(n1) == oid
    check arena.getNodeOrigin(n2) == InvalidOriginId

  test "array nodes are tagged":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    let arr = arena.newArr()
    arena.popOrigin()
    check arena.getNodeOrigin(arr) == oid

  test "object nodes are tagged":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    let obj = arena.newObj()
    arena.popOrigin()
    check arena.getNodeOrigin(obj) == oid

  test "manual setNodeOrigin overrides":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "a.json")
    let oid2 = arena.registerOrigin(sfYaml, "b.yaml")
    arena.pushOrigin(oid1)
    let n = arena.newInt(42)
    arena.popOrigin()
    check arena.getNodeOrigin(n) == oid1
    arena.setNodeOrigin(n, oid2)
    check arena.getNodeOrigin(n) == oid2

suite "Origins - History Traversal":
  test "no origin returns empty history":
    var arena = initArena()
    let n = arena.newInt(42)
    check arena.originHistory(n).len == 0

  test "single origin returns one-element history":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    let n = arena.newInt(42)
    arena.popOrigin()
    let history = arena.originHistory(n)
    check history.len == 1
    check history[0] == oid

  test "chained origins return full history":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "base.json")
    let oid2 = arena.registerOrigin(sfYaml, "mid.yaml", previous = oid1)
    let oid3 = arena.registerOrigin(sfToml, "top.toml", previous = oid2)
    arena.pushOrigin(oid3)
    let n = arena.newInt(42)
    arena.popOrigin()
    let history = arena.originHistory(n)
    check history.len == 3
    check history[0] == oid3
    check history[1] == oid2
    check history[2] == oid1

  test "originDepth for untagged is 0":
    var arena = initArena()
    let n = arena.newInt(42)
    check arena.originDepth(n) == 0

  test "originDepth for single origin is 0 (never overwritten)":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "test.json")
    arena.pushOrigin(oid)
    let n = arena.newInt(42)
    arena.popOrigin()
    check arena.originDepth(n) == 0

  test "originDepth for chained origin reflects chain length":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "base.json")
    let oid2 = arena.registerOrigin(sfYaml, "over.yaml", previous = oid1)
    arena.pushOrigin(oid2)
    let n = arena.newInt(42)
    arena.popOrigin()
    check arena.originDepth(n) == 1  # overwritten once

suite "Origins - Overwrite Chaining via objSet":
  test "new key does not create chain":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "a.json")
    arena.pushOrigin(oid)
    let obj = arena.newObj()
    let val = arena.newStr("hello")
    arena.popOrigin()
    arena.objSet(obj, "key", val)
    check arena.getNodeOrigin(val) == oid
    check arena.originDepth(val) == 0  # no overwrite

  test "overwrite with different origin creates chain":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "base.json")
    let oid2 = arena.registerOrigin(sfYaml, "override.yaml")
    # Create object and initial value with origin 1
    arena.pushOrigin(oid1)
    let obj = arena.newObj()
    let v1 = arena.newStr("original")
    arena.popOrigin()
    arena.objSet(obj, "title", v1)
    # Create new value with origin 2 and overwrite
    arena.pushOrigin(oid2)
    let v2 = arena.newStr("overridden")
    arena.popOrigin()
    arena.objSet(obj, "title", v2)
    # v2's origin should now chain to oid1
    let history = arena.originHistory(v2)
    check history.len == 2
    let currentOrig = arena.getOrigin(history[0])
    check currentOrig.format == sfYaml
    check arena.getSourcePath(currentOrig.sourceId) == "override.yaml"
    let prevOrig = arena.getOrigin(history[1])
    check prevOrig.format == sfJson
    check arena.getSourcePath(prevOrig.sourceId) == "base.json"
    check arena.originDepth(v2) == 1

  test "no chain when neither has origin":
    var arena = initArena()
    let obj = arena.newObj()
    let v1 = arena.newInt(1)
    let v2 = arena.newInt(2)
    arena.objSet(obj, "x", v1)
    arena.objSet(obj, "x", v2)
    check arena.getNodeOrigin(v2) == InvalidOriginId

  test "no chain when same origin":
    var arena = initArena()
    let oid = arena.registerOrigin(sfJson, "same.json")
    arena.pushOrigin(oid)
    let obj = arena.newObj()
    let v1 = arena.newInt(1)
    let v2 = arena.newInt(2)
    arena.popOrigin()
    arena.objSet(obj, "x", v1)
    arena.objSet(obj, "x", v2)
    # Same origin — no chain created
    check arena.getNodeOrigin(v2) == oid
    check arena.originDepth(v2) == 0

  test "multiple overwrites build longer chain":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "first.json")
    let oid2 = arena.registerOrigin(sfYaml, "second.yaml")
    let oid3 = arena.registerOrigin(sfToml, "third.toml")
    let obj = arena.newObj()
    # First value
    arena.pushOrigin(oid1)
    let v1 = arena.newStr("v1")
    arena.popOrigin()
    arena.objSet(obj, "key", v1)
    # Second value overwrites first
    arena.pushOrigin(oid2)
    let v2 = arena.newStr("v2")
    arena.popOrigin()
    arena.objSet(obj, "key", v2)
    # Third value overwrites second
    arena.pushOrigin(oid3)
    let v3 = arena.newStr("v3")
    arena.popOrigin()
    arena.objSet(obj, "key", v3)
    # v3's history should chain through all three
    let history = arena.originHistory(v3)
    check history.len == 3
    check arena.getOrigin(history[0]).format == sfToml
    check arena.getOrigin(history[1]).format == sfYaml
    check arena.getOrigin(history[2]).format == sfJson
    check arena.originDepth(v3) == 2

  test "overwrite chaining works through API set":
    var arena = initArena()
    let oid1 = arena.registerOrigin(sfJson, "a.json")
    let oid2 = arena.registerOrigin(sfYaml, "b.yaml")
    arena.pushOrigin(oid1)
    let obj = arena.newObj()
    let v1 = arena.newStr("old")
    arena.popOrigin()
    arena.set(obj, "key", v1)
    arena.pushOrigin(oid2)
    let v2 = arena.newStr("new")
    arena.popOrigin()
    arena.set(obj, "key", v2)
    check arena.originDepth(v2) == 1

suite "Origins - Source Attribution":
  test "findSource returns the interned id without registering":
    var arena = initArena()
    let id = arena.registerSource("data/site.json")
    check arena.findSource("data/site.json") == id
    check arena.findSource("data/unknown.json") == InvalidSourceId
    check arena.sources.len == 1

  test "nodesFrom returns the nodes a source produced":
    var arena = initArena()
    let oidA = arena.registerOrigin(sfJson, "a.json")
    let oidB = arena.registerOrigin(sfJson, "b.json")
    arena.pushOrigin(oidA)
    let a1 = arena.newStr("from a")
    let a2 = arena.newInt(1)
    arena.popOrigin()
    arena.pushOrigin(oidB)
    let b1 = arena.newStr("from b")
    arena.popOrigin()
    let untagged = arena.newInt(2)

    let fromA = arena.nodesFrom("a.json")
    check a1 in fromA
    check a2 in fromA
    check b1 notin fromA
    check untagged notin fromA

  test "nodesFrom follows the current origin after overwrite chaining":
    var arena = initArena()
    let oidA = arena.registerOrigin(sfJson, "a.json")
    let oidB = arena.registerOrigin(sfYaml, "b.yaml")
    arena.pushOrigin(oidA)
    let obj = arena.newObj()
    let v1 = arena.newStr("old")
    arena.popOrigin()
    arena.objSet(obj, "key", v1)
    arena.pushOrigin(oidB)
    let v2 = arena.newStr("new")
    arena.popOrigin()
    arena.objSet(obj, "key", v2)
    # v2's chained origin still points at b.yaml as the current source.
    check v2 in arena.nodesFrom("b.yaml")
    check v2 notin arena.nodesFrom("a.json")
    # v1 keeps its original attribution.
    check v1 in arena.nodesFrom("a.json")

  test "nodesFrom on an unregistered path is empty":
    var arena = initArena()
    discard arena.newStr("x")
    check arena.nodesFrom("never/registered.json").len == 0
