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

  Arena* = object
    nodes*: seq[Node]
    strings*: seq[byte]
    entries*: seq[Entry]
    children*: seq[NodeId]
    # tries buffer deferred to Phase 5
    # provenance buffer deferred to Phase 2
    stringFreeList*: seq[FreeRegion]

const
  InvalidNodeId* = NodeId(uint32.high)

proc `==`*(a, b: NodeId): bool {.borrow.}
proc `$`*(id: NodeId): string = "NodeId(" & $uint32(id) & ")"

proc initArena*(): Arena =
  ## Create a new empty arena.
  result = Arena(
    nodes: @[],
    strings: @[],
    entries: @[],
    children: @[],
    stringFreeList: @[],
  )
