# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-25

First tagged release. The arena context store holds a static site generator's
build context in flat arena buffers, recording where every value came from and
which consumer read it, so an incremental rebuild can tell exactly what a change
made stale.

### Added

- A whole context tree — null, bool, int, float, string, array and object — held
  in a handful of flat, growable buffers instead of a graph of heap-allocated
  objects, with every value addressed by a `NodeId` that indexes the node table
  directly and is never reused, so ids held in dependency records or in a saved
  cache stay valid for the life of the arena.
- One byte heap shared by strings and object keys, stored null-terminated and
  allocated with roughly double the needed capacity, so an edit that still fits
  is written in place while an edit that overflows relocates the string and
  returns the old region to an offset-sorted free list that later allocations
  draw on, first fit, before growing the heap.
- Object entries and array child ids in shared growable buffers, with keys found
  by linear scan, capacity doubled and contents relocated on overflow,
  positional access to an object's keys and values, and iterators over array
  items, object keys and object pairs.
- In-place scalar mutation with `setBool`, `setInt`, `setFloat` and `setStr`,
  and single-slot rebinding with `arrSet`, so updating a value keeps the
  `NodeId` that other nodes, dependency records and caches already point at.
- A Nim-facing facade over the primitives — `[]` for object keys and array
  indices, `len`, `set`, `add`, and `items`/`pairs` iterators. Reads, the
  bracket operators and every iterator take an immutable `Arena` and only
  creation and mutation require `var`, so a template engine can render from a
  read-only view of the context.
- Lookup semantics template engines expect: a missing object key, and an
  out-of-range or negative `arrGetOrMiss` index, yield `InvalidNodeId` rather
  than raising. A wrong-kind access instead raises `ValueError` — a real raise
  rather than an assert, so kind confusion still fails loudly in a release build
  — as does `len` on a scalar, while an out-of-range `arrGet`, `arrSet` or
  positional entry access raises `IndexDefect`.
- Origin tagging: a node created while an origin is pushed records the source
  format, an interned source path and a byte offset, and a push/pop origin stack
  lets a loader attribute a whole file's tree without touching each node
  individually. Nodes created outside any pushed origin carry no origin.
- Overwrite chaining: rebinding an object key or array slot with a value from a
  different source chains the new origin to the one it replaced, so
  `originHistory` and `originDepth` report how a slot came to hold what it
  holds, while `findSource` and `nodesFrom` invert the tagging to list the nodes
  a source file currently owns — judged by current origin, so a node since
  overwritten from elsewhere no longer counts as that file's.
- An access log recording reads, iterations and writes against the consumer id
  on top of the consumer stack, and nothing at all while no consumer is pushed,
  with `readSet`, `iterateSet` and `writeSet` answering per consumer. It lives
  behind a reference so recording works through an immutable arena,
  `clearTracking` drops the records of one consumer or of all of them before a
  re-run, and setting `Arena.tracking` to nil switches recording off for a full
  build where nothing will consume it.
- Edge-precise accesses, distinguishing a read of a node's own value from the
  traversal of a single container edge, and recording length checks, key
  listings, presence checks and missed lookups as a dependency on the
  container's whole edge set. A consumer that read `site.title` therefore
  depends on the two edges it traversed and the string it landed on, not on
  everything bound in the objects it passed through.
- `invalidatedBy`, answering the incremental-rebuild question — given what one
  writer changed, which consumers now hold stale output — by indexing the small
  write set and scanning the log once, either over an explicit list of write
  records or over everything a named writer has written since its records were
  cleared. Because a consumer records every edge along the paths it traversed,
  rebinding a whole subtree at one edge reaches that subtree's deep readers with
  no transitive walk.
- `retireSubtree`, marking every node and container edge of a subtree being
  replaced wholesale as written, so a consumer that reached one of those nodes
  through a handle it held directly, rather than through an edge from an
  ancestor, is invalidated along with everyone else.
- A loader registry dispatching file content by extension suffix, matched
  case-insensitively, or by explicit format name, raising `ValueError` when
  nothing is registered for either. A JSON loader comes with it, installed by
  `registerJsonLoader`, tagging everything it builds with the file's origin;
  `fromJson` and `toJson` convert individual `JsonNode` values at a boundary.
- `saveArena` and `loadArena`, moving a whole arena — nodes, the string heap and
  its free list, entries, children, sources and origins — through a versioned
  binary stream written field by field, so the file does not depend on Nim's
  in-memory layout. It remains a machine-local cache in native byte order, and a
  wrong magic number or version is rejected with `ArenaCacheError` rather than
  migrated. The access log travels with the data, so a cold process that loads a
  previous build's arena can answer invalidation queries about it, while the
  loader registry and the origin and consumer stacks do not persist.
- A benchmark suite, run with `nimble bench`, measuring the arena against
  `JsonNode` on a site-shaped workload — building, deep and indexed reads,
  iteration, wide-object key scans from 8 to 512 keys, writes, tracking in each
  of its three states, the invalidation query at dev-server scale and the
  `toJson` boundary — and reporting how much memory each buffer occupies.
- A test suite of eleven files, run by `run_tests.sh`, covering the string heap,
  arrays, objects, the Nim-facing API, origins, access tracking, invalidation,
  the loader registry, serialization round trips and end-to-end scenarios.
