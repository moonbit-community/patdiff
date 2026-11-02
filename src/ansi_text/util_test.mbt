///|
using @ansi_text {
  type Attr,
  type Element,
  type Control,
  type StyleRange,
  type TextWithStyleRanges,
  type Text,
  parse,
  to_bytes,
  to_bytes_hum,
  visualize,
  minimize,
  strip,
}

///|
fn b(s : String) -> Bytes {
  @bstr.of_string(s)
}

///|
fn str(x : Bytes) -> String {
  @bstr.to_string(x)
}

///|
/// Mimics OCaml's `String.escaped` so expectations can be copied verbatim from
/// the upstream tests (ESC shows as `\027`, backslash as `\\`).
fn escaped(x : Bytes) -> String {
  let buf = StringBuilder()
  for c in x {
    let n = c.to_int()
    if c == b'\n' {
      buf.write_string("\\n")
    } else if c == b'\t' {
      buf.write_string("\\t")
    } else if c == b'\r' {
      buf.write_string("\\r")
    } else if n == 8 {
      buf.write_string("\\b")
    } else if c == b'"' {
      buf.write_string("\\\"")
    } else if c == b'\\' {
      buf.write_string("\\\\")
    } else if n >= 32 && n < 127 {
      buf.write_char(Int::unsafe_to_char(n))
    } else {
      buf.write_string("\\")
      buf.write_string((n / 100).to_string())
      buf.write_string(((n / 10) % 10).to_string())
      buf.write_string((n % 10).to_string())
    }
  }
  buf.to_string()
}

///|
/// Collects what an upstream test would print to stdout, then compares it with
/// an expect-block the way ppx_expect does: indentation is irrelevant (we write
/// blocks dedented), trailing whitespace on each line is ignored, and leading
/// and trailing blank lines are ignored.
struct Out {
  buf : StringBuilder
}

///|
fn Out::new() -> Out {
  { buf: StringBuilder() }
}

///|
fn Out::print(self : Out, s : String) -> Unit {
  self.buf.write_string(s)
}

///|
fn Out::println(self : Out, s : String) -> Unit {
  self.buf.write_string(s)
  self.buf.write_string("\n")
}

///|
fn normalize_expect(s : String) -> String {
  let lines = []
  for line in s.split("\n") {
    let line = line.to_owned()
    let mut stop = line.length()
    while stop > 0 && (line[stop - 1] == ' ' || line[stop - 1] == '\t') {
      stop -= 1
    }
    lines.push(line[:stop].to_owned())
  }
  let mut lo = 0
  let mut hi = lines.length()
  while lo < hi && lines[lo].is_empty() {
    lo += 1
  }
  while hi > lo && lines[hi - 1].is_empty() {
    hi -= 1
  }
  // ppx_expect also ignores a common indentation of the whole block.
  let mut indent = 1000000
  for line in lines[lo:hi] {
    if !line.is_empty() {
      let mut n = 0
      while n < line.length() && line[n] == ' ' {
        n += 1
      }
      indent = @cmp.minimum(indent, n)
    }
  }
  let result = []
  for line in lines[lo:hi] {
    result.push(if line.is_empty() { line } else { line[indent:].to_owned() })
  }
  result.join("\n")
}

///|
/// Like `[%expect {| ... |}]`: compare everything printed since the last check.
fn Out::check(
  self : Out,
  expected : Array[String],
  loc? : SourceLoc = _,
) -> Unit raise {
  let actual = self.buf.to_string()
  self.buf.reset()
  @test.assert_eq(normalize_expect(actual), normalize_expect(expected.join("\n")), loc~)
}
