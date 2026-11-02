///|
/// A file being compared. `Real` files can be read, and may be displayed under
/// an alternative name.
pub(all) enum FileName {
  Real(real_name~ : Bytes, alt_name~ : Bytes?)
  Fake(Bytes)
} derive(Debug, Eq)

///|
pub fn FileName::real_name(self : FileName) -> Bytes {
  match self {
    Real(real_name~, ..) => real_name
    Fake(_) => abort("FileName::real_name got a fake file")
  }
}

///|
pub fn FileName::display_name(self : FileName) -> Bytes {
  match self {
    Real(real_name~, alt_name~) => alt_name.unwrap_or(real_name)
    Fake(name) => name
  }
}

///|
/// `Filename.concat` from Core: exactly one `/` joins the two paths, and `.`
/// segments at the join are collapsed.
pub fn filename_concat(p1 : Bytes, p2 : Bytes) -> Bytes {
  fn collapse_trailing(s : Bytes) -> Bytes {
    guard s.rev_find(b"/") is Some(i) else { return s }
    let tail = @bstr.sub(s, i + 1, s.length())
    if tail == b"." || tail.is_empty() {
      if i == 0 {
        b""
      } else {
        collapse_trailing(@bstr.sub(s, 0, i))
      }
    } else {
      s
    }
  }

  fn collapse_leading(s : Bytes) -> Bytes {
    match @bstr.lsplit2(s, b'/') {
      Some((head, tail)) if head == b"." || head.is_empty() =>
        collapse_leading(tail)
      _ => s
    }
  }

  collapse_trailing(p1) + b"/" + collapse_leading(p2)
}

///|
pub fn FileName::append(self : FileName, part : Bytes) -> FileName {
  match self {
    Real(real_name~, alt_name~) =>
      Real(
        real_name=filename_concat(real_name, part),
        alt_name=alt_name.map(name => filename_concat(name, part)),
      )
    Fake(name) => Fake(filename_concat(name, part))
  }
}

///|
pub fn FileName::dev_null() -> FileName {
  Real(real_name=b"/dev/null", alt_name=None)
}

///|
/// A named blob of text to diff.
pub(all) struct DiffInput {
  name : Bytes
  text : Bytes
} derive(Debug, Eq)

///|
/// A `DiffInput` from UTF-8 text.
pub fn DiffInput::of_string(name : StringView, text : StringView) -> DiffInput {
  { name: @bstr.of_string(name), text: @bstr.of_string(text) }
}
