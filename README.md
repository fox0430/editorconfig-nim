# editorconfig-nim

A Nim library for parsing [EditorConfig](https://editorconfig.org/) files.

## Requires

- Nim >= 2.0.0

## Install

```sh
nimble install editorconfig
```

## Usage

```nim
import pkg/editorconfig

let props = getProperties("/path/to/file.nim")
```

## License

MIT
