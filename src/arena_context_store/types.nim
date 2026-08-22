## Core types for the arena context store.
##
## The arena consists of multiple contiguous buffers, each independently growable.
## NodeId is a stable identifier that is never reused or reassigned.

import std/hashes

type
  NodeId* = distinct uint32
    ## Stable identifier into the node table. Never reused.

  NodeKind* = enum
    nkNull = 0
    nkBool = 1
    nkInt = 2
    nkFloat = 3
    nkString = 4
    nkArray = 5
    nkObject = 6

  Node* = object
    case kind*: NodeKind
    of nkNull:
      discard
    of nkBool:
      boolVal*: bool
    of nkInt:
      intVal*: int64
    of nkFloat:
      floatVal*: float64
    of nkString:
      strOffset*: uint32   ## byte offset into strings buffer
      strLen*: uint32       ## actual byte length (excluding null terminator)
      strCap*: uint32       ## allocated capacity (including null terminator)
    of nkArray:
      childOffset*: uint32 ## byte offset into children buffer
      childLen*: uint32     ## number of children
      childCap*: uint32     ## allocated capacity
    of nkObject:
      entryOffset*: uint32 ## byte offset into entries buffer
      entryCount*: uint32   ## number of key-value pairs
      entryCap*: uint32     ## allocated capacity
      trieOffset*: uint32   ## byte offset into tries buffer (0 = no trie)

  Entry* = object
    keyOffset*: uint32  ## byte offset into strings buffer
    keyLen*: uint32      ## key length in bytes
    valueNode*: NodeId   ## node ID of the value

  FreeRegion* = object
    offset*: uint32
    size*: uint32

  # --- Origin Tracking ---

  SourceFormat* = enum
    sfUnknown = 0
    sfJson = 1
    sfYaml = 2
    sfCsv = 3
    sfToml = 4
    sfLiteral = 5    ## hardcoded / programmatic
    sfComputed = 6   ## produced by a plugin

  OriginId* = distinct uint32
    ## Index into the origins table. InvalidOriginId means "no origin set".

  Origin* = object
    format*: SourceFormat
    sourceId*: uint32     ## index into Arena.sources (interned path)
    offset*: uint32       ## byte offset in source (0 = unknown)
    previous*: OriginId   ## linked list — previous origin, InvalidOriginId = none

  # --- Access Tracking ---

  AccessKind* = enum
    akRead      ## Depends on the node's own record, or on one traversed edge.
    akIterate   ## Depends on the container's whole edge set: count, keys, bindings.
    akWrite     ## Created the node, mutated its value, or rebound one of its edges.

  AccessRecord* = object
    ## One access by one consumer. `edge` narrows a container access to a
    ## single entry (objects) or child slot (arrays); NoEdge means the access
    ## concerned the node itself rather than one of its edges.
    ##
    ## Invalidation semantics for the index that consumes these records:
    ##   akRead  + NoEdge -> stale when the node record changes (kind or
    ##                       scalar value).
    ##   akRead  + edge   -> stale when that edge is rebound.
    ##   akIterate        -> stale when any edge is added, removed or rebound.
    ## A lookup that missed records akIterate, because adding the absent key
    ## would change the answer.
    kind*: AccessKind
    nodeId*: NodeId
    edge*: uint32
    consumerId*: uint32

  TrackingLog* = ref object
    ## Runtime-only access log. Held by reference so read procs can record
    ## through an immutable Arena: readers never need var access to the
    ## data buffers themselves. Set to nil to disable tracking entirely
    ## (e.g. on a full build, where nothing consumes it).
    accesses*: seq[AccessRecord]
    consumerStack*: seq[uint32]  ## push/pop consumer context

  # --- Loader Registry ---

  LoadProc* = proc(arena: var Arena, data: string, path: string): NodeId {.nimcall.}
    ## A loader takes raw file content + path, returns root NodeId.

  LoaderEntry* = object
    format*: string
    extensions*: seq[string]
    load*: LoadProc

  # --- Arena ---

  Arena* = object
    nodes*: seq[Node]
    strings*: seq[byte]
    entries*: seq[Entry]
    children*: seq[NodeId]
    stringFreeList*: seq[FreeRegion]
    # Origin tracking
    sources*: seq[string]         ## interned source paths
    origins*: seq[Origin]         ## origin records
    nodeOrigins*: seq[OriginId]   ## parallel to nodes
    originStack*: seq[OriginId]   ## push/pop context stack
    # Loader registry
    loaders*: seq[LoaderEntry]
    # Access tracking
    tracking*: TrackingLog

const
  InvalidNodeId* = NodeId(uint32.high)
  InvalidOriginId* = OriginId(uint32.high)
  InvalidConsumerId* = uint32.high
  InvalidSourceId* = uint32.high
  NoEdge* = uint32.high
    ## Marks an access to a node itself rather than to one of its edges.

proc `==`*(a, b: NodeId): bool {.borrow.}
proc hash*(id: NodeId): Hash {.borrow.}
proc `$`*(id: NodeId): string = "NodeId(" & $uint32(id) & ")"

proc expectKind*(node: Node, kind: NodeKind) {.inline.} =
  ## Raise if the node is not of the expected kind. A real raise, not an
  ## assert: kind confusion must fail loudly in release builds too, where
  ## asserts compile out and a wrong-kind access would corrupt the arena.
  if node.kind != kind:
    raise newException(ValueError, "Expected " & $kind & " node, got " & $node.kind)

proc `==`*(a, b: OriginId): bool {.borrow.}
proc `$`*(id: OriginId): string = "OriginId(" & $uint32(id) & ")"
proc `!=`*(a, b: OriginId): bool = not (a == b)

proc initArena*(): Arena =
  ## Create a new empty arena.
  result = Arena(
    nodes: @[],
    strings: @[],
    entries: @[],
    children: @[],
    stringFreeList: @[],
    sources: @[],
    origins: @[],
    nodeOrigins: @[],
    originStack: @[],
    loaders: @[],
    tracking: TrackingLog(),
  )
