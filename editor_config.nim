import std/[os, tables, strutils]

import editor_config/[types, parser, glob]

proc prepareSections(ec: var EditorConfigFile) =
  ## Pre-compile glob patterns for all sections in an EditorConfig file.
  for section in ec.sections.mitems:
    var pattern = section.glob
    if pattern.startsWith("/"):
      pattern = pattern[1 .. ^1]
    elif not pattern.contains('/'):
      pattern = "**/" & pattern
    section.compiledGlob = compileGlob(pattern)

proc getProperties*(filePath: string): Table[string, string] =
  ## Return the merged EditorConfig properties for ``filePath``.
  ##
  ## Walks parent directories from ``filePath`` upward, collecting
  ## ``.editorconfig`` files until one with ``root = true`` is found or the
  ## filesystem root is reached.  Properties from nearer files / later
  ## sections override those from farther ones.
  let absPath = absolutePath(filePath)

  # Collect .editorconfig files from nearest to farthest
  var configs: seq[EditorConfigFile]
  var dir = parentDir(absPath)
  var prevDir = ""

  while dir != prevDir: # Stop at filesystem root (dir stops changing)
    let ecPath = dir / ".editorconfig"
    if fileExists(ecPath):
      var ec = parseEditorConfig(ecPath)
      prepareSections(ec)
      configs.add ec
      if ec.root:
        break
    prevDir = dir
    dir = parentDir(dir)

  # Process farthest-first so that nearer files override
  for i in countdown(configs.high, 0):
    let ec = configs[i]
    let relPath = relativePath(absPath, ec.directory)

    for section in ec.sections:
      if matchGlob(section.compiledGlob, relPath):
        for key, value in section.pairs:
          let lowerVal = value.toLowerAscii()
          if lowerVal == "unset":
            result.del(key)
          else:
            result[key] = value

  # Post-processing: normalize and apply spec defaults

  # Step 1: Lowercase values for known case-insensitive properties
  const LowercaseValueProps = [
    "indent_style", "indent_size", "end_of_line", "charset", "trim_trailing_whitespace",
    "insert_final_newline",
  ]
  for prop in LowercaseValueProps:
    if prop in result:
      result[prop] = result[prop].toLowerAscii()

  # Step 2: tab_width defaults to indent_size when indent_size is numeric
  if "indent_size" in result and "tab_width" notin result:
    try:
      discard parseInt(result["indent_size"])
      result["tab_width"] = result["indent_size"]
    except ValueError:
      discard

  # Step 3: Resolve indent_size = "tab"
  if "indent_style" in result and result["indent_style"] == "tab" and
      "indent_size" notin result:
    result["indent_size"] = "tab"
  if "indent_size" in result and result["indent_size"] == "tab" and "tab_width" in result:
    result["indent_size"] = result["tab_width"]
