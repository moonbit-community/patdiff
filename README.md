# patdiff.mbt

A MoonBit port of [patdiff](https://github.com/janestreet/patdiff), Jane Street's
file diff using the patience diff algorithm. It highlights the words that changed
within lines, and renders to the terminal (ANSI or plain ASCII), to HTML, and side
by side.

The port follows upstream at `v0.18~preview.130.106+341`, together with the
`patience_diff` library it depends on.

## Command line

`patdiff` takes upstream's flags. It builds for native and for Wasm. To run the
published Wasm build without installing anything:

```bash
moonx moonbit-community/patdiff old.txt new.txt
```

To install the native build:

```bash
moon install moonbit-community/patdiff
```

Before 0.3.0 the executable was the package `moonbit-community/patdiff/cmd/patdiff`.

Or, from a checkout:

```bash
moon build --release
```

```bash
_build/native/release/build/patdiff.exe old.txt new.txt
```

As upstream it compares two files or two directories, or reads diff-like text from
stdin when given no files. Flags can be abbreviated to any unique prefix. `~/.patdiff`
is read as a configuration file if it exists; `-make-config FILE` writes a sample one.
The exit code is 0 for no differences and 1 for differences or an error.

Useful flags: `-html`, `-ascii`, `-side-by-side wrap`, `-find-moves`, `-unrefined`,
`-keep-whitespace`, `-context NUM`, `-float-tolerance 1%`, `-location-style omake`.
See `-help` for all of them.

`scripts/patdiff-git-wrapper` is upstream's wrapper for using patdiff as git's
external diff.

## Library

The `kernel` package is pure MoonBit, so it isn't tied to the native backend:

```moonbit nocheck
let diff : Bytes = @kernel.patdiff(
  prev=@kernel.DiffInput::of_string("old", "Foo bar buzz"),
  next=@kernel.DiffInput::of_string("new", "Foo buzz"),
  output=Html,
)
```

| Package | Contents |
| --- | --- |
| `patience_diff` | The diff algorithm, generic over the element type |
| `ansi_text` | Parsing and manipulating text with ANSI escape codes |
| `kernel` | Refinement, moves, rendering and configuration; no I/O |
| `sexp` | S-expressions, for configuration files |
| `sys` | Files, standard streams and the terminal, on `moonbitlang/async` |
| `lib` | Comparing files and directories, loading configuration |
| the module root, `cmd/ansi_text` | The executables, `patdiff` and `ansi_text` |

`sys`, `lib` and the executables do I/O through `moonbitlang/async`, so they build
for native and Wasm (run with `moonrun`), and their I/O functions are `async`.

All text is `Bytes`, because file contents needn't be valid UTF-8, and OCaml's
`string` is a byte sequence too. `DiffInput::of_string` encodes a `String` as UTF-8,
and `@utf8.decode_lossy` from `moonbitlang/core/encoding/utf8` decodes the result.

## Differences from upstream

- **`-include` and `-exclude`** use MoonBit's `@string.Regex` rather than OCaml's
  `Re.Pcre`, so the regexp syntax isn't identical.
- **Very large replaced regions**: when a single `Replace` has hundreds of lines,
  upstream breaks it up around rare words, and breaks ties between equally rare words
  by hash table order. This port uses first appearance, so a tie may be broken
  differently.
- **Terminal width** is read from the controlling terminal on every Unix. Upstream
  only does so on Linux, using 121 columns elsewhere. The Wasm build can't see the
  terminal, so it always uses 121 columns unless given `-width`.
- **File names** must be valid UTF-8, as `moonbitlang/async` takes them as strings.
  File contents can be any bytes.
- **Command line errors and `-help`** have the same content as Core's `Command`, but
  not exactly the same layout.
- **`-double-check`** compares the files in-process rather than running `cmp`.
- **SGR parameters** above 2^31 - 1 are treated as missing, because they don't fit in
  an `Int`.
- Upstream's `Patience_diff.merge` isn't used by patdiff, and isn't ported.

## Testing

```bash
moon test
```

```bash
moon build --release && python3 test/cli/run_cram.py
```

```bash
moon build --release --target wasm && python3 test/cli/run_cram.py --target wasm
```

`moon test` runs upstream's expect tests, ported to MoonBit, on any backend. `test/cli`
holds upstream's command line tests as cram files; they need `bash` and `git`, and
run either the native build or the Wasm build under `moonrun`.
