## String heap operations for the arena context store.
##
## Strings are stored in a single append-only byte buffer.
## Each string occupies `strCap` bytes at its offset, with `strLen` bytes
## of actual content. Strings are null-terminated for C compatibility.

import std/algorithm
import types

proc allocString*(arena: var Arena, data: openArray[byte]): tuple[offset, len, cap: uint32] =
  ## Allocate a new string in the heap. Returns offset, length, capacity.
  ## Tries free list first (first-fit), then appends.
  let dataLen = uint32(data.len)
  let needed = dataLen + 1  # +1 for null terminator
  let cap = max(needed, dataLen * 2 + 1)  # 2x slack

  # Try free list first (first-fit)
  for i in 0 ..< arena.stringFreeList.len:
    let region = arena.stringFreeList[i]
    if region.size >= cap:
      let offset = region.offset
      # Copy data into the freed region
      for j in 0'u32 ..< dataLen:
        arena.strings[offset + j] = data[j]
      arena.strings[offset + dataLen] = 0  # null terminator
      # Shrink or remove free region
      if region.size > cap:
        arena.stringFreeList[i] = FreeRegion(offset: offset + cap, size: region.size - cap)
      else:
        arena.stringFreeList.delete(i)
      return (offset, dataLen, cap)

  # Append to end
  let offset = uint32(arena.strings.len)
  arena.strings.setLen(arena.strings.len + int(cap))
  for j in 0'u32 ..< dataLen:
    arena.strings[offset + j] = data[j]
  arena.strings[offset + dataLen] = 0  # null terminator
  result = (offset, dataLen, cap)

proc allocString*(arena: var Arena, s: string): tuple[offset, len, cap: uint32] =
  ## Convenience overload for string input.
  if s.len == 0:
    allocString(arena, newSeq[byte](0))
  else:
    allocString(arena, s.toOpenArrayByte(0, s.high))

proc readString*(arena: Arena, offset, length: uint32): string =
  ## Read a string back from the heap. Copies the data out.
  if length == 0:
    return ""
  result = newString(length)
  for i in 0'u32 ..< length:
    result[i] = char(arena.strings[offset + i])

proc readStringBytes*(arena: Arena, offset, length: uint32): seq[byte] =
  ## Read raw bytes from the string heap.
  if length == 0:
    return @[]
  result = newSeq[byte](length)
  for i in 0'u32 ..< length:
    result[i] = arena.strings[offset + i]

proc updateString*(arena: var Arena, node: var Node, newData: openArray[byte]) =
  ## Mutate a string node's value. If the new data fits in the existing
  ## capacity, overwrites in place. Otherwise allocates new space and
  ## frees the old region.
  node.expectKind(nkString)
  let newLen = uint32(newData.len)
  let needed = newLen + 1  # +1 for null terminator

  if needed <= node.strCap:
    # Fits in place
    for i in 0'u32 ..< newLen:
      arena.strings[node.strOffset + i] = newData[i]
    arena.strings[node.strOffset + newLen] = 0  # null terminator
    node.strLen = newLen
  else:
    # Must relocate — free old region, allocate new
    let oldOffset = node.strOffset
    let oldCap = node.strCap
    arena.stringFreeList.add(FreeRegion(offset: oldOffset, size: oldCap))
    # Sort free list by offset for potential coalescing
    arena.stringFreeList.sort(proc(a, b: FreeRegion): int = int(a.offset) - int(b.offset))
    let (newOffset, nl, nc) = arena.allocString(newData)
    node.strOffset = newOffset
    node.strLen = nl
    node.strCap = nc

proc freeString*(arena: var Arena, offset, cap: uint32) =
  ## Mark a string region as free.
  arena.stringFreeList.add(FreeRegion(offset: offset, size: cap))
  arena.stringFreeList.sort(proc(a, b: FreeRegion): int = int(a.offset) - int(b.offset))
