## Save and load an arena as a flat binary stream.
##
## This is the pragmatic cache format, not the mmap design from the
## plan: every buffer is written field by field, so the file does not
## depend on Nim's in-memory object layout. It is a machine-local cache
## in native byte order — regenerable, versioned, and rejected loudly
## on mismatch rather than migrated.
##
## Runtime-only state does not persist: the loader registry re-registers
## at startup, and the origin/consumer stacks must be empty between
## builds. The access log DOES persist — it is the point: a cold process
## that loads a cached arena can answer invalidation queries about the
## previous build.

import std/streams
import types

const ArenaCacheVersion* = 1'u32
const ArenaCacheMagic = 0x41435458'u32  # "ACTX"

type
  ArenaCacheError* = object of ValueError
    ## The stream is not a compatible arena cache.

# ─── Writing ─────────────────────────────────────────────────────────

proc writeStr(s: Stream, v: string) =
  s.write(uint32(v.len))
  if v.len > 0:
    s.writeData(unsafeAddr v[0], v.len)

proc saveArena*(arena: Arena, s: Stream) =
  assert arena.originStack.len == 0, "Origin stack must be empty between builds"

  s.write(ArenaCacheMagic)
  s.write(ArenaCacheVersion)

  # Nodes, field by field.
  s.write(uint32(arena.nodes.len))
  for node in arena.nodes:
    s.write(uint8(node.kind))
    case node.kind
    of nkNull: discard
    of nkBool: s.write(uint8(node.boolVal))
    of nkInt: s.write(node.intVal)
    of nkFloat: s.write(node.floatVal)
    of nkString:
      s.write(node.strOffset); s.write(node.strLen); s.write(node.strCap)
    of nkArray:
      s.write(node.childOffset); s.write(node.childLen); s.write(node.childCap)
    of nkObject:
      s.write(node.entryOffset); s.write(node.entryCount)
      s.write(node.entryCap); s.write(node.trieOffset)

  # String heap as one block.
  s.write(uint32(arena.strings.len))
  if arena.strings.len > 0:
    s.writeData(unsafeAddr arena.strings[0], arena.strings.len)

  s.write(uint32(arena.stringFreeList.len))
  for region in arena.stringFreeList:
    s.write(region.offset); s.write(region.size)

  s.write(uint32(arena.entries.len))
  for entry in arena.entries:
    s.write(entry.keyOffset); s.write(entry.keyLen); s.write(uint32(entry.valueNode))

  s.write(uint32(arena.children.len))
  for child in arena.children:
    s.write(uint32(child))

  s.write(uint32(arena.sources.len))
  for source in arena.sources:
    s.writeStr(source)

  s.write(uint32(arena.origins.len))
  for origin in arena.origins:
    s.write(uint8(origin.format))
    s.write(origin.sourceId); s.write(origin.offset); s.write(uint32(origin.previous))

  s.write(uint32(arena.nodeOrigins.len))
  for oid in arena.nodeOrigins:
    s.write(uint32(oid))

  # The access log.
  if arena.tracking == nil:
    s.write(0'u32)
  else:
    s.write(uint32(arena.tracking.accesses.len))
    for rec in arena.tracking.accesses:
      s.write(uint8(rec.kind))
      s.write(uint32(rec.nodeId)); s.write(rec.edge); s.write(rec.consumerId)

# ─── Reading ─────────────────────────────────────────────────────────

proc readStr(s: Stream): string =
  let len = int(s.readUint32())
  result = newString(len)
  if len > 0:
    if s.readData(addr result[0], len) != len:
      raise newException(ArenaCacheError, "Truncated arena cache")

proc loadArena*(s: Stream): Arena =
  if s.readUint32() != ArenaCacheMagic:
    raise newException(ArenaCacheError, "Not an arena cache")
  let version = s.readUint32()
  if version != ArenaCacheVersion:
    raise newException(ArenaCacheError,
      "Arena cache version " & $version & ", expected " & $ArenaCacheVersion)

  result = initArena()

  let nodeCount = int(s.readUint32())
  result.nodes = newSeqOfCap[Node](nodeCount)
  for i in 0 ..< nodeCount:
    let kind = NodeKind(s.readUint8())
    var node = Node(kind: kind)
    case kind
    of nkNull: discard
    of nkBool: node.boolVal = s.readUint8() != 0
    of nkInt: node.intVal = s.readInt64()
    of nkFloat: node.floatVal = s.readFloat64()
    of nkString:
      node.strOffset = s.readUint32(); node.strLen = s.readUint32()
      node.strCap = s.readUint32()
    of nkArray:
      node.childOffset = s.readUint32(); node.childLen = s.readUint32()
      node.childCap = s.readUint32()
    of nkObject:
      node.entryOffset = s.readUint32(); node.entryCount = s.readUint32()
      node.entryCap = s.readUint32(); node.trieOffset = s.readUint32()
    result.nodes.add(node)

  let stringsLen = int(s.readUint32())
  result.strings = newSeq[byte](stringsLen)
  if stringsLen > 0:
    if s.readData(addr result.strings[0], stringsLen) != stringsLen:
      raise newException(ArenaCacheError, "Truncated arena cache")

  let freeCount = int(s.readUint32())
  for i in 0 ..< freeCount:
    let offset = s.readUint32()
    let size = s.readUint32()
    result.stringFreeList.add(FreeRegion(offset: offset, size: size))

  let entryCount = int(s.readUint32())
  result.entries = newSeqOfCap[Entry](entryCount)
  for i in 0 ..< entryCount:
    let keyOffset = s.readUint32()
    let keyLen = s.readUint32()
    let valueNode = NodeId(s.readUint32())
    result.entries.add(Entry(keyOffset: keyOffset, keyLen: keyLen, valueNode: valueNode))

  let childCount = int(s.readUint32())
  result.children = newSeqOfCap[NodeId](childCount)
  for i in 0 ..< childCount:
    result.children.add(NodeId(s.readUint32()))

  let sourceCount = int(s.readUint32())
  for i in 0 ..< sourceCount:
    result.sources.add(s.readStr())

  let originCount = int(s.readUint32())
  for i in 0 ..< originCount:
    let format = SourceFormat(s.readUint8())
    let sourceId = s.readUint32()
    let offset = s.readUint32()
    let previous = OriginId(s.readUint32())
    result.origins.add(Origin(format: format, sourceId: sourceId,
                              offset: offset, previous: previous))

  let nodeOriginCount = int(s.readUint32())
  result.nodeOrigins = newSeqOfCap[OriginId](nodeOriginCount)
  for i in 0 ..< nodeOriginCount:
    result.nodeOrigins.add(OriginId(s.readUint32()))

  let accessCount = int(s.readUint32())
  result.tracking.accesses = newSeqOfCap[AccessRecord](accessCount)
  for i in 0 ..< accessCount:
    let kind = AccessKind(s.readUint8())
    let nodeId = NodeId(s.readUint32())
    let edge = s.readUint32()
    let consumerId = s.readUint32()
    result.tracking.accesses.add(AccessRecord(
      kind: kind, nodeId: nodeId, edge: edge, consumerId: consumerId))
