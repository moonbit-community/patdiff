///|
/// `width`, for functions with a label of the same name.
fn total_width(t : ArrayView[Element]) -> Int32 {
  width(t)
}

///|
fn repeated(char : Byte, n : Int32) -> Text {
  Text::of_bytes(if n <= 0 { b"" } else { Bytes::make(n, char) })
}

///|
/// Pad `t` on the right to `width` columns.
pub fn pad(
  t : ArrayView[Element],
  char~ : Byte = b' ',
  style~ : ArrayView[Attr] = [],
  width~ : Int32,
) -> AnsiText {
  let pad_text = repeated(char, width - total_width(t))
  let out = t.to_owned()
  if style.is_empty() {
    out.push(Text(pad_text))
  } else {
    out.push(Style(style.to_owned()))
    out.push(Text(pad_text))
    out.push(Style(style_turn_off(style)))
  }
  out
}

///|
/// Pad `t` on both sides to `width` columns.
pub fn center(
  t : ArrayView[Element],
  char~ : Byte = b' ',
  style~ : ArrayView[Attr] = [],
  width~ : Int32,
) -> AnsiText {
  let pad_len = @cmp.maximum(0, width - total_width(t))
  let left_pad = Element::Text(repeated(char, pad_len / 2))
  let right_pad = Element::Text(repeated(char, pad_len - pad_len / 2))
  let out : Array[Element] = []
  if style.is_empty() {
    out.push(left_pad)
    out.push_iter(t.iter())
    out.push(right_pad)
  } else {
    let turn_on = Element::Style(style.to_owned())
    let turn_off = Element::Style(style_turn_off(style))
    out.push(turn_on)
    out.push(left_pad)
    out.push(turn_off)
    out.push_iter(t.iter())
    out.push(turn_on)
    out.push(right_pad)
    out.push(turn_off)
  }
  out
}

///|
/// The first `width` columns of `t`.
pub fn truncate(t : ArrayView[Element], width~ : Int32) -> AnsiText {
  split(t, pos=width).0
}

///|
/// Split `t` into lines of at most `width` columns.
pub fn wrap(t : ArrayView[Element], width~ : Int32) -> Array[AnsiText] {
  let lines = []
  let mut rest = t.to_owned()
  while !is_empty(rest) {
    let (before, after) = split(rest, pos=width)
    lines.push(before)
    rest = after
  }
  lines
}

///|
/// Wrap `str` in the escape codes turning `style` on and off again.
pub fn apply(style : ArrayView[Attr], str : Bytes) -> Bytes {
  style_to_string(style) + str + style_to_string(style_turn_off(style))
}

///|
/// Render ANSI codes in `str` in a human-readable form.
pub fn visualize(str : Bytes) -> Bytes {
  to_bytes_hum(parse(str))
}

///|
/// Rewrite `str` with the fewest escape codes giving the same appearance.
pub fn minimize(str : Bytes) -> Bytes {
  to_bytes(simplify_styles(parse(str)))
}

///|
/// Drop ANSI codes from `str`.
pub fn strip(str : Bytes) -> Bytes {
  to_unstyled(parse(str))
}

///|
/// Lay out two texts in columns of `width`, wrapping each as necessary.
pub fn to_double_column(
  width~ : Int32,
  left~ : Bytes,
  right~ : Bytes,
) -> Array[(Bytes, Bytes)] {
  let left = [ for l in wrap(parse(left), width~) => to_bytes(pad(l, width~)) ]
  let right = [ for l in wrap(parse(right), width~) => to_bytes(l) ]
  while left.length() < right.length() {
    left.push(@bstr.spaces(width))
  }
  while right.length() < left.length() {
    right.push(b"")
  }
  [
    for i in 0..<left.length() => (left[i], right[i])
  ]
}
