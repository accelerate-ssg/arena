import std/[unittest, json]
import arena_context_store/types
import arena_context_store/nodes
import arena_context_store/arrays
import arena_context_store/objects
import arena_context_store/api

# Helper: convert a JsonNode tree into arena nodes
proc fromJson(arena: var Arena, j: JsonNode): NodeId =
  case j.kind
  of JNull:
    arena.newNull()
  of JBool:
    arena.newBool(j.getBool())
  of JInt:
    arena.newInt(j.getInt())
  of JFloat:
    arena.newFloat(j.getFloat())
  of JString:
    arena.newStr(j.getStr())
  of JArray:
    let arr = arena.newArr(initialCap = j.len)
    for child in j:
      arena.add(arr, arena.fromJson(child))
    arr
  of JObject:
    let obj = arena.newObj(initialCap = j.len)
    for key, val in j:
      arena.set(obj, key, arena.fromJson(val))
    obj

# Helper: convert arena nodes back to JsonNode
proc toJson(arena: var Arena, id: NodeId): JsonNode =
  case arena.kind(id)
  of nkNull:
    result = newJNull()
  of nkBool:
    result = newJBool(arena.getBool(id))
  of nkInt:
    result = newJInt(arena.getInt(id))
  of nkFloat:
    result = newJFloat(arena.getFloat(id))
  of nkString:
    result = newJString(arena.getStr(id))
  of nkArray:
    result = newJArray()
    for child in arena.items(id):
      result.add(arena.toJson(child))
  of nkObject:
    result = newJObject()
    for key, val in arena.pairs(id):
      result[key] = arena.toJson(val)

suite "Integration - JSON Round-Trip":
  test "simple object round-trip":
    let input = %*{"title": "Hello", "count": 42, "active": true}
    var arena = initArena()
    let root = arena.fromJson(input)
    let output = arena.toJson(root)
    check output == input

  test "nested object round-trip":
    let input = %*{
      "site": {
        "title": "My Blog",
        "url": "https://example.com",
        "author": {
          "name": "Alice",
          "email": "alice@example.com"
        }
      }
    }
    var arena = initArena()
    let root = arena.fromJson(input)
    let output = arena.toJson(root)
    check output == input

  test "array round-trip":
    let input = %*[1, 2, 3, "four", true, nil]
    var arena = initArena()
    let root = arena.fromJson(input)
    let output = arena.toJson(root)
    check output == input

  test "complex site context round-trip":
    let input = %*{
      "site": {
        "title": "Accelerate Blog",
        "baseUrl": "/",
        "language": "en"
      },
      "pages": [
        {
          "title": "First Post",
          "slug": "first-post",
          "date": "2024-01-15",
          "tags": ["nim", "programming"],
          "draft": false,
          "wordCount": 1500,
          "meta": {
            "description": "An introduction to Nim programming",
            "ogImage": "/images/first-post.png"
          }
        },
        {
          "title": "Second Post",
          "slug": "second-post",
          "date": "2024-02-20",
          "tags": ["web", "performance"],
          "draft": true,
          "wordCount": 800,
          "meta": nil
        }
      ],
      "navigation": [
        {"label": "Home", "url": "/"},
        {"label": "About", "url": "/about"},
        {"label": "Archive", "url": "/archive"}
      ],
      "config": {
        "postsPerPage": 10,
        "enableComments": true,
        "theme": "dark",
        "version": 2.5
      }
    }
    var arena = initArena()
    let root = arena.fromJson(input)
    let output = arena.toJson(root)
    check output == input

  test "empty structures round-trip":
    let input = %*{"emptyObj": {}, "emptyArr": [], "emptyStr": ""}
    var arena = initArena()
    let root = arena.fromJson(input)
    let output = arena.toJson(root)
    check output == input

suite "Integration - Real-World Access Patterns":
  setup:
    var arena = initArena()
    let ctx = arena.fromJson(%*{
      "site": {
        "title": "My Site",
        "pages": [
          {"title": "Home", "url": "/", "weight": 1},
          {"title": "About", "url": "/about", "weight": 2},
          {"title": "Contact", "url": "/contact", "weight": 3}
        ]
      },
      "page": {
        "title": "Current Page",
        "content": "Lorem ipsum dolor sit amet",
        "frontmatter": {
          "layout": "default",
          "tags": ["test", "example"]
        }
      }
    })

  test "traverse nested path: site.title":
    let site = arena[ctx, "site"]
    check arena.getStr(arena[site, "title"]) == "My Site"

  test "traverse array: site.pages[1].title":
    let pages = arena[arena[ctx, "site"], "pages"]
    let page1 = arena[pages, 1]
    check arena.getStr(arena[page1, "title"]) == "About"

  test "iterate pages":
    let pages = arena[arena[ctx, "site"], "pages"]
    var titles: seq[string]
    for page in arena.items(pages):
      titles.add(arena.getStr(arena[page, "title"]))
    check titles == @["Home", "About", "Contact"]

  test "access frontmatter tags":
    let tags = arena[arena[arena[ctx, "page"], "frontmatter"], "tags"]
    check arena.len(tags) == 2
    check arena.getStr(arena[tags, 0]) == "test"
    check arena.getStr(arena[tags, 1]) == "example"

  test "missing key returns InvalidNodeId":
    check arena[ctx, "nonexistent"] == InvalidNodeId

