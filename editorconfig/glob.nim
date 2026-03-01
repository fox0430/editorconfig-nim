import std/[strutils, strformat]

import pkg/regex

import types

proc bracesAreBalanced(pattern: string): bool =
  var
    depth = 0
    i = 0
    inBracket = false
  let n = pattern.len
  while i < n:
    let ch = pattern[i]
    if ch == '\\':
      # Skip escaped character
      i += 2
      continue
    if inBracket:
      if ch == ']':
        inBracket = false
      inc i
      continue
    if ch == '[':
      inBracket = true
    elif ch == '{':
      inc depth
    elif ch == '}':
      dec depth
      if depth < 0:
        return false
    inc i
  return depth == 0

proc globToRegexStr*(pattern: string, numericRanges: var seq[NumericRange]): string =
  ## Convert an EditorConfig glob pattern to a regex string and collect
  ## numeric-range constraints.
  var
    i = 0
    inBracket = false
  let
    n = pattern.len
    balanced = bracesAreBalanced(pattern)

  while i < n:
    let c = pattern[i]

    if inBracket:
      case c
      of ']':
        result.add ']'
        inBracket = false
      of '\\':
        result.add '\\'
        if i + 1 < n:
          inc i
          result.add pattern[i]
      of '/':
        # `/` inside [...] should never match
        discard
      else:
        result.add c
      inc i
      continue

    case c
    of '*':
      if i + 1 < n and pattern[i + 1] == '*':
        i += 2
        if i < n and pattern[i] == '/':
          # `**/` matches zero or more directory components
          result.add "(?:.*/)?"
          inc i
        else:
          # `**` at end or not followed by `/`
          result.add ".*"
      else:
        result.add "[^/]*"
        inc i
    of '?':
      result.add "[^/]"
      inc i
    of '[':
      # Look ahead for closing ']'
      var j = i + 1
      if j < n and pattern[j] == '!':
        inc j
      elif j < n and pattern[j] == ']':
        # Empty bracket -- treat `[` as literal
        result.add "\\["
        inc i
        continue
      var hasClose = false
      var k = j
      while k < n:
        if pattern[k] == ']':
          hasClose = true
          break
        inc k
      if not hasClose:
        # No closing ']' found -- treat `[` as literal
        result.add "\\["
        inc i
        continue
      # Valid bracket expression
      j = i + 1
      if j < n and pattern[j] == '!':
        result.add "[^"
        inc j
      else:
        result.add '['
      inBracket = true
      i = j
    of '{':
      if not balanced:
        result.add "\\{"
        inc i
        continue

      # Collect inner content up to matching '}'
      var j = i + 1
      var inner = ""
      var depth = 1
      var inBrk = false
      while j < n and depth > 0:
        let ch = pattern[j]
        if ch == '\\' and j + 1 < n:
          # Escaped character -- add both and skip
          if depth > 0:
            inner.add ch
            inner.add pattern[j + 1]
          j += 2
          continue
        if inBrk:
          if ch == ']':
            inBrk = false
          if depth > 0:
            inner.add ch
          inc j
          continue
        if ch == '[':
          inBrk = true
        elif ch == '{':
          inc depth
        elif ch == '}':
          dec depth
        if depth > 0:
          inner.add ch
        inc j

      if depth != 0:
        result.add "\\{"
        inc i
        continue

      let dotdot = inner.find("..")
      if dotdot >= 0:
        # Potential numeric range {n1..n2}
        let leftStr = inner[0 ..< dotdot]
        let rightStr = inner[dotdot + 2 .. ^1]
        try:
          let lo = parseInt(leftStr)
          let hi = parseInt(rightStr)
          let hasLeadingZero =
            (leftStr.len > 1 and leftStr[0] == '0') or
            (leftStr.len > 2 and leftStr[0] == '-' and leftStr[1] == '0') or
            (rightStr.len > 1 and rightStr[0] == '0') or
            (rightStr.len > 2 and rightStr[0] == '-' and rightStr[1] == '0')
          if hasLeadingZero:
            # Compute digit width excluding sign
            let leftDigitLen =
              if leftStr.len > 0 and leftStr[0] == '-':
                leftStr.len - 1
              else:
                leftStr.len
            let rightDigitLen =
              if rightStr.len > 0 and rightStr[0] == '-':
                rightStr.len - 1
              else:
                rightStr.len
            let minWidth = max(leftDigitLen, rightDigitLen)
            if lo < 0:
              result.add &"(-?\\d{{{minWidth}}})"
            else:
              result.add &"(\\d{{{minWidth}}})"
          else:
            result.add "(-?\\d+)"
          if lo <= hi:
            numericRanges.add (lo: lo, hi: hi, leadingZero: hasLeadingZero)
          else:
            numericRanges.add (lo: hi, hi: lo, leadingZero: hasLeadingZero)
        except ValueError:
          # Not a valid range -- treat as alternation
          result.add "(?:"
          result.add globToRegexStr(inner, numericRanges)
          result.add ')'
      else:
        # Alternation {a,b,c}
        result.add "(?:"
        var altStart = 0
        var altDepth = 0
        var altBrk = false
        var k = 0
        while k < inner.len:
          let ch = inner[k]
          if ch == '\\' and k + 1 < inner.len:
            # Skip escaped character
            k += 2
            continue
          if altBrk:
            if ch == ']':
              altBrk = false
            inc k
            continue
          if ch == '[':
            altBrk = true
          elif ch == '{':
            inc altDepth
          elif ch == '}':
            dec altDepth
          elif ch == ',' and altDepth == 0:
            let part = inner[altStart ..< k]
            result.add globToRegexStr(part, numericRanges)
            result.add '|'
            altStart = k + 1
          inc k
        result.add globToRegexStr(inner[altStart .. ^1], numericRanges)
        result.add ')'

      i = j
    of '}':
      if not balanced:
        result.add "\\}"
      else:
        result.add '}'
      inc i
    of '\\':
      result.add '\\'
      inc i
      if i < n:
        result.add pattern[i]
        inc i
    of '.', '(', ')', '+', '|', '^', '$':
      result.add '\\'
      result.add c
      inc i
    else:
      result.add c
      inc i

proc compileGlob*(pattern: string): GlobRegex =
  ## Compile an EditorConfig glob pattern into a GlobRegex.
  ## Returns a GlobRegex with ``valid = false`` if the pattern is invalid.
  var numericRanges: seq[NumericRange]
  let regexStr = globToRegexStr(pattern, numericRanges)
  try:
    result =
      GlobRegex(pattern: re2(regexStr), numericRanges: numericRanges, valid: true)
  except RegexError:
    result.valid = false

proc matchGlob*(globRegex: GlobRegex, path: string): bool =
  ## Test whether ``path`` matches the compiled glob pattern, including
  ## numeric-range constraints.
  if not globRegex.valid:
    return false
  var m: RegexMatch2
  if not match(path, globRegex.pattern, m):
    return false

  for idx, rng in globRegex.numericRanges:
    let groupSlice = m.group(idx)
    let s = path[groupSlice]
    if s.len == 0:
      return false
    # Reject values with leading zeros unless the pattern itself uses them
    if not rng.leadingZero:
      if s.len > 1 and s[0] == '0':
        return false
      if s.len > 1 and s[0] == '-' and s.len > 2 and s[1] == '0':
        return false
    try:
      let val = parseInt(s)
      if val < rng.lo or val > rng.hi:
        return false
    except ValueError:
      return false

  return true
