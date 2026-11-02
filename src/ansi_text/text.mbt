///|
/// Plain text together with what's needed to reason about its display width.
/// `str` is stored as given even when it isn't valid UTF-8; `char_widths` is
/// computed from its sanitized form.
pub(all) struct Text {
  str : Bytes
  char_widths : Array[(Char, Int32)]
  width : Int32
} derive(Debug, Eq)

///|
/// Decode the UTF-8 scalar at `i`, returning it with its encoded length.
/// Ill-formed input yields U+FFFD and consumes the maximal invalid subpart.
fn decode_utf8(s : Bytes, i : Int32) -> (Char, Int32) {
  let replacement = '\u{FFFD}'
  let n = s.length()
  let b0 = s[i].to_int()
  if b0 < 0x80 {
    return (b0.unsafe_to_char(), 1)
  }
  let (len, min2, max2) = match b0 {
    0xE0 => (3, 0xA0, 0xBF)
    0xED => (3, 0x80, 0x9F)
    0xF0 => (4, 0x90, 0xBF)
    0xF4 => (4, 0x80, 0x8F)
    b if b >= 0xC2 && b <= 0xDF => (2, 0x80, 0xBF)
    b if b >= 0xE1 && b <= 0xEF => (3, 0x80, 0xBF)
    b if b >= 0xF1 && b <= 0xF3 => (4, 0x80, 0xBF)
    _ => return (replacement, 1)
  }
  let mut code = match len {
    2 => b0 & 0x1F
    3 => b0 & 0x0F
    _ => b0 & 0x07
  }
  for k in 1..<len {
    if i + k >= n {
      return (replacement, k)
    }
    let b = s[i + k].to_int()
    let (lo, hi) = if k == 1 { (min2, max2) } else { (0x80, 0xBF) }
    if b < lo || b > hi {
      return (replacement, k)
    }
    code = (code << 6) | (b & 0x3F)
  }
  (code.unsafe_to_char(), len)
}

///|
fn utf8_byte_length(c : Char) -> Int32 {
  let code = c.to_int()
  if code < 0x80 {
    1
  } else if code < 0x800 {
    2
  } else if code < 0x10000 {
    3
  } else {
    4
  }
}

///|
pub fn Text::of_bytes(str : Bytes) -> Text {
  let char_widths = []
  let mut width = 0
  let mut i = 0
  while i < str.length() {
    let (c, len) = decode_utf8(str, i)
    let w = char_width(c)
    char_widths.push((c, w))
    width += w
    i += len
  }
  { str, char_widths, width, }
}

///|
pub fn Text::is_empty(self : Text) -> Bool {
  self.str.is_empty()
}

///|
/// Split so that the prefix is as wide as possible while not exceeding `pos`.
pub fn Text::split(self : Text, pos~ : Int32) -> (Text, Text) {
  let mut prefix_width = 0
  let mut n = 0
  let mut prefix_bytes = 0
  for item in self.char_widths {
    let (c, w) = item
    if prefix_width + w > pos {
      break
    }
    prefix_width += w
    n += 1
    prefix_bytes += utf8_byte_length(c)
  }
  // The offsets above are for the sanitized string, so they can run past the
  // end of an ill-formed `str`.
  let cut = @cmp.minimum(prefix_bytes, self.str.length())
  (
    {
      str: @bstr.sub(self.str, 0, cut),
      char_widths: self.char_widths[:n].to_owned(),
      width: prefix_width,
    },
    {
      str: @bstr.sub(self.str, cut, self.str.length()),
      char_widths: self.char_widths[n:].to_owned(),
      width: self.width - prefix_width,
    },
  )
}

///|
pub impl Add for Text with fn add(self, other) {
  let char_widths = self.char_widths.copy()
  char_widths.push_iter(other.char_widths.iter())
  { str: self.str + other.str, char_widths, width: self.width + other.width, }
}

///|
pub fn Text::concat(texts : ArrayView[Text]) -> Text {
  texts.fold(init=Text::of_bytes(b""), (acc, t) => acc + t)
}
