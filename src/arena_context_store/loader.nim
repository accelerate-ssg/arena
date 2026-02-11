## Loader registry for the arena context store.
##
## Loaders are registered by format name and file extensions.
## The `load` proc dispatches by file extension; `loadFormat` dispatches
## by explicit format name.

import std/strutils
import types

proc registerLoader*(arena: var Arena, format: string, extensions: seq[string],
                     loader: LoadProc) =
  ## Register a loader for the given format and file extensions.
  arena.loaders.add(LoaderEntry(
    format: format,
    extensions: extensions,
    load: loader,
  ))

proc load*(arena: var Arena, path: string, data: string): NodeId =
  ## Load data from a file path by dispatching to the appropriate loader
  ## based on the file extension.
  let pathLower = path.toLowerAscii()
  for entry in arena.loaders:
    for ext in entry.extensions:
      if pathLower.endsWith(ext.toLowerAscii()):
        return entry.load(arena, data, path)
  raise newException(ValueError, "No loader registered for extension of: " & path)

proc loadFormat*(arena: var Arena, path: string, data: string,
                 format: string): NodeId =
  ## Load data using an explicit format name.
  for entry in arena.loaders:
    if entry.format == format:
      return entry.load(arena, data, path)
  raise newException(ValueError, "No loader registered for format: " & format)
