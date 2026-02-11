import std/[unittest, json]
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/origins
import arena_context_store/api
import arena_context_store/loader
import arena_context_store/loader_json

suite "Loader - Registration":
  test "register a loader by format and extensions":
    var arena = initArena()
    arena.registerLoader("json", @[".json"], jsonLoader)
    check arena.loaders.len == 1
    check arena.loaders[0].format == "json"
    check arena.loaders[0].extensions == @[".json"]

  test "register multiple loaders":
    var arena = initArena()
    arena.registerLoader("json", @[".json"], jsonLoader)
    arena.registerLoader("json5", @[".json5"], jsonLoader)
    check arena.loaders.len == 2

  test "registerJsonLoader registers .json extension":
    var arena = initArena()
    arena.registerJsonLoader()
    check arena.loaders.len == 1
    check arena.loaders[0].extensions == @[".json"]

suite "Loader - Dispatch by Extension":
  test "load dispatches to correct loader by extension":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("data/config.json", """{"title": "hello"}""")
    check arena.kind(root) == nkObject
    check arena.getStr(arena[root, "title"]) == "hello"

  test "load with nested path":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("/some/deep/path/data.json", """{"x": 1}""")
    check arena.getInt(arena[root, "x"]) == 1

  test "load unknown extension raises":
    var arena = initArena()
    arena.registerJsonLoader()
    expect(ValueError):
      discard arena.load("data.yaml", "{}")

  test "extension matching is case-insensitive":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("data.JSON", """{"ok": true}""")
    check arena.getBool(arena[root, "ok"]) == true

suite "Loader - Dispatch by Format":
  test "load by explicit format name":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.loadFormat("data.txt", """{"x": 42}""", "json")
    check arena.getInt(arena[root, "x"]) == 42

  test "load by unknown format raises":
    var arena = initArena()
    arena.registerJsonLoader()
    expect(ValueError):
      discard arena.loadFormat("data.json", "{}", "yaml")

suite "Loader - JSON Round-Trip":
  test "simple object":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("test.json", """{"name": "Alice", "age": 30, "active": true}""")
    check arena.kind(root) == nkObject
    check arena.getStr(arena[root, "name"]) == "Alice"
    check arena.getInt(arena[root, "age"]) == 30
    check arena.getBool(arena[root, "active"]) == true

  test "nested objects":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("test.json",
      """{"site": {"title": "Blog", "author": {"name": "Bob"}}}""")
    let site = arena[root, "site"]
    check arena.getStr(arena[site, "title"]) == "Blog"
    check arena.getStr(arena[arena[site, "author"], "name"]) == "Bob"

  test "array of values":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("test.json", """[1, 2, 3, "four", true, null]""")
    check arena.kind(root) == nkArray
    check arena.len(root) == 6
    check arena.getInt(arena[root, 0]) == 1
    check arena.getStr(arena[root, 3]) == "four"
    check arena.getBool(arena[root, 4]) == true
    check arena.isNull(arena[root, 5]) == true

  test "empty structures":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("test.json", """{"obj": {}, "arr": [], "str": ""}""")
    check arena.len(arena[root, "obj"]) == 0
    check arena.len(arena[root, "arr"]) == 0
    check arena.getStr(arena[root, "str"]) == ""

  test "float values":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("test.json", """{"pi": 3.14, "neg": -0.5}""")
    check abs(arena.getFloat(arena[root, "pi"]) - 3.14) < 0.001
    check abs(arena.getFloat(arena[root, "neg"]) - (-0.5)) < 0.001

  test "null value":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("test.json", """{"nothing": null}""")
    check arena.isNull(arena[root, "nothing"]) == true

suite "Loader - JSON toJson Round-Trip":
  test "arena to JsonNode round-trip":
    var arena = initArena()
    arena.registerJsonLoader()
    let input = """{"title": "Test", "count": 42, "items": [1, "two", true]}"""
    let root = arena.load("test.json", input)
    let output = arena.toJson(root)
    let expected = parseJson(input)
    check output == expected

  test "complex structure round-trip":
    let input = %*{
      "site": {"title": "My Blog", "url": "https://example.com"},
      "pages": [
        {"title": "First", "tags": ["nim", "web"], "draft": false},
        {"title": "Second", "tags": [], "draft": true}
      ],
      "config": {"postsPerPage": 10, "version": 2.5}
    }
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("site.json", $input)
    let output = arena.toJson(root)
    check output == input

suite "Loader - Origin Integration":
  test "all loaded nodes are tagged with correct origin":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("config.json", """{"title": "Hello", "count": 42}""")
    let rootOrigin = arena.getNodeOrigin(root)
    check rootOrigin != InvalidOriginId
    let origin = arena.getOrigin(rootOrigin)
    check origin.format == sfJson
    check arena.getSourcePath(origin.sourceId) == "config.json"
    # Nested nodes also tagged
    let titleNode = arena[root, "title"]
    check arena.getNodeOrigin(titleNode) != InvalidOriginId

  test "two files get distinct origins":
    var arena = initArena()
    arena.registerJsonLoader()
    let r1 = arena.load("a.json", """{"x": 1}""")
    let r2 = arena.load("b.json", """{"y": 2}""")
    let o1 = arena.getNodeOrigin(r1)
    let o2 = arena.getNodeOrigin(r2)
    check o1 != o2
    check arena.getSourcePath(arena.getOrigin(o1).sourceId) == "a.json"
    check arena.getSourcePath(arena.getOrigin(o2).sourceId) == "b.json"

  test "nested nodes share same origin as root":
    var arena = initArena()
    arena.registerJsonLoader()
    let root = arena.load("data.json",
      """{"nested": {"deep": {"value": 42}}}""")
    let rootOrigin = arena.getNodeOrigin(root)
    let nested = arena[root, "nested"]
    let deep = arena[nested, "deep"]
    let value = arena[deep, "value"]
    check arena.getNodeOrigin(nested) == rootOrigin
    check arena.getNodeOrigin(deep) == rootOrigin
    check arena.getNodeOrigin(value) == rootOrigin

  test "origin stack is clean after load":
    var arena = initArena()
    arena.registerJsonLoader()
    discard arena.load("test.json", """{"x": 1}""")
    check arena.currentOrigin() == InvalidOriginId
