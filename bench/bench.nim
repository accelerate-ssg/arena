## Performance benchmarks for the arena context store.
##
## Run with:  nimble bench
## (or:  nim c -r -d:release --mm:orc --hints:off bench/bench.nim)
##
## Most benchmarks come in arena/JsonNode pairs, since JsonNode is what
## the arena replaces in acc. Workloads are shaped like a real site
## context: a config object plus a posts collection with typical
## frontmatter fields. Each benchmark runs its body several times and
## reports the best trial, so numbers are close to the machine's actual
## capability rather than an average over scheduler noise.

import std/[monotimes, times, json, strutils, strformat, random, tables, sets]
import arena_context_store

# ─── Harness ─────────────────────────────────────────────────────────

var sink: int64  ## accumulated by benchmarks so work cannot be optimized away

type Row = tuple[name: string, nsPerOp: float]
var rows: seq[Row]
var section = ""

proc heading(title: string) =
  section = title

template bench(name: string, ops: int, body: untyped) =
  block:
    body  # warmup
    var best = int64.high
    for trial in 0 ..< 5:
      let start = getMonoTime()
      body
      let elapsed = (getMonoTime() - start).inNanoseconds
      if elapsed < best: best = elapsed
    if section.len > 0:
      rows.add((("── " & section), NaN))
      section = ""
    rows.add((name, best.float / ops.float))

proc fmt(ns: float): string =
  if ns != ns: ""  # NaN → section row
  elif ns >= 1_000_000: &"{ns / 1_000_000:>10.2f} ms"
  elif ns >= 1_000: &"{ns / 1_000:>10.2f} µs"
  else: &"{ns:>10.1f} ns"

proc report() =
  echo ""
  echo &"""{"benchmark":<58}{"per op":>13}"""
  echo repeat("─", 71)
  for (name, ns) in rows:
    if ns != ns:
      echo name
    else:
      echo &"  {name:<56}{fmt(ns):>13}"
  echo ""
  echo "(sink: ", sink, ")"

# ─── Workload data ───────────────────────────────────────────────────

proc siteJson(posts: int): JsonNode =
  ## A context shaped like a real site: config plus a posts collection.
  var rng = initRand(42)
  result = %*{
    "site": {
      "name": "Benchmark Site",
      "domains": ["bench.example", "www.bench.example"],
      "deep": {"a": {"b": {"c": {"d": "bottom"}}}},
    }
  }
  var list = newJArray()
  for i in 0 ..< posts:
    list.add(%*{
      "slug": "post-" & $i,
      "title": "Post number " & $i,
      "date": "2026-08-" & $(1 + rng.rand(27)),
      "order": i,
      "published": rng.rand(1.0) > 0.1,
      "tags": ["alpha", "tag-" & $rng.rand(9)],
      "body": repeat("Lorem ipsum dolor sit amet. ", 8),
    })
  result["posts"] = list

let doc1k = siteJson(1000)

proc arenaFrom(j: JsonNode): (Arena, NodeId) =
  var arena = initArena()
  let root = arena.fromJson(j)
  (arena, root)

# ═══ Build ═══════════════════════════════════════════════════════════

heading "Build (1000-post site)"

bench "arena fromJson", 10:
  for i in 0 ..< 10:
    var arena = initArena()
    sink += int64(arena.fromJson(doc1k))

bench "JsonNode deep copy (baseline)", 10:
  for i in 0 ..< 10:
    let copied {.used.} = doc1k.copy()
    sink += copied["posts"].len

bench "arena direct build, 10k int nodes", 10_000:
  var arena = initArena()
  let arr = arena.newArr(initialCap = 16)
  for i in 0 ..< 10_000:
    arena.arrPush(arr, arena.newInt(i))
  sink += arena.nodeCount

bench "JsonNode direct build, 10k ints (baseline)", 10_000:
  var arr = newJArray()
  for i in 0 ..< 10_000:
    arr.add(newJInt(i))
  sink += arr.len

