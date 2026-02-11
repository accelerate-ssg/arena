import std/[unittest, strutils]
import arena_context_store/types
import arena_context_store/string_heap

suite "String Heap - Allocation":
  test "allocate empty string":
    var arena = initArena()
    let (offset, length, cap) = arena.allocString("")
    check length == 0
    check cap >= 1  # at least null terminator
    check arena.strings[offset] == 0  # null terminated

  test "allocate simple string":
    var arena = initArena()
    let (offset, length, cap) = arena.allocString("hello")
    check length == 5
    check cap >= 6  # at least len + null terminator
    check cap >= 11  # 2x slack: 5*2+1 = 11
    # Verify content
    check arena.strings[offset + 0] == byte('h')
    check arena.strings[offset + 1] == byte('e')
    check arena.strings[offset + 2] == byte('l')
    check arena.strings[offset + 3] == byte('l')
    check arena.strings[offset + 4] == byte('o')
    check arena.strings[offset + 5] == 0  # null terminator

  test "allocate multiple strings - no overlap":
    var arena = initArena()
    let (off1, len1, cap1) = arena.allocString("hello")
    let (off2, len2, cap2) = arena.allocString("world")
    # Second string starts after first string's capacity
    check off2 >= off1 + cap1
    check len1 == 5
    check len2 == 5

  test "allocate UTF-8 string":
    var arena = initArena()
    let utf8str = "héllo wörld"
    let (offset, length, cap) = arena.allocString(utf8str)
    check length == uint32(utf8str.len)
    let readBack = readString(arena, offset, length)
    check readBack == utf8str

  test "allocate long string":
    var arena = initArena()
    let longStr = 'x'.repeat(10000)
    let (offset, length, cap) = arena.allocString(longStr)
    check length == 10000
    check cap >= 20001  # 2x slack + null
    let readBack = readString(arena, offset, length)
    check readBack == longStr

suite "String Heap - Reading":
  test "readString returns correct content":
    var arena = initArena()
    let (offset, length, _) = arena.allocString("test string")
    let result = readString(arena, offset, length)
    check result == "test string"

  test "readString for empty string":
    var arena = initArena()
    let (offset, length, _) = arena.allocString("")
    let result = readString(arena, offset, length)
    check result == ""

  test "readStringBytes returns raw bytes":
    var arena = initArena()
    let (offset, length, _) = arena.allocString("abc")
    let bytes = readStringBytes(arena, offset, length)
    check bytes.len == 3
    check bytes[0] == byte('a')
    check bytes[1] == byte('b')
    check bytes[2] == byte('c')

  test "readStringBytes for empty returns empty seq":
    var arena = initArena()
    let bytes = readStringBytes(arena, 0, 0)
    check bytes.len == 0

suite "String Heap - Mutation":
  test "update string in place (shorter)":
    var arena = initArena()
    let (offset, length, cap) = arena.allocString("hello world")
    var node = Node(kind: nkString, strOffset: offset, strLen: length, strCap: cap)
    updateString(arena, node, "hi".toOpenArrayByte(0, 1))
    check node.strLen == 2
    check node.strOffset == offset  # same offset — in place
    check readString(arena, node.strOffset, node.strLen) == "hi"

  test "update string in place (same length)":
    var arena = initArena()
    let (offset, length, cap) = arena.allocString("hello")
    var node = Node(kind: nkString, strOffset: offset, strLen: length, strCap: cap)
    updateString(arena, node, "world".toOpenArrayByte(0, 4))
    check node.strLen == 5
    check node.strOffset == offset  # same offset
    check readString(arena, node.strOffset, node.strLen) == "world"

  test "update string requires relocation (longer)":
    var arena = initArena()
    # Allocate a small string with minimal capacity
    let (offset, length, cap) = arena.allocString("hi")
    var node = Node(kind: nkString, strOffset: offset, strLen: length, strCap: cap)
    let origCap = cap
    # Now update with a very long string that won't fit
    let longStr = 'x'.repeat(int(origCap) * 3)
    updateString(arena, node, longStr.toOpenArrayByte(0, longStr.high))
    check node.strLen == uint32(longStr.len)
    # New offset should be different (relocated)
    check node.strOffset != offset
    check readString(arena, node.strOffset, node.strLen) == longStr
    # Old region should be in free list
    check arena.stringFreeList.len == 1
    check arena.stringFreeList[0].offset == offset
    check arena.stringFreeList[0].size == origCap

suite "String Heap - Free List":
  test "free list starts empty":
    var arena = initArena()
    check arena.stringFreeList.len == 0

  test "freeString adds to free list":
    var arena = initArena()
    let (offset, _, cap) = arena.allocString("hello")
    freeString(arena, offset, cap)
    check arena.stringFreeList.len == 1
    check arena.stringFreeList[0].offset == offset
    check arena.stringFreeList[0].size == cap

  test "free list reuse - exact fit":
    var arena = initArena()
    let (off1, _, cap1) = arena.allocString("hello")
    freeString(arena, off1, cap1)
    check arena.stringFreeList.len == 1

    # Allocate a string small enough to fit in the freed region
    let (off2, len2, cap2) = arena.allocString("hi")
    # Should reuse the freed region
    check off2 == off1
    check arena.stringFreeList.len <= 1  # either removed or shrunk

  test "free list reuse - partial fit leaves remainder":
    var arena = initArena()
    # Allocate a large string then free it
    let bigStr = 'x'.repeat(1000)
    let (off1, _, cap1) = arena.allocString(bigStr)
    freeString(arena, off1, cap1)
    check arena.stringFreeList.len == 1

    # Allocate a small string that should reuse part of the freed region
    let (off2, len2, cap2) = arena.allocString("hi")
    check off2 == off1  # reused from free list
    if cap2 < cap1:
      # Remainder should still be in free list
      check arena.stringFreeList.len == 1
      check arena.stringFreeList[0].offset == off1 + cap2
      check arena.stringFreeList[0].size == cap1 - cap2

  test "free list sorted by offset":
    var arena = initArena()
    let (off1, _, cap1) = arena.allocString("aaa")
    let (off2, _, cap2) = arena.allocString("bbb")
    let (off3, _, cap3) = arena.allocString("ccc")
    # Free in reverse order
    freeString(arena, off3, cap3)
    freeString(arena, off1, cap1)
    # Should be sorted by offset
    check arena.stringFreeList.len == 2
    check arena.stringFreeList[0].offset < arena.stringFreeList[1].offset

  test "multiple allocations and frees":
    var arena = initArena()
    var offsets: seq[tuple[offset, cap: uint32]]
    # Allocate several strings
    for i in 0 ..< 10:
      let (off, _, cap) = arena.allocString("str" & $i)
      offsets.add((off, cap))
    # Free odd-indexed ones
    for i in countup(1, 9, 2):
      freeString(arena, offsets[i].offset, offsets[i].cap)
    check arena.stringFreeList.len == 5
    # Allocate new strings — should reuse freed regions
    let heapSizeBefore = arena.strings.len
    for i in 0 ..< 3:
      discard arena.allocString("new" & $i)
    # Some (possibly all) should have been allocated from the free list
    # The heap might not have grown (or grown less than without free list)
