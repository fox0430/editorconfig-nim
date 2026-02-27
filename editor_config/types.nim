import std/tables

import pkg/regex

type
  NumericRange* = tuple[lo: int, hi: int, leadingZero: bool]

  GlobRegex* = object
    pattern*: Regex2
    numericRanges*: seq[NumericRange]
    valid*: bool

  EditorConfigSection* = object
    glob*: string
    compiledGlob*: GlobRegex
    pairs*: OrderedTable[string, string]

  EditorConfigFile* = object
    root*: bool
    sections*: seq[EditorConfigSection]
    directory*: string