# ═══ Reads ═══════════════════════════════════════════════════════════

heading "Reads"

block:
  var (arena, root) = arenaFrom(doc1k)
  arena.tracking = nil

  bench "arena deep get, 5 levels (site.deep.a.b.c.d)", 1_000_000:
    for i in 0 ..< 1_000_000:
      var n = arena.objGet(root, "site")
      n = arena.objGet(n, "deep")
      n = arena.objGet(n, "a")
      n = arena.objGet(n, "b")
      n = arena.objGet(n, "c")
      sink += int64(arena.objGet(n, "d"))

  let posts = arena.objGet(root, "posts")
  var rng = initRand(7)

  bench "arena arrGet, random index in 1000", 1_000_000:
    for i in 0 ..< 1_000_000:
      sink += int64(arena.arrGet(posts, rng.rand(999)))

  let post0 = arena.arrGet(posts, 0)

  bench "arena objGet, 7-key object, last key", 1_000_000:
    for i in 0 ..< 1_000_000:
      sink += int64(arena.objGet(post0, "body"))

  bench "arena getStr (body, ~220 bytes)", 100_000:
    let body = arena.objGet(post0, "body")
    for i in 0 ..< 100_000:
      sink += arena.getStr(body).len

  bench "arena full iteration, all posts, all fields", 1000:
    for post in arrItems(arena, posts):
      for key, val in objPairs(arena, post):
        sink += int64(val)

block:
  let j = doc1k

  bench "JsonNode deep get, 5 levels (baseline)", 1_000_000:
    for i in 0 ..< 1_000_000:
      sink += j{"site"}{"deep"}{"a"}{"b"}{"c"}{"d"}.getStr.len

  let posts = j["posts"]
  var rng = initRand(7)

  bench "JsonNode index, random in 1000 (baseline)", 1_000_000:
    for i in 0 ..< 1_000_000:
      sink += posts[rng.rand(999)]["order"].getInt

  let post0 = posts[0]

  bench "JsonNode key get, 7-key object (baseline)", 1_000_000:
    for i in 0 ..< 1_000_000:
      sink += post0["body"].getStr.len

  bench "JsonNode full iteration (baseline)", 1000:
    for post in posts:
      for key, val in post:
        sink += ord(val.kind)

# ═══ Wide objects (linear scan behavior) ═════════════════════════════

heading "Wide objects — linear key scan (trie threshold data)"

for width in [8, 32, 128, 512]:
  block:
    var arena = initArena()
    arena.tracking = nil
    let obj = arena.newObj(initialCap = width)
    for i in 0 ..< width:
      arena.objSet(obj, "key_number_" & $i, arena.newInt(i))
    let lastKey = "key_number_" & $(width - 1)

    bench &"arena objGet, {width:>3}-key object, last key", 200_000:
      for i in 0 ..< 200_000:
        sink += int64(arena.objGet(obj, lastKey))

# ═══ Writes ══════════════════════════════════════════════════════════

heading "Writes"

block:
  var arena = initArena()
  let obj = arena.newObj()
  arena.objSet(obj, "value", arena.newInt(0))
  let slot = arena.newInt(1)

  bench "objSet, rebind existing key", 1_000_000:
    for i in 0 ..< 1_000_000:
      arena.objSet(obj, "value", slot)

  bench "objSet, append (fresh 16-key objects)", 160_000:
    for o in 0 ..< 10_000:
      let fresh = arena.newObj(initialCap = 4)  # forces growth at 4
      for k in 0 ..< 16:
        arena.objSet(fresh, "k" & $k, slot)

  bench "arrPush, growing array to 100k", 100_000:
    let arr = arena.newArr()
    for i in 0 ..< 100_000:
      arena.arrPush(arr, slot)

  let s = arena.newStr("0123456789abcdef")  # cap leaves in-place room

  bench "setStr, fits in place", 1_000_000:
    for i in 0 ..< 1_000_000:
      arena.setStr(s, "0123456789ABCDEF")

  bench "setStr, forces relocation each time", 100_000:
    var payload = "x"
    for i in 0 ..< 100_000:
      payload.add('y')
      if payload.len > 64: payload.setLen(1)
      arena.setStr(s, payload)

