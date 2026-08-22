import std/[unittest, sets, json, tables]
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects
import arena_context_store/api
import arena_context_store/tracking
import arena_context_store/invalidation
import arena_context_store/loader
import arena_context_store/loader_json

const
  Loader = 1'u32
  PageA = 10'u32
  PageB = 11'u32
  PageC = 12'u32

suite "Invalidation - Scalar Writes":
  test "scalar write invalidates its value readers":
    var arena = initArena()
    let n = arena.newInt(1)
    arena.pushConsumer(PageA)
    discard arena.getInt(n)
    arena.popConsumer()

    arena.pushConsumer(Loader)
    arena.setStr(arena.newStr("x"), "y")  # unrelated write
    arena.popConsumer()
    check PageA notin arena.invalidatedBy(Loader)

    arena.clearTracking(Loader)
    arena.pushConsumer(Loader)
    arena.setInt(n, 2)
    arena.popConsumer()
    check PageA in arena.invalidatedBy(Loader)

  test "setStr invalidates string readers":
    var arena = initArena()
    let s = arena.newStr("before")
    arena.pushConsumer(PageA)
    discard arena.getStr(s)
    arena.popConsumer()

    arena.pushConsumer(Loader)
    arena.setStr(s, "after")
    arena.popConsumer()
    check PageA in arena.invalidatedBy(Loader)

suite "Invalidation - Edge Writes":
  test "rebinding an edge invalidates only that edge's readers":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "a", arena.newInt(1))
    arena.objSet(obj, "b", arena.newInt(2))

    arena.pushConsumer(PageA)
    discard arena.objGet(obj, "a")
    arena.popConsumer()
    arena.pushConsumer(PageB)
    discard arena.objGet(obj, "b")
    arena.popConsumer()

    arena.pushConsumer(Loader)
    arena.objSet(obj, "b", arena.newInt(3))
    arena.popConsumer()

    let stale = arena.invalidatedBy(Loader)
    check PageB in stale
    check PageA notin stale

  test "rebinding an edge invalidates iterators of the container":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "a", arena.newInt(1))

    arena.pushConsumer(PageA)
    for k, v in objPairs(arena, obj): discard
    arena.popConsumer()

    arena.pushConsumer(Loader)
    arena.objSet(obj, "a", arena.newInt(2))
    arena.popConsumer()
    check PageA in arena.invalidatedBy(Loader)

  test "appending a key invalidates iterators and missed lookups":
    var arena = initArena()
    let obj = arena.newObj()
    arena.objSet(obj, "present", arena.newInt(1))

    arena.pushConsumer(PageA)
    check arena.objGet(obj, "absent") == InvalidNodeId  # miss
    arena.popConsumer()
    arena.pushConsumer(PageB)
    discard arena.objLen(obj)
    arena.popConsumer()
    arena.pushConsumer(PageC)
    discard arena.objGet(obj, "present")  # untouched edge
    arena.popConsumer()

    arena.pushConsumer(Loader)
    arena.objSet(obj, "absent", arena.newInt(2))
    arena.popConsumer()

    let stale = arena.invalidatedBy(Loader)
    check PageA in stale
    check PageB in stale
    check PageC notin stale

  test "array push invalidates length checks but not element readers":
    var arena = initArena()
    let arr = arena.newArr()
    arena.arrPush(arr, arena.newInt(1))

    arena.pushConsumer(PageA)
    discard arena.arrGet(arr, 0)
    arena.popConsumer()
    arena.pushConsumer(PageB)
    discard arena.arrLen(arr)
    arena.popConsumer()

    arena.pushConsumer(Loader)
    arena.arrPush(arr, arena.newInt(2))
    arena.popConsumer()

    let stale = arena.invalidatedBy(Loader)
    check PageB in stale
    check PageA notin stale

suite "Invalidation - Path Transitivity":
  test "rebinding a subtree invalidates deep readers via the traversed edge":
    var arena = initArena()
    let root = arena.newObj()
    let site = arena.newObj()
    arena.objSet(site, "title", arena.newStr("hello"))
    arena.objSet(root, "site", site)
    arena.objSet(root, "other", arena.newInt(1))

    # PageA reads root -> site -> title, recording every edge on the path.
    arena.pushConsumer(PageA)
    discard arena.getStr(arena[arena[root, "site"], "title"])
    arena.popConsumer()
    # PageB reads only root.other.
    arena.pushConsumer(PageB)
    discard arena.getInt(arena[root, "other"])
    arena.popConsumer()

    # A reload rebinds root.site to a freshly built subtree.
    arena.pushConsumer(Loader)
    let newSite = arena.newObj()
    arena.objSet(newSite, "title", arena.newStr("changed"))
    arena.objSet(root, "site", newSite)
    arena.popConsumer()

    let stale = arena.invalidatedBy(Loader)
    check PageA in stale
    check PageB notin stale

  test "writer is excluded from its own invalidation set":
    var arena = initArena()
    let obj = arena.newObj()
    arena.pushConsumer(Loader)
    arena.objSet(obj, "key", arena.newInt(1))
    discard arena.objGet(obj, "key")
    arena.objSet(obj, "key", arena.newInt(2))
    arena.popConsumer()
    check Loader notin arena.invalidatedBy(Loader)

  test "record-list overload does not exclude anyone":
    var arena = initArena()
    let n = arena.newStr("v")
    arena.pushConsumer(PageA)
    discard arena.getStr(n)
    arena.popConsumer()
    let writes = @[AccessRecord(kind: akWrite, nodeId: n, edge: NoEdge, consumerId: PageA)]
    check PageA in arena.invalidatedBy(writes)

suite "Invalidation - Dev Server Flow":
  test "reloading one file invalidates only its readers":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.newObj()

    # Initial load of two content files under the loader consumer.
    arena.pushConsumer(Loader)
    arena.objSet(root, "site", arena.load("site.json", """{"title": "My Site"}"""))
    arena.objSet(root, "blog", arena.load("blog.json", """{"posts": ["first", "second"]}"""))
    arena.popConsumer()

    # PageA renders from site.json data, PageB from blog.json data.
    arena.pushConsumer(PageA)
    discard arena.getStr(arena[arena[root, "site"], "title"])
    arena.popConsumer()
    arena.pushConsumer(PageB)
    let posts = arena[arena[root, "blog"], "posts"]
    for post in items(arena, posts):
      discard arena.getStr(post)
    arena.popConsumer()

    # site.json changes on disk: clear the loader's records and reload.
    arena.clearTracking(Loader)
    arena.pushConsumer(Loader)
    arena.objSet(root, "site", arena.load("site.json", """{"title": "Renamed"}"""))
    arena.popConsumer()

    let stale = arena.invalidatedBy(Loader)
    check PageA in stale
    check PageB notin stale

    # Re-render the stale page against the new data.
    arena.clearTracking(PageA)
    arena.pushConsumer(PageA)
    check arena.getStr(arena[arena[root, "site"], "title"]) == "Renamed"
    arena.popConsumer()
