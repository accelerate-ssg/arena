import std/[unittest, streams, json, sets]
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects
import arena_context_store/api
import arena_context_store/origins
import arena_context_store/tracking
import arena_context_store/invalidation
import arena_context_store/loader
import arena_context_store/loader_json
import arena_context_store/serialize

proc roundTrip(arena: Arena): Arena =
  var s = newStringStream()
  arena.saveArena(s)
  s.setPosition(0)
  loadArena(s)

suite "Serialize - Round trip":
  test "a populated arena survives intact":
    var arena = initArena()
    let oid = arena.registerOrigin(sfYaml, "content/site.yaml")
    arena.pushOrigin(oid)
    let root = arena.fromJson(%*{
      "site": {"name": "Test", "count": 3, "ratio": 1.5, "on": true, "none": nil},
      "posts": [{"slug": "a"}, {"slug": "b"}],
    })
    arena.popOrigin()

    let back = roundTrip(arena)
    check back.toJson(root) == arena.toJson(root)
    check back.nodeCount == arena.nodeCount
    check back.getNodeOrigin(root) == oid
    check back.getSourcePath(back.getOrigin(oid).sourceId) == "content/site.yaml"
    check back.nodesFrom("content/site.yaml").len == arena.nodesFrom("content/site.yaml").len

  test "the access log survives and answers invalidation":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "a", arena.newInt(1))
    arena.objSet(obj, "b", arena.newInt(2))

    arena.pushConsumer(10)
    discard arena.objGet(obj, "a")
    arena.popConsumer()
    arena.pushConsumer(11)
    discard arena.objGet(obj, "b")
    arena.popConsumer()

    var back = roundTrip(arena)
    # A writer in the RELOADED arena invalidates using the persisted reads.
    back.pushConsumer(99)
    back.objSet(obj, "a", back.newInt(3))
    back.popConsumer()
    let stale = back.invalidatedBy(99'u32)
    check 10'u32 in stale
    check 11'u32 notin stale

  test "the string heap free list survives":
    var arena = initArena()
    let s1 = arena.newStr("short")
    arena.setStr(s1, "long enough to overflow the doubled slack of a five-byte string")
    let freeRegions = arena.stringFreeList.len
    check freeRegions > 0
    let back = roundTrip(arena)
    check back.stringFreeList == arena.stringFreeList
    check back.getStr(s1) == arena.getStr(s1)

  test "a reloaded arena keeps working: writes, merges, queries":
    var arena = initArena()
    let root = arena.fromJson(%*{"posts": [{"title": "One"}]})
    var back = roundTrip(arena)
    # Continue building on the reloaded arena.
    let posts = back.objGet(root, "posts")
    back.arrPush(posts, back.fromJson(%*{"title": "Two"}))
    check back.toJson(root) == %*{"posts": [{"title": "One"}, {"title": "Two"}]}

  test "wrong magic and wrong version are rejected":
    var junk = newStringStream()
    junk.write(0xDEADBEEF'u32)
    junk.setPosition(0)
    expect ArenaCacheError:
      discard loadArena(junk)

    var stale = newStringStream()
    stale.write(0x41435458'u32)
    stale.write(9999'u32)
    stale.setPosition(0)
    expect ArenaCacheError:
      discard loadArena(stale)

  test "an empty arena round trips":
    var arena = initArena()
    let back = roundTrip(arena)
    check back.nodeCount == 0
