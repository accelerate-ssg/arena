# Arena Context Store

## Purpose

A static site generator's core job is shuttling structured data — page metadata, site configuration, content — between different processing stages: content ingestion, script-based transformations, and template rendering. These stages may be implemented in different languages (Nim core, JS/WASM plugins, Liquid/Mustache templates), each with its own runtime and memory model.

The arena context store replaces a conventional tree of heap-allocated objects (e.g. Nim's `JsonNode`) with a flat, arena-allocated data structure designed for three properties:

1. **Zero-cost cross-language access.** The data lives in a contiguous memory region that can be mapped into any address space — host process, WASM linear memory, or shared memory — without serialization or copying.
2. **Cheap persistence.** The arena is a flat byte buffer. Saving and loading build state is a file write/read (or mmap) with no encoding step.
3. **Surgical incremental rebuilds.** Each node tracks where it came from (provenance). Combined with a reverse dependency index and external change detection (git diff, fswatch), only affected nodes and pages are reprocessed on subsequent builds.

## Architecture

### System context

```
┌─────────────────────────────────────────────────────────┐
│ Change Detection Plugins                                │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │  git diff     │  │  fswatch     │                     │
│  │  (node-level) │  │  (file-level)│                     │
│  └──────┬───────┘  └──────┬───────┘                     │
│         └──────┬──────────┘                              │
│                ▼                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │                    Core                           │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │         Arena Context Store                 │  │   │
│  │  │  ┌───────────┬──────────┬───────────────┐  │  │   │
│  │  │  │ Node Table│ Trie Keys│ String Heap   │  │  │   │
│  │  │  ├───────────┼──────────┼───────────────┤  │  │   │
│  │  │  │ Entries   │ Children │ Provenance    │  │  │   │
│  │  │  └───────────┴──────────┴───────────────┘  │  │   │
│  │  │  ┌─────────────────────────────────────┐   │  │   │
│  │  │  │   Reverse Dependency Index           │  │  │   │
│  │  │  └─────────────────────────────────────┘   │  │   │
│  │  └────────────────────────────────────────────┘  │   │
│  │                    │                              │   │
│  │      ┌─────────────┼─────────────┐               │   │
│  │      ▼             ▼             ▼               │   │
│  │  ┌────────┐  ┌──────────┐  ┌──────────┐         │   │
│  │  │Template│  │  Script  │  │  WASM    │         │   │
│  │  │Engines │  │  Engines │  │  Plugins │         │   │
│  │  │Liquid  │  │  QuickJS │  │  Rust/C  │         │   │
│  │  │Mustache│  │  Duktape │  │  Zig/Nim │         │   │
│  │  └────────┘  └──────────┘  └──────────┘         │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

Template engines are read-only consumers. Script engines can read and mutate. WASM plugins operate on a copy of the arena mapped into their linear memory (read-only) or go through host-imported functions (read-write). Change detection plugins are external — they don't access the arena, they emit sets of dirty node IDs or dirty file paths that the core uses to drive selective rebuilds.

---

## Data layout

The arena consists of six contiguous buffers, each independently growable:

| Buffer       | Entry size | Indexed by | Purpose |
|-------------|-----------|-----------|---------|
| `nodes`      | Fixed      | `NodeId`   | All value nodes (scalars, containers) |
| `strings`    | Variable   | Byte offset | Append-only string/byte heap |
| `entries`    | Fixed      | Byte offset | Object key-value pairs |
| `children`   | Fixed      | Byte offset | Array child lists |
| `tries`      | Fixed      | Byte offset | Per-object trie nodes for key lookup |
| `provenance` | Fixed      | `NodeId`   | Source origin metadata, parallel to `nodes` |

### Node representation

```nim
type
  NodeId = distinct uint32
    ## Stable identifier. Never reused or reassigned.

  NodeKind = enum
    nkNull
    nkBool
    nkInt
    nkFloat
    nkString
    nkArray
    nkObject

  Node {.packed.} = object
    kind: NodeKind            # 1 byte
    padding: array[3, byte]   # alignment
    case kind
    of nkNull:
      discard
    of nkBool:
      boolVal: bool
    of nkInt:
      intVal: int64
    of nkFloat:
      floatVal: float64
    of nkString:
      strOffset: uint32       # byte offset into strings buffer
      strLen: uint32           # actual length
      strCap: uint32           # allocated capacity (for in-place mutation)
    of nkArray:
      childOffset: uint32     # byte offset into children buffer
      childLen: uint32         # number of children
      childCap: uint32         # allocated capacity
    of nkObject:
      entryOffset: uint32     # byte offset into entries buffer
      entryCount: uint32       # number of key-value pairs
      entryCap: uint32         # allocated capacity
      trieOffset: uint32       # byte offset into tries buffer (0 = no trie)
```

Fixed-size node slots mean `NodeId` is a direct index: `addr nodes[id.uint32]`. Node IDs are stable for the lifetime of the arena — they are never reused, so external references (from plugins, dependency tracking, serialized caches) remain valid.

### String heap

Strings are stored in a single append-only byte buffer. Each string occupies `strCap` bytes at its offset, with `strLen` bytes of actual content. The initial allocation strategy:

- On creation: `strCap = strLen * 2` (2× slack for in-place mutation)
- On mutation that fits: overwrite in place, update `strLen`
- On mutation that overflows: append new allocation at end of heap, update node's offset/len/cap, mark old region as free

Freed regions are tracked in a simple free list sorted by offset. New allocations check the free list first (first-fit) before appending. For build-and-discard workloads, fragmentation is irrelevant and the free list can be skipped entirely.

Strings are stored as raw UTF-8 bytes, null-terminated for C compatibility. `strLen` does not include the null terminator; `strCap` does.

### Object entries

```nim
type
  Entry {.packed.} = object
    keyOffset: uint32     # byte offset into strings buffer
    keyLen: uint32         # key length
    valueNode: NodeId      # node ID of the value
```

An object's entries are stored contiguously starting at `entryOffset` in the entries buffer. Lookup by key can use one of two strategies depending on entry count:

- **≤16 entries:** Linear scan. Typical for page metadata objects. The entries fit in a cache line or two.
- **>16 entries:** Trie lookup (see below).

The threshold is tunable. The linear scan is simple and has good cache behavior for small objects, which dominate in typical site contexts (page frontmatter, config sections).

### Trie-indexed key lookup

For objects with many keys, a trie (prefix tree) enables O(k) lookup where k is the length of the key — or less, since lookup terminates as soon as the prefix is unique.

```nim
const
  AlphabetSize = 64  # a-z, A-Z, 0-9, _, -
  
  AsciiOffset = array[256, int8]  # maps ASCII byte to 0..63 or -1

type
  TrieNode {.packed.} = object
    children: array[AlphabetSize, uint32]  # offset to child TrieNode, 0 = none
    entryIndex: int32                       # index into object's entries, -1 = not a leaf
```

Lookup for key `"title"`:

1. Start at the object's `trieOffset`
2. Read `'t'` → map to index via `AsciiOffset` → follow `children[idx]`
3. Read `'i'` → follow child → arrive at leaf with `entryIndex >= 0`
4. Key is unique after `"ti"` — lookup complete in 2 steps

The trie is built lazily on first lookup (or eagerly during ingestion for objects known to be large). It is stored in the `tries` buffer as a flat array of `TrieNode` records.

Each TrieNode is `64 * 4 + 4 = 260 bytes`. A trie for an object with 50 keys might have ~80 nodes = ~20KB. This is larger than a hash table but provides deterministic worst-case performance with no hash collisions, and the flat layout means excellent cache behavior during traversal.

For memory-constrained scenarios, a **radix trie** variant collapses single-child chains, reducing node count significantly. This is an optimization that can be added later without changing the lookup API.

### Array children

```nim
# children buffer contains packed NodeId values
# array node's childOffset points to first child
# childLen gives count, childCap gives allocated slots
```

Push appends to the end if capacity allows, otherwise relocates the child list (same strategy as strings).

---

## Provenance tracking

Each node has a parallel provenance record:

```nim
type
  SourceKind = enum
    skFile        # ingested from a source file
    skComputed    # produced by a script/plugin
    skLiteral     # hardcoded in config or created by core

  Provenance {.packed.} = object
    sourceKind: SourceKind
    sourceFileId: uint32      # index into file path table (for skFile)
    sourceOffset: uint32      # byte offset in source file
    producerPluginId: uint32  # which plugin created this (for skComputed)
    generation: uint32        # build number when this node was last written
```

The `generation` field enables cheap staleness checks: if a node's generation is less than the current build number, it hasn't been touched this build.

### File path table

A separate table maps `sourceFileId` to file paths:

```nim
type
  FileEntry = object
    pathOffset: uint32    # offset into strings buffer
    pathLen: uint32
    lastBuildHash: uint64 # content hash at last full ingest
```

This table is small (one entry per source file) and is stored alongside the arena.

---

## Reverse dependency index

The reverse dependency index answers: "if node X changed, what needs to be rebuilt?"

```nim
type
  DepKind = enum
    dkPageRender    # a page template read this node
    dkScriptOutput  # a script read this node while computing another node

  Dependency = object
    kind: DepKind
    consumerId: uint32    # PageId or ScriptId
    nodeId: NodeId         # the node that was read
```

This is populated during script execution and template rendering by intercepting read access. Each `ctx_get` call through the plugin API records a dependency edge.

Storage: a flat array of `Dependency` records, rebuilt each full build, updated incrementally on partial rebuilds.

### Rebuild flow

```
Input: Set[NodeId] dirty nodes (from change detection plugin)

1. For each dirty NodeId, query reverse dependency index:
   → collect Set[PageId] of affected pages
   → collect Set[ScriptId] of affected scripts

2. Re-run affected scripts:
   → scripts may read clean nodes (no recompute needed)
   → scripts may produce new/updated nodes
   → new dirty nodes may cascade (repeat until stable)

3. Re-render affected pages:
   → template engine reads from arena (mostly clean cached data)
   → write output files only for changed pages

4. Update provenance generation numbers for all touched nodes
5. Persist arena to disk
```

---

## Cross-language access

### C API (native plugins, JS engine bindings)

```c
/* Opaque handle — just a uint32 internally */
typedef uint32_t NodeId;
typedef struct Arena Arena;

/* Traversal */
NodeId    arena_root(Arena* a);
uint8_t   arena_type(Arena* a, NodeId id);
NodeId    arena_get(Arena* a, NodeId id, const char* key, uint32_t key_len);
NodeId    arena_index(Arena* a, NodeId id, uint32_t index);
uint32_t  arena_length(Arena* a, NodeId id);

/* Scalar read — zero-copy for strings */
const char* arena_string_ptr(Arena* a, NodeId id);
uint32_t    arena_string_len(Arena* a, NodeId id);
double      arena_float(Arena* a, NodeId id);
int64_t     arena_int(Arena* a, NodeId id);
bool        arena_bool(Arena* a, NodeId id);

/* Mutation */
NodeId arena_new_string(Arena* a, const char* data, uint32_t len);
NodeId arena_new_int(Arena* a, int64_t val);
NodeId arena_new_float(Arena* a, double val);
NodeId arena_new_bool(Arena* a, bool val);
NodeId arena_new_object(Arena* a);
NodeId arena_new_array(Arena* a);
void   arena_set(Arena* a, NodeId obj, const char* key, uint32_t key_len, NodeId val);
void   arena_push(Arena* a, NodeId arr, NodeId val);
void   arena_set_string(Arena* a, NodeId id, const char* data, uint32_t len);

/* Dependency tracking (called automatically by bindings) */
void arena_record_read(Arena* a, NodeId id, uint32_t consumer_id);
```

All functions operate on `NodeId` values (plain `uint32_t`). No pointers to manage, no ownership semantics, no GC interaction. `arena_string_ptr` returns a direct pointer into the string heap — zero-copy for C plugins and for JS engine bindings that need to pass the bytes to the engine's string constructor.

### WASM plugins (via host imports)

Same API shape as C, exposed as WASM host imports. The WASM runtime (wasm3, Wasmtime) bridges the calls. For read-heavy plugins, the arena (or a read-only snapshot) can be copied into WASM linear memory for direct access without host calls.

### Nim-native API

```nim
proc `[]`(arena: Arena, id: NodeId, key: string): NodeId
proc `[]`(arena: Arena, id: NodeId, index: int): NodeId
proc len(arena: Arena, id: NodeId): int
proc kind(arena: Arena, id: NodeId): NodeKind
proc getStr(arena: Arena, id: NodeId): string     # copies out
proc getStrView(arena: Arena, id: NodeId): openArray[byte]  # zero-copy view
proc getInt(arena: Arena, id: NodeId): int64
proc getFloat(arena: Arena, id: NodeId): float64
proc getBool(arena: Arena, id: NodeId): bool

proc newStr(arena: var Arena, val: string): NodeId
proc newObj(arena: var Arena): NodeId
proc newArr(arena: var Arena): NodeId
proc set(arena: var Arena, obj: NodeId, key: string, val: NodeId)
proc add(arena: var Arena, arr: NodeId, val: NodeId)

iterator items(arena: Arena, id: NodeId): NodeId    # array iteration
iterator pairs(arena: Arena, id: NodeId): (string, NodeId)  # object iteration
```

This is the API the Liquid VM and Mustache renderer would use. `getStrView` returns a direct view into the heap without copying — useful for template engines that are concatenating output and can write the bytes directly.

---

## Persistence

### On-disk format

The arena serializes as a single file with a header followed by each buffer:

```
[Header]
  magic: "ACTX"
  version: uint32
  generation: uint32 (build number)
  buffer_count: uint32
  
[Buffer Directory]
  For each buffer:
    offset: uint64
    length: uint64
    
[Buffer Data]
  nodes, strings, entries, children, tries, provenance
  (in order, page-aligned for mmap compatibility)

[File Path Table]
[Reverse Dependency Index]
```

Loading is a single `mmap` call. The buffers are used directly from mapped memory for reads. On mutation (during an incremental rebuild), modified regions are copied on write into heap memory, and the full arena is re-persisted after the build completes.

### Bytecode cache

Template bytecode (Liquid VM, compiled JS via QuickJS) is stored in a separate cache file, keyed by a content hash of the template source. On build:

1. Hash the template source
2. Look up hash in bytecode cache
3. Cache hit → load bytecode directly, skip parsing
4. Cache miss → parse, compile, store bytecode in cache

The bytecode cache is independent of the arena and can be invalidated separately.

---

## Implementation phases

**Phase 1 — Arena library.** Node storage, string heap, object entries, array children. Linear scan for key lookup. Append-only mutation. Round-trip tests against existing site data (ingest from JSON, verify reads). No trie, no provenance, no persistence.

**Phase 2 — Provenance and dependencies.** Add source tracking metadata. Build the reverse dependency index. File path table. Still a standalone library with no SSG integration.

**Phase 3 — Core integration.** Replace `JsonNode` with arena-backed access in the Liquid VM, Mustache renderer, and Duktape bindings. The C API layer goes in here. Verify identical output for existing test sites.

**Phase 4 — Persistence and incremental rebuilds.** On-disk format, mmap loading, integration with git diff and fswatch change detection plugins. Bytecode cache for Liquid VM.

**Phase 5 — Trie optimization.** Profile real-world access patterns, add trie indexing for large objects if linear scan proves to be a bottleneck.

**Phase 6 — WASM plugin support.** Expose C API as WASM host imports, integrate a lightweight runtime (wasm3). Ship SDK crates/packages for Rust, C, Zig plugin authors.
