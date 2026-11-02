///|
/// Helpers for treating `Bytes` the way OCaml treats `string`: as an arbitrary
/// byte sequence. File contents are not guaranteed to be valid UTF-8, so the
/// whole diff pipeline works on `Bytes` and never decodes implicitly.

///|
/// `Char.is_whitespace` from Core: space, `\t`, `\n`, `\x0b`, `\x0c` and `\r`.
pub fn is_whitespace(c : Byte) -> Bool {
  c == b' ' || (c >= 9 && c <= 13)
}

///|
/// Encode text as UTF-8.
pub fn of_string(s : StringView) -> Bytes {
  @utf8.encode(s)
}

///|
/// Decode as UTF-8, replacing malformed sequences.
pub fn to_string(b : BytesView) -> String {
  @utf8.decode_lossy(b)
}

///|
pub fn of_int(n : Int32) -> Bytes {
  of_string(n.to_string())
}

///|
/// An owned copy of `s[start:end]`.
pub fn sub(s : Bytes, start : Int32, end : Int32) -> Bytes {
  s[start:end].to_owned()
}

///|
pub fn concat(parts : ArrayView[Bytes], sep~ : Bytes = b"") -> Bytes {
  let size = parts.fold(init=0, (acc, p) => acc + p.length() + sep.length())
  let buf = Buffer(size_hint=size)
  for i, part in parts {
    if i > 0 {
      buf.write_bytes(sep)
    }
    buf.write_bytes(part)
  }
  buf.contents()
}

///|
pub fn rstrip(s : Bytes) -> Bytes {
  let mut end = s.length()
  while end > 0 && is_whitespace(s[end - 1]) {
    end -= 1
  }
  if end == s.length() {
    s
  } else {
    sub(s, 0, end)
  }
}

///|
pub fn strip(s : Bytes) -> Bytes {
  let mut end = s.length()
  while end > 0 && is_whitespace(s[end - 1]) {
    end -= 1
  }
  let mut start = 0
  while start < end && is_whitespace(s[start]) {
    start += 1
  }
  if start == 0 && end == s.length() {
    s
  } else {
    sub(s, start, end)
  }
}

///|
pub fn for_all(s : BytesView, f : (Byte) -> Bool) -> Bool {
  for c in s {
    if !f(c) {
      return false
    }
  }
  true
}

///|
/// `String.split_lines` from Core: splits on `\n`, drops one `\r` before each
/// `\n`, and yields no trailing empty line when `s` ends with a newline.
pub fn split_lines(s : Bytes) -> Array[Bytes] {
  let lines = []
  let n = s.length()
  let mut start = 0
  for i in 0..<n {
    if s[i] == b'\n' {
      let stop = if i > start && s[i - 1] == b'\r' { i - 1 } else { i }
      lines.push(sub(s, start, stop))
      start = i + 1
    }
  }
  if start < n {
    lines.push(sub(s, start, n))
  }
  lines
}

///|
/// Split on every occurrence of `sep`; always yields at least one part.
pub fn split_on(s : Bytes, sep : Byte) -> Array[Bytes] {
  let parts = []
  let mut start = 0
  for i, c in s {
    if c == sep {
      parts.push(sub(s, start, i))
      start = i + 1
    }
  }
  parts.push(sub(s, start, s.length()))
  parts
}

///|
/// Split at the first occurrence of `sep`.
pub fn lsplit2(s : Bytes, sep : Byte) -> (Bytes, Bytes)? {
  for i, c in s {
    if c == sep {
      return Some((sub(s, 0, i), sub(s, i + 1, s.length())))
    }
  }
  None
}

///|
pub fn is_substring_at(s : Bytes, pos : Int32, substring : Bytes) -> Bool {
  let n = substring.length()
  if pos + n > s.length() {
    return false
  }
  for i in 0..<n {
    if s[pos + i] != substring[i] {
      return false
    }
  }
  true
}

///|
pub fn contains(s : Bytes, substring : Bytes) -> Bool {
  s.find(substring) is Some(_)
}

///|
pub fn spaces(n : Int32) -> Bytes {
  if n <= 0 {
    b""
  } else {
    Bytes::make(n, b' ')
  }
}

///|
pub fn pad_left(s : Bytes, len : Int32) -> Bytes {
  if s.length() >= len {
    s
  } else {
    spaces(len - s.length()) + s
  }
}

///|
/// A stable sort, matching OCaml's `List.sort`, which returns a new array.
pub fn[T] stable_sorted_by(
  xs : ArrayView[T],
  cmp : (T, T) -> Int32,
) -> Array[T] {
  let fixed = FixedArray::from_iter(xs.iter())
  fixed.stable_sort_by(cmp)
  [
    for x in fixed => x
  ]
}