# ═══ Tracking overhead ═══════════════════════════════════════════════

heading "Tracking overhead (same deep-get workload)"

block:
  var (arena, root) = arenaFrom(doc1k)

  template deepGets() =
    for i in 0 ..< 1_000_000:
      var n = arena.objGet(root, "site")
      n = arena.objGet(n, "deep")
      n = arena.objGet(n, "a")
      n = arena.objGet(n, "b")
      n = arena.objGet(n, "c")
      sink += int64(arena.objGet(n, "d"))

  arena.tracking = nil
  bench "tracking disabled (nil)", 6_000_000:
    deepGets()

  arena.tracking = TrackingLog()
  bench "tracking on, no consumer pushed", 6_000_000:
    deepGets()

  bench "consumer pushed, every access recorded", 6_000_000:
    arena.tracking.accesses.setLen(0)
    arena.pushConsumer(1)
    deepGets()
    arena.popConsumer()

# ═══ Invalidation query ══════════════════════════════════════════════

heading "Invalidation (500 consumers × 200 reads, 100k-record log)"

block:
  var (arena, root) = arenaFrom(doc1k)
  let posts = arena.objGet(root, "posts")

  # 500 page-like consumers each read one post's fields.
  var rng = initRand(11)
  for c in 0'u32 ..< 500:
    arena.pushConsumer(c)
    let post = arena.arrGet(posts, int(c) mod 1000)
    for i in 0 ..< 40:
      for key in ["slug", "title", "date", "order", "published"]:
        discard arena.objGet(post, key)
    arena.popConsumer()

  # A loader rewrites one post's title.
  arena.pushConsumer(9999)
  let victim = arena.arrGet(posts, 3)
  arena.objSet(victim, "title", arena.newStr("changed"))
  arena.popConsumer()

  bench "invalidatedBy over the full log", 10:
    for i in 0 ..< 10:
      sink += arena.invalidatedBy(9999'u32).len

# ═══ Facade boundary ═════════════════════════════════════════════════

heading "Facade boundary (1000-post site)"

block:
  var (arena, root) = arenaFrom(doc1k)
  arena.tracking = nil

  bench "toJson, whole tree", 10:
    for i in 0 ..< 10:
      sink += arena.toJson(root)["posts"].len

  bench "fromJson + toJson round trip", 10:
    for i in 0 ..< 10:
      var fresh = initArena()
      let r = fresh.fromJson(doc1k)
      sink += fresh.toJson(r)["posts"].len

# ═══ Memory footprint ════════════════════════════════════════════════

block:
  var (arena, root) = arenaFrom(doc1k)
  let
    nodesB = arena.nodes.len * sizeof(Node)
    stringsB = arena.strings.len
    entriesB = arena.entries.len * sizeof(Entry)
    childrenB = arena.children.len * sizeof(NodeId)
    originsB = arena.origins.len * sizeof(Origin) +
               arena.nodeOrigins.len * sizeof(OriginId)
    total = nodesB + stringsB + entriesB + childrenB + originsB
  echo ""
  echo "Memory, 1000-post site (", arena.nodeCount, " nodes):"
  echo &"  nodes     {nodesB div 1024:>6} KiB   ({sizeof(Node)} B/node)"
  echo &"  strings   {stringsB div 1024:>6} KiB"
  echo &"  entries   {entriesB div 1024:>6} KiB"
  echo &"  children  {childrenB div 1024:>6} KiB"
  echo &"  origins   {originsB div 1024:>6} KiB"
  echo &"  total     {total div 1024:>6} KiB"
  sink += int64(root)

report()
