import std/[unittest, strutils]

import ../editor_config/[types, glob]

suite "globToRegexStr":
  test "simple star":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("*.txt", ranges)
    check s == "[^/]*\\.txt"
    check ranges.len == 0

  test "double star":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("**/*.txt", ranges)
    check ".*" in s

  test "question mark":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("?.txt", ranges)
    check "[^/]" in s

  test "bracket expression":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("[abc].txt", ranges)
    check "[abc]" in s

  test "negated bracket":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("[!abc].txt", ranges)
    check "[^abc]" in s

  test "alternation":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("{a,b,c}", ranges)
    check "(?:" in s
    check "a|b|c" in s

  test "numeric range":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("{1..10}", ranges)
    check ranges.len == 1
    check ranges[0].lo == 1
    check ranges[0].hi == 10

  test "numeric range reversed":
    var ranges: seq[NumericRange]
    discard globToRegexStr("{10..1}", ranges)
    check ranges.len == 1
    check ranges[0].lo == 1
    check ranges[0].hi == 10

  test "numeric range with leading zeros":
    var ranges: seq[NumericRange]
    discard globToRegexStr("{01..10}", ranges)
    check ranges.len == 1
    check ranges[0].lo == 1
    check ranges[0].hi == 10
    check ranges[0].leadingZero == true

  test "numeric range without leading zeros":
    var ranges: seq[NumericRange]
    discard globToRegexStr("{1..10}", ranges)
    check ranges.len == 1
    check ranges[0].leadingZero == false

  test "negative numeric range with leading zeros":
    var ranges: seq[NumericRange]
    discard globToRegexStr("{-01..10}", ranges)
    check ranges.len == 1
    check ranges[0].leadingZero == true

  test "unclosed bracket is literal":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("[abc", ranges)
    check "\\[" in s

  test "escaped brace not counted in balance":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("\\{a,b}", ranges)
    # `\{` is escaped, so braces are unbalanced -- `}` is literal
    check "\\{" in s
    check "\\}" in s

  test "brace inside bracket not counted in balance":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("[{].txt", ranges)
    # `{` inside bracket is literal, not a brace opener
    check "[{]" in s

  test "unbalanced brace is literal":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("{a,b", ranges)
    check "\\{" in s

  test "escaped closing brace inside braces":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("{a\\},b}", ranges)
    # `\}` is escaped, so the real close is the final `}`
    check "(?:" in s
    check "a\\}" in s
    check "|" in s

  test "bracket containing closing brace inside braces":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("{[}],a}", ranges)
    # `}` inside `[}]` is not a brace closer
    check "(?:" in s
    check "|" in s

  test "non-leading-zero numeric range regex excludes plus":
    var ranges: seq[NumericRange]
    let s = globToRegexStr("{1..5}", ranges)
    check "+-" notin s