suite "Integration - Mutation":
  test "build context incrementally":
    var arena = initArena()
    let root = arena.newObj()
    let site = arena.newObj()
    arena.set(site, "title", arena.newStr("My Site"))
    arena.set(root, "site", site)

    # Add pages array
    let pages = arena.newArr()
    let page1 = arena.newObj()
    arena.set(page1, "title", arena.newStr("Hello World"))
    arena.set(page1, "draft", arena.newBool(false))
    arena.add(pages, page1)
    arena.set(site, "pages", pages)

    # Verify the structure
    check arena.getStr(arena[arena[root, "site"], "title"]) == "My Site"
    let gotPages = arena[arena[root, "site"], "pages"]
    check arena.len(gotPages) == 1
    check arena.getStr(arena[arena[gotPages, 0], "title"]) == "Hello World"

  test "mutate string value in context":
    var arena = initArena()
    let root = arena.newObj()
    let titleId = arena.newStr("Draft Title")
    arena.set(root, "title", titleId)
    check arena.getStr(arena[root, "title"]) == "Draft Title"

    # Mutate the string
    arena.setStr(titleId, "Final Title")
    check arena.getStr(arena[root, "title"]) == "Final Title"

  test "overwrite object key with different type":
    var arena = initArena()
    let obj = arena.newObj()
    arena.set(obj, "value", arena.newStr("string"))
    check arena.kind(arena[obj, "value"]) == nkString
    arena.set(obj, "value", arena.newInt(42))
    check arena.kind(arena[obj, "value"]) == nkInt
    check arena.getInt(arena[obj, "value"]) == 42

suite "Integration - Stress Tests":
  test "large flat object (100 keys)":
    var arena = initArena()
    let obj = arena.newObj()
    for i in 0 ..< 100:
      arena.set(obj, "key_" & $i, arena.newInt(int64(i)))
    check arena.len(obj) == 100
    # Verify all keys accessible
    for i in 0 ..< 100:
      check arena.getInt(arena[obj, "key_" & $i]) == int64(i)

  test "deeply nested structure (100 levels)":
    var arena = initArena()
    var current = arena.newStr("leaf")
    for i in countdown(99, 0):
      let wrapper = arena.newObj()
      arena.set(wrapper, "level_" & $i, current)
      current = wrapper
    # Traverse all the way down
    var node = current
    for i in 0 ..< 100:
      node = arena[node, "level_" & $i]
    check arena.getStr(node) == "leaf"

  test "large array (10000 elements)":
    var arena = initArena()
    let arr = arena.newArr()
    for i in 0 ..< 10000:
      arena.add(arr, arena.newInt(int64(i)))
    check arena.len(arr) == 10000
    check arena.getInt(arena[arr, 0]) == 0
    check arena.getInt(arena[arr, 5000]) == 5000
    check arena.getInt(arena[arr, 9999]) == 9999

  test "many small objects (typical page metadata)":
    var arena = initArena()
    let pages = arena.newArr()
    for i in 0 ..< 500:
      let page = arena.newObj()
      arena.set(page, "title", arena.newStr("Page " & $i))
      arena.set(page, "slug", arena.newStr("page-" & $i))
      arena.set(page, "order", arena.newInt(int64(i)))
      arena.set(page, "draft", arena.newBool(i mod 3 == 0))
      let tags = arena.newArr()
      arena.add(tags, arena.newStr("tag-" & $(i mod 5)))
      arena.add(tags, arena.newStr("tag-" & $(i mod 7)))
      arena.set(page, "tags", tags)
      arena.add(pages, page)
    check arena.len(pages) == 500
    # Spot check
    let p42 = arena[pages, 42]
    check arena.getStr(arena[p42, "title"]) == "Page 42"
    check arena.getStr(arena[p42, "slug"]) == "page-42"
    check arena.getInt(arena[p42, "order"]) == 42
    check arena.getBool(arena[p42, "draft"]) == true  # 42 mod 3 == 0
    let tags42 = arena[p42, "tags"]
    check arena.getStr(arena[tags42, 0]) == "tag-2"  # 42 mod 5
    check arena.getStr(arena[tags42, 1]) == "tag-0"  # 42 mod 7

  test "arena node count reflects all created nodes":
    var arena = initArena()
    check arena.nodeCount() == 0
    let obj = arena.newObj()
    arena.set(obj, "a", arena.newInt(1))
    arena.set(obj, "b", arena.newStr("hello"))
    let arr = arena.newArr()
    arena.add(arr, arena.newBool(true))
    arena.set(obj, "c", arr)
    # obj + int(1) + str("hello") + arr + bool(true) = 5 nodes
    check arena.nodeCount() == 5

  test "multiple arenas are independent":
    var a1 = initArena()
    var a2 = initArena()
    let id1 = a1.newStr("arena1")
    let id2 = a2.newStr("arena2")
    # Same NodeId value (both are 0), different arenas
    check uint32(id1) == uint32(id2)
    check a1.getStr(id1) == "arena1"
    check a2.getStr(id2) == "arena2"
