import std/[unittest, os, tables]

import ../editor_config

suite "getProperties integration":
  var tmpDir: string

  setup:
    tmpDir = getTempDir() / "editorconfig_integration_test"
    removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  test "basic property lookup":
    let ecContent = """
root = true

[*.nim]
indent_style = space
indent_size = 2
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props["indent_style"] == "space"
    check props["indent_size"] == "2"

  test "no match returns empty":
    let ecContent = """
root = true

[*.py]
indent_style = space
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props.len == 0

  test "nearer file overrides farther":
    createDir(tmpDir / "project" / "sub")

    writeFile(
      tmpDir / "project" / ".editorconfig",
      """
root = true

[*.nim]
indent_style = tab
indent_size = 4
""",
    )
    writeFile(
      tmpDir / "project" / "sub" / ".editorconfig",
      """
[*.nim]
indent_size = 2
""",
    )
    writeFile(tmpDir / "project" / "sub" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "sub" / "main.nim")
    check props["indent_style"] == "tab" # from parent
    check props["indent_size"] == "2" # overridden by child

  test "root = true stops upward search":
    createDir(tmpDir / "project" / "sub")

    writeFile(
      tmpDir / "project" / ".editorconfig",
      """
[*.nim]
charset = utf-8
""",
    )
    writeFile(
      tmpDir / "project" / "sub" / ".editorconfig",
      """
root = true

[*.nim]
indent_style = space
""",
    )
    writeFile(tmpDir / "project" / "sub" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "sub" / "main.nim")
    check props["indent_style"] == "space"
    check "charset" notin props # parent not reached

  test "unset removes property":
    createDir(tmpDir / "project" / "sub")

    writeFile(
      tmpDir / "project" / ".editorconfig",
      """
root = true

[*.nim]
indent_style = space
indent_size = 2
""",
    )
    writeFile(
      tmpDir / "project" / "sub" / ".editorconfig",
      """
[*.nim]
indent_size = unset
""",
    )
    writeFile(tmpDir / "project" / "sub" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "sub" / "main.nim")
    check props["indent_style"] == "space"
    check "indent_size" notin props

  test "double star glob matches subdirectories":
    let ecContent = """
root = true

[src/**.nim]
indent_style = space
"""
    createDir(tmpDir / "project" / "src" / "sub")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "src" / "sub" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "src" / "sub" / "main.nim")
    check props["indent_style"] == "space"

  test "alternation glob":
    let ecContent = """
root = true

[{*.py,*.js}]
indent_style = space
indent_size = 4
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.py", "")
    writeFile(tmpDir / "project" / "main.js", "")
    writeFile(tmpDir / "project" / "main.nim", "")

    check getProperties(tmpDir / "project" / "main.py")["indent_style"] == "space"
    check getProperties(tmpDir / "project" / "main.js")["indent_style"] == "space"
    check getProperties(tmpDir / "project" / "main.nim").len == 0

  test "later section overrides earlier in same file":
    let ecContent = """
root = true

[*.nim]
indent_style = tab
indent_size = 4

[*.nim]
indent_style = space
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props["indent_style"] == "space"
    check props["indent_size"] == "4"

  test "known property values are lowercased":
    let ecContent = """
root = true

[*.nim]
indent_style = Space
end_of_line = CRLF
charset = UTF-8
trim_trailing_whitespace = True
insert_final_newline = False
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props["indent_style"] == "space"
    check props["end_of_line"] == "crlf"
    check props["charset"] == "utf-8"
    check props["trim_trailing_whitespace"] == "true"
    check props["insert_final_newline"] == "false"

  test "tab_width defaults to indent_size":
    let ecContent = """
root = true

[*.nim]
indent_size = 4
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props["indent_size"] == "4"
    check props["tab_width"] == "4"

  test "indent_size = tab resolves to tab_width":
    let ecContent = """
root = true

[*.nim]
indent_size = tab
tab_width = 8
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props["indent_size"] == "8"
    check props["tab_width"] == "8"

  test "indent_style = tab auto-sets indent_size":
    let ecContent = """
root = true

[*.nim]
indent_style = tab
tab_width = 4
"""
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "main.nim", "")

    let props = getProperties(tmpDir / "project" / "main.nim")
    check props["indent_size"] == "4"
    check props["tab_width"] == "4"

  test "no editorconfig file returns empty":
    createDir(tmpDir / "project")
    writeFile(tmpDir / "project" / "main.nim", "")

    # This may not be truly empty if parent dirs have .editorconfig,
    # but within our temp dir there should be none with root=true above.
    # The test at least ensures no crash.
    discard getProperties(tmpDir / "project" / "main.nim")

  test "leading slash pattern matches at root only":
    let ecContent = """
root = true

[/src/*.nim]
indent_style = space
"""
    createDir(tmpDir / "project" / "src" / "sub")
    writeFile(tmpDir / "project" / ".editorconfig", ecContent)
    writeFile(tmpDir / "project" / "src" / "main.nim", "")
    writeFile(tmpDir / "project" / "src" / "sub" / "main.nim", "")

    let props1 = getProperties(tmpDir / "project" / "src" / "main.nim")
    check props1["indent_style"] == "space"
    # Should not match subdirectory
    let props2 = getProperties(tmpDir / "project" / "src" / "sub" / "main.nim")
    check "indent_style" notin props2

  test "directory with glob metacharacters":
    let dirName = "{special}[dir]"
    createDir(tmpDir / dirName)
    let ecContent = """
root = true

[*.nim]
indent_style = tab
"""
    writeFile(tmpDir / dirName / ".editorconfig", ecContent)
    writeFile(tmpDir / dirName / "main.nim", "")

    let props = getProperties(tmpDir / dirName / "main.nim")
    check props["indent_style"] == "tab"
