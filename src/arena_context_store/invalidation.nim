## Invalidation queries for the arena context store.
##
## Answers the question the incremental rebuild loop asks: given a set of
## writes, which consumers recorded accesses that those writes made stale?
##
## The matching rules follow AccessRecord's semantics (see types.nim):
##
##   write (N, NoEdge)  — the node's own value changed —
##     invalidates consumers that read (N, NoEdge).
##
##   write (N, edge)    — an edge was bound, rebound or appended —
##     invalidates consumers that read that exact (N, edge), and
##     every consumer that iterated N (count, keys and bindings all
##     belong to the edge set).
##
## Because every path to a node passes through the edges above it, a
## consumer that reached a value via lookups has recorded every edge on
## its path. Rebinding any of those edges therefore invalidates it, with
## no transitive walk needed at query time.
##
## Typical dev-server flow:
##   arena.clearTracking(loaderId)
##   ... reload the changed file under pushConsumer(loaderId) ...
##   let stale = arena.invalidatedBy(loaderId)
##   for consumer in stale: re-render it (clearing its records first)

import std/[tables, sets]
import types
import tracking

proc invalidatedBy*(arena: Arena, writes: openArray[AccessRecord]): HashSet[uint32] =
  ## Return the consumers whose recorded reads or iterates are made stale
  ## by the given write records. Consumers appearing in `writes` themselves
  ## are not excluded — use the writerId overload for that.
  # Index the log's reads once: exact (node, edge) readers, and iterators.
  var edgeReaders = initTable[(NodeId, uint32), HashSet[uint32]]()
  var iterators = initTable[NodeId, HashSet[uint32]]()

  for rec in arena.accesses:
    case rec.kind
    of akRead:
      edgeReaders.mgetOrPut((rec.nodeId, rec.edge), initHashSet[uint32]()).incl(rec.consumerId)
    of akIterate:
      iterators.mgetOrPut(rec.nodeId, initHashSet[uint32]()).incl(rec.consumerId)
    of akWrite:
      discard

  for w in writes:
    if w.kind != akWrite:
      continue
    if edgeReaders.hasKey((w.nodeId, w.edge)):
      result.incl(edgeReaders[(w.nodeId, w.edge)])
    if w.edge != NoEdge and iterators.hasKey(w.nodeId):
      result.incl(iterators[w.nodeId])

proc invalidatedBy*(arena: Arena, writerId: uint32): HashSet[uint32] =
  ## Return the consumers made stale by everything `writerId` has written
  ## since its records were last cleared. The writer itself is excluded.
  var writes: seq[AccessRecord] = @[]
  for rec in arena.accesses:
    if rec.consumerId == writerId and rec.kind == akWrite:
      writes.add(rec)
  result = arena.invalidatedBy(writes)
  result.excl(writerId)
