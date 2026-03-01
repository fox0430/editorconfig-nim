import std/[os, strutils, tables]

import types

const Bom = "\xEF\xBB\xBF"

proc parseEditorConfig*(path: string): EditorConfigFile =
  ## Parse an ``.editorconfig`` file at ``path``.
  ## Returns a default (root=false, empty sections) on read failure.
  result.directory = parentDir(path)
  result.root = false

  var content: string
  try:
    content = readFile(path)
  except IOError, OSError:
    return

  # Strip UTF-8 BOM
  if content.startsWith(Bom):
    content = content[Bom.len .. ^1]

  var
    currentSection: EditorConfigSection
    inSection = false
    inPreamble = true

  for rawLine in content.splitLines():
    let line = rawLine.strip()

    # Skip empty lines
    if line.len == 0:
      continue

    # Comment lines: starts with '#' or ';'
    if line[0] == '#' or line[0] == ';':
      continue

    # Section header
    if line[0] == '[':
      # Save previous section if any
      if inSection:
        result.sections.add currentSection

      let closingBracket = line.rfind(']')
      if closingBracket > 0:
        let glob = line[1 ..< closingBracket]
        currentSection =
          EditorConfigSection(glob: glob, pairs: initOrderedTable[string, string]())
      else:
        # Malformed section header -- treat as glob with everything after '['
        currentSection = EditorConfigSection(
          glob: line[1 .. ^1], pairs: initOrderedTable[string, string]()
        )

      inSection = true
      inPreamble = false
      continue

    # Key = value
    let eqPos = line.find('=')
    if eqPos >= 0:
      let key = line[0 ..< eqPos].strip().toLowerAscii()
      let value = line[eqPos + 1 .. ^1].strip()

      if inPreamble:
        # Only `root = true` is meaningful in the preamble
        if key == "root" and value.toLowerAscii() == "true":
          result.root = true
      elif inSection:
        currentSection.pairs[key] = value

  # Don't forget the last section
  if inSection:
    result.sections.add currentSection
