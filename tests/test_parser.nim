import std/[unittest, os, tables]

import ../editor_config/[types, parser]

suite "parseEditorConfig":
  var tmpDir: string

  setup:
    tmpDir = getTempDir() / "editorconfig_test"
    removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  proc writeTempFile(dir, content: string): string =
    result = dir / ".editorconfig"
    writeFile(result, content)

  test "basic file":
    let path = writeTempFile(
      tmpDir,
      """
root = true

[*.nim]
indent_style = space
indent_size = 2
""",
    )
    let ec = parseEditorConfig(path)
    check ec.root == true
    check ec.sections.len == 1
    check ec.sections[0].glob == "*.nim"
    check ec.sections[0].pairs["indent_style"] == "space"
    check ec.sections[0].pairs["indent_size"] == "2"

  test "root = false by default":
    let path = writeTempFile(
      tmpDir,
      """
[*.py]
indent_style = space
""",
    )
    let ec = parseEditorConfig(path)
    check ec.root == false

  test "root = true case insensitive":
    let path = writeTempFile(tmpDir, "root = True\n")
    let ec = parseEditorConfig(path)
    check ec.root == true

  test "comment lines":
    let path = writeTempFile(
      tmpDir,
      """
# This is a comment
; This is also a comment
[*.nim]
indent_style = space
# Another comment
""",
    )
    let ec = parseEditorConfig(path)
    check ec.sections.len == 1
    check ec.sections[0].pairs.len == 1

  test "multiple sections":
    let path = writeTempFile(
      tmpDir,
      """
[*.py]
indent_style = space
indent_size = 4

[*.js]
indent_style = space
indent_size = 2

[Makefile]
indent_style = tab
""",
    )
    let ec = parseEditorConfig(path)
    check ec.sections.len == 3
    check ec.sections[0].glob == "*.py"
    check ec.sections[1].glob == "*.js"
    check ec.sections[2].glob == "Makefile"

  test "keys are lowercased":
    let path = writeTempFile(
      tmpDir,
      """
[*.nim]
Indent_Style = space
INDENT_SIZE = 2
""",
    )
    let ec = parseEditorConfig(path)
    check "indent_style" in ec.sections[0].pairs
    check "indent_size" in ec.sections[0].pairs

  test "values preserve case":
    let path = writeTempFile(
      tmpDir,
      """
[*.nim]
charset = UTF-8
""",
    )
    let ec = parseEditorConfig(path)
    check ec.sections[0].pairs["charset"] == "UTF-8"

  test "whitespace around equals":
    let path = writeTempFile(
      tmpDir,
      """
[*.nim]
indent_style  =  space
indent_size=2
""",
    )
    let ec = parseEditorConfig(path)
    check ec.sections[0].pairs["indent_style"] == "space"
    check ec.sections[0].pairs["indent_size"] == "2"

  test "UTF-8 BOM":
    let path =
      writeTempFile(tmpDir, "\xEF\xBB\xBFroot = true\n[*.nim]\nindent_style = space\n")
    let ec = parseEditorConfig(path)
    check ec.root == true
    check ec.sections.len == 1

  test "CRLF line endings":
    let path =
      writeTempFile(tmpDir, "[*.nim]\r\nindent_style = space\r\nindent_size = 2\r\n")
    let ec = parseEditorConfig(path)
    check ec.sections.len == 1
    check ec.sections[0].pairs["indent_style"] == "space"
    check ec.sections[0].pairs["indent_size"] == "2"

  test "empty file":
    let path = writeTempFile(tmpDir, "")
    let ec = parseEditorConfig(path)
    check ec.root == false
    check ec.sections.len == 0

  test "nonexistent file returns defaults":
    let ec = parseEditorConfig("/nonexistent/path/.editorconfig")
    check ec.root == false
    check ec.sections.len == 0

  test "section with bracket in glob uses rfind":
    let path = writeTempFile(
      tmpDir,
      """
[{*.txt]}]
indent_style = space
""",
    )
    let ec = parseEditorConfig(path)
    # rfind(']') should capture up to the last ']'
    check ec.sections.len == 1

  test "root in section is not treated as root":
    let path = writeTempFile(
      tmpDir,
      """
[*.nim]
root = true
indent_style = space
""",
    )
    let ec = parseEditorConfig(path)
    check ec.root == false
    check "root" in ec.sections[0].pairs

  test "preamble key-value pairs other than root are ignored":
    let path = writeTempFile(
      tmpDir,
      """
indent_style = space
[*.nim]
indent_size = 2
""",
    )
    let ec = parseEditorConfig(path)
    check ec.sections.len == 1
    check ec.sections[0].pairs.len == 1

  test "directory is set":
    let path = writeTempFile(
      tmpDir,
      """
[*.nim]
indent_style = space
""",
    )
    let ec = parseEditorConfig(path)
    check ec.directory == parentDir(path)
