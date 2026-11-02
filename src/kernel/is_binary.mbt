///|
/// The choice of 8000 bytes is copied from git:
/// https://github.com/git/git/blob/b7bd9486b055c3f967a870311e704e3bb0654e4f/xdiff-interface.c#L201
const PREFIX_LENGTH = 8000

///|
/// Heuristic for detecting content that is clearly binary.
pub fn is_binary(s : Bytes) -> Bool {
  let limit = @cmp.minimum(PREFIX_LENGTH, s.length())
  for i in 0..<limit {
    if s[i] == 0 {
      return true
    }
  }
  false
}

///|
pub fn is_binary_lines(lines : ArrayView[Bytes]) -> Bool {
  let mut len = 0
  for line in lines {
    if is_binary(line) {
      return true
    }
    len += line.length()
    if len >= PREFIX_LENGTH {
      return false
    }
  }
  false
}

///|
fn looks_like_python_filename(name : Bytes) -> Bool {
  name.has_suffix(b".py")
}

///|
fn looks_like_python_first_line(first_line : Bytes) -> Bool {
  first_line.has_prefix(b"#!") && @bstr.contains(first_line, b"python")
}

///|
fn looks_like_fsharp_filename(name : Bytes) -> Bool {
  [b".fs", b".fsi", b".fsy", b".fsl", b".fsx"]
  .iter()
  .any(suffix => name.has_suffix(suffix))
}

///|
fn first_line(text : Bytes) -> Bytes {
  match text.find(b"\n") {
    Some(i) => @bstr.sub(text, 0, i)
    None => text
  }
}

///|
/// Whether whitespace is significant in these inputs, judging by their names
/// and first lines.
pub fn should_keep_whitespace(prev~ : DiffInput, next~ : DiffInput) -> Bool {
  [prev, next]
  .iter()
  .any(input => {
    looks_like_python_filename(input.name) ||
    looks_like_python_first_line(first_line(input.text)) ||
    looks_like_fsharp_filename(input.name)
  })
}

///|
/// Like `should_keep_whitespace`, for inputs already split into lines.
pub fn should_keep_whitespace_lines(
  prev~ : (Bytes, ArrayView[Bytes]),
  next~ : (Bytes, ArrayView[Bytes]),
) -> Bool {
  [prev, next]
  .iter()
  .any(input => {
    let (name, lines) = input
    let first = if lines.is_empty() { b"" } else { lines[0] }
    looks_like_python_filename(name) ||
    looks_like_python_first_line(first) ||
    looks_like_fsharp_filename(name)
  })
}
