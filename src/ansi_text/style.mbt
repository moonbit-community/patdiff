///|
/// A style models an ANSI escape sequence that can modify several attributes.
/// The functions on it are prefixed with `style_`.
pub type Style = Array[Attr]

///|
/// Make a style from parsed CSI parameters. For example the parser, handling
/// `"\x1b[1;38;5;1m"`, would invoke
/// `style_of_sgr_params([Some(1), Some(38), Some(5), Some(1)])`, yielding
/// `[Bold, Fg(Standard(Red))]`.
pub fn style_of_sgr_params(params : ArrayView[Int?]) -> Style {
  let codes = []
  for param in params {
    if param is Some(code) {
      codes.push(code)
    }
  }
  // Per ECMA-48, `ESC [ m` (no parameters) is equivalent to `ESC [ 0 m` (reset).
  if codes.is_empty() {
    codes.push(0)
  }
  let style = []
  let mut rest : ArrayView[Int] = codes
  while rest is [first, ..] {
    let n = match rest {
      [38 | 48 | 58, 2, _, _, _, ..] => 5
      [38 | 48 | 58, 5, _, ..] => 3
      _ => 1
    }
    ignore(first)
    style.push(Attr::of_codes(rest[:n]))
    rest = rest[n:]
  }
  style
}

///|
/// For example `[Bold, Fg(Standard(Red))]` gives `"\x1b[1;31m"`.
pub fn style_to_string(style : ArrayView[Attr]) -> Bytes {
  if style.is_empty() {
    return b""
  }
  let codes = [ for attr in style => attr.to_string() ]
  @bstr.of_string("\u{1b}[\{codes.join(";")}m")
}

///|
pub fn style_includes_reset(style : ArrayView[Attr]) -> Bool {
  style.iter().any(attr => attr is Reset)
}

///|
pub fn style_is_reset(style : ArrayView[Attr]) -> Bool {
  style is [.., Reset]
}

///|
/// If a reset is present, drop it and everything before.
fn after_reset(style : ArrayView[Attr]) -> ArrayView[Attr] {
  let mut start = 0
  for i, attr in style {
    if attr is Reset {
      start = i + 1
    }
  }
  style[start:]
}

///|
/// Simplifies a style by removing redundant attributes. For example
/// `[Bold, Bg(Blue), Reset, Fg(Red), Fg(Green)]` gives `[Reset, Fg(Green)]`.
/// Styles are generally short, so being quadratic is fine.
pub fn style_compress(style : ArrayView[Attr]) -> Style {
  let keep = []
  // Walk from the end: each attribute is kept unless a later one overrides it.
  for attr in style.rev_iter() {
    if !keep.iter().any(later => overrides(new_attr=later, old_attr=attr)) {
      keep.push(attr)
    }
  }
  keep.rev()
}

///|
/// The style that results from applying `added_style` over `old_style`.
pub fn style_update(
  old_style~ : ArrayView[Attr],
  added_style~ : ArrayView[Attr],
) -> Style {
  let all = old_style.to_owned()
  all.push_iter(added_style.iter())
  style_compress(all)
}

///|
/// A minimal style transitioning the active state from `old_style` to
/// `old_style` plus `added_style`.
pub fn style_delta(
  old_style~ : ArrayView[Attr],
  added_style~ : ArrayView[Attr],
) -> Style {
  let old_style = style_compress(old_style)
  let added_style = style_compress(added_style)
  match (style_includes_reset(old_style), style_includes_reset(added_style)) {
    (true, true) => {
      // Check whether the added style is shorter with or without the reset.
      let old_attrs = after_reset(old_style)
      let new_attrs = after_reset(added_style)
      let without_reset = []
      for old_attr in old_attrs {
        if !new_attrs
          .iter()
          .any(new_attr => overrides(new_attr~, old_attr~)) &&
          old_attr.turn_off() is Some(off) {
          without_reset.push(off)
        }
      }
      for new_attr in new_attrs {
        if !old_attrs.contains(new_attr) {
          without_reset.push(new_attr)
        }
      }
      if without_reset.length() < added_style.length() {
        without_reset
      } else {
        added_style
      }
    }
    (false, true) => {
      let out : Array[Attr] = [Reset]
      out.push_iter(after_reset(added_style).iter())
      out
    }
    (_, false) => {
      let out = []
      for new_attr in added_style {
        let mut last_overridden = None
        for old_attr in old_style {
          if overrides(new_attr~, old_attr~) {
            last_overridden = Some(old_attr)
          }
        }
        if !(last_overridden is Some(a) && a == new_attr) {
          out.push(new_attr)
        }
      }
      out
    }
  }
}

///|
/// A style turning off all attributes that are turned on by `style`.
pub fn style_turn_off(style : ArrayView[Attr]) -> Style {
  let out = []
  for attr in style {
    if attr.turn_off() is Some(off) {
      out.push(off)
    }
  }
  style_compress(out)
}

///|
/// Whether `new_style` overrides all attributes that `old_style` set.
pub fn style_closes(
  new_style~ : ArrayView[Attr],
  old_style~ : ArrayView[Attr],
) -> Bool {
  old_style
  .iter()
  .all(old_attr => new_style
    .iter()
    .any(new_attr => overrides(new_attr~, old_attr~)))
}

///|
/// Lists the attributes in a somewhat human-readable style.
pub fn style_to_string_hum(style : ArrayView[Attr]) -> String {
  if style.is_empty() {
    return ""
  }
  let inner = [ for attr in style => attr.to_string_hum() ]
  "(\{inner.join(" ")})"
}
