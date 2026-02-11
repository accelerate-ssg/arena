## Core types for the arena context store.
##
## The arena consists of multiple contiguous buffers, each independently growable.
## NodeId is a stable identifier that is never reused or reassigned.

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
    akRead
    akWrite

  AccessRecord* = object
    kind*: AccessKind
    nodeId*: NodeId
    consumerId*: uint32

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
    accesses*: seq[AccessRecord]
    consumerStack*: seq[uint32]  ## push/pop consumer context

const
  InvalidNodeId* = NodeId(uint32.high)
  InvalidOriginId* = OriginId(uint32.high)
  InvalidConsumerId* = uint32.high

proc `==`*(a, b: NodeId): bool {.borrow.}
proc `$`*(id: NodeId): string = "NodeId(" & $uint32(id) & ")"

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
    accesses: @[],
    consumerStack: @[],
  )
