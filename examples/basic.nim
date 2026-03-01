import std/[os, tables]

import pkg/editorconfig

# Resolve a .nim file path relative to this example's directory,
# so the bundled .editorconfig is picked up.
let target = currentSourcePath().parentDir() / "hello.nim"

echo "\nTarget: " & target & '\n'

let props = getProperties(target)

if props.len == 0:
  echo "No properties found."
else:
  for key, value in props:
    echo key, " = ", value