suite "compileGlob and matchGlob":
  test "star matches filename":
    let g = compileGlob("*.txt")
    check matchGlob(g, "foo.txt")
    check matchGlob(g, "bar.txt")
    check not matchGlob(g, "foo.rs")
    check not matchGlob(g, "dir/foo.txt")

  test "double star matches across directories":
    let g = compileGlob("**/*.txt")
    check matchGlob(g, "foo.txt")
    check matchGlob(g, "a/foo.txt")
    check matchGlob(g, "a/b/c/foo.txt")
    check not matchGlob(g, "a/b/foo.rs")

  test "question mark matches single char":
    let g = compileGlob("?.txt")
    check matchGlob(g, "a.txt")
    check not matchGlob(g, "ab.txt")
    check not matchGlob(g, ".txt")

  test "bracket expression":
    let g = compileGlob("[abc].txt")
    check matchGlob(g, "a.txt")
    check matchGlob(g, "b.txt")
    check not matchGlob(g, "d.txt")

  test "negated bracket":
    let g = compileGlob("[!abc].txt")
    check not matchGlob(g, "a.txt")
    check matchGlob(g, "d.txt")

  test "alternation":
    let g = compileGlob("{*.py,*.js}")
    check matchGlob(g, "test.py")
    check matchGlob(g, "test.js")
    check not matchGlob(g, "test.rb")

  test "numeric range":
    let g = compileGlob("file{1..5}.txt")
    check matchGlob(g, "file1.txt")
    check matchGlob(g, "file3.txt")
    check matchGlob(g, "file5.txt")
    check not matchGlob(g, "file0.txt")
    check not matchGlob(g, "file6.txt")

  test "numeric range rejects leading zeros":
    let g = compileGlob("file{1..10}.txt")
    check matchGlob(g, "file1.txt")
    check matchGlob(g, "file10.txt")
    check not matchGlob(g, "file01.txt")

  test "negative numeric range":
    let g = compileGlob("file{-5..5}.txt")
    check matchGlob(g, "file-5.txt")
    check matchGlob(g, "file0.txt")
    check matchGlob(g, "file5.txt")
    check not matchGlob(g, "file-6.txt")
    check not matchGlob(g, "file6.txt")

  test "leading zero numeric range matches zero-padded values":
    let g = compileGlob("file{01..10}.txt")
    check matchGlob(g, "file01.txt")
    check matchGlob(g, "file05.txt")
    check matchGlob(g, "file10.txt")
    check not matchGlob(g, "file00.txt")
    check not matchGlob(g, "file11.txt")
    check not matchGlob(g, "file1.txt") # not zero-padded

  test "star does not match slash":
    let g = compileGlob("*.txt")
    check not matchGlob(g, "dir/file.txt")

  test "question mark does not match slash":
    let g = compileGlob("?/a.txt")
    check matchGlob(g, "x/a.txt")
    check not matchGlob(g, "xy/a.txt")

  test "pattern with path separator":
    let g = compileGlob("src/*.nim")
    check matchGlob(g, "src/foo.nim")
    check not matchGlob(g, "src/sub/foo.nim")

  test "double star with trailing slash":
    let g = compileGlob("src/**/")
    check matchGlob(g, "src/a/")
    check matchGlob(g, "src/a/b/")

  test "escaped special characters":
    let g = compileGlob("file\\.txt")
    check matchGlob(g, "file.txt")

  test "dot in pattern is literal":
    let g = compileGlob("file.txt")
    check matchGlob(g, "file.txt")
    check not matchGlob(g, "fileatxt") # '.' should not match arbitrary char

  test "leading zero rejects extra-padded values":
    let g = compileGlob("file{01..10}.txt")
    check not matchGlob(g, "file001.txt") # 3 digits, pattern expects 2

  test "negative leading zero numeric range":
    let g = compileGlob("file{-01..10}.txt")
    check matchGlob(g, "file10.txt")
    check matchGlob(g, "file00.txt")
    check matchGlob(g, "file-01.txt")
    check not matchGlob(g, "file0.txt") # not zero-padded
    check not matchGlob(g, "file-1.txt") # not zero-padded

  test "unclosed bracket matches literally":
    let g = compileGlob("[abc")
    check matchGlob(g, "[abc")
    check not matchGlob(g, "a")

  test "escaped brace is literal":
    let g = compileGlob("\\{a\\}")
    check matchGlob(g, "{a}")
    check not matchGlob(g, "a")

  test "single open bracket is literal":
    let g = compileGlob("[")
    check matchGlob(g, "[")
    check not matchGlob(g, "a")

  test "empty bracket is literal":
    let g = compileGlob("[].txt")
    check matchGlob(g, "[].txt")
    check not matchGlob(g, "a.txt")

  test "escaped closing brace in alternation":
    let g = compileGlob("{a\\},b}")
    check matchGlob(g, "a}")
    check matchGlob(g, "b")
    check not matchGlob(g, "a")

  test "bracket with brace in alternation":
    let g = compileGlob("{[}],a}")
    check matchGlob(g, "}")
    check matchGlob(g, "a")
    check not matchGlob(g, "[")

  test "escaped comma in alternation":
    let g = compileGlob("{a\\,,b}")
    check matchGlob(g, "a,")
    check matchGlob(g, "b")
    check not matchGlob(g, "a")

  test "bracket with comma in alternation":
    let g = compileGlob("{[,]a,b}")
    check matchGlob(g, ",a")
    check matchGlob(g, "b")
    check not matchGlob(g, "a")

  test "plus prefix does not match numeric range":
    let g = compileGlob("file{1..5}.txt")
    check matchGlob(g, "file3.txt")
    check not matchGlob(g, "file+3.txt")
