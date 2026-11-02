///|
/// One part of a text with ANSI escapes.
pub(all) enum Element {
  Text(Text)
  Style(Array[Attr])
  Hyperlink(Hyperlink)
  PrivateMode(PrivateMode)
  Osc(Osc)
  Dsr(Dsr)
  Control(Control)
  Unknown(UnknownEsc)
} derive(Debug, Eq)

///|
/// Text as a sequence of plain runs and ANSI elements.
pub type AnsiText = Array[Element]

///|
/// The width of the text in a terminal, ignoring ANSI codes.
pub fn width(t : ArrayView[Element]) -> Int {
  let mut total = 0
  for element in t {
    if element is Text(txt) {
      total += txt.width
    }
  }
  total
}

///|
/// Whether there is no text, even if there are ANSI codes.
pub fn is_empty(t : ArrayView[Element]) -> Bool {
  for element in t {
    if element is Text(txt) && !txt.is_empty() {
      return false
    }
  }
  true
}

///|
pub fn Element::to_bytes(self : Element) -> Bytes {
  match self {
    Style(sty) => style_to_string(sty)
    Control(ctl) => ctl.to_bytes()
    Hyperlink(link) => link.to_bytes()
    PrivateMode(pm) => pm.to_bytes()
    Osc(osc) => osc.to_bytes()
    Dsr(dsr) => dsr.to_bytes()
    Unknown(unk) => unk.to_bytes()
    Text(txt) => txt.str
  }
}

///|
pub fn Element::to_bytes_hum(self : Element) -> Bytes {
  match self {
    Style(sty) => @bstr.of_string(style_to_string_hum(sty))
    Control(ctl) => @bstr.of_string(ctl.to_string_hum())
    Hyperlink(link) => link.to_bytes_hum()
    PrivateMode(pm) => @bstr.of_string(pm.to_string_hum())
    Osc(osc) => osc.to_bytes_hum()
    Dsr(dsr) => @bstr.of_string(dsr.to_string_hum())
    Unknown(unk) => unk.to_bytes_hum()
    Text(txt) => txt.str
  }
}

///|
/// The text with its ANSI codes.
pub fn to_bytes(t : ArrayView[Element]) -> Bytes {
  @bstr.concat([ for e in t => e.to_bytes() ])
}

///|
/// The text with ANSI codes in a human-readable form.
pub fn to_bytes_hum(t : ArrayView[Element]) -> Bytes {
  @bstr.concat([ for e in t => e.to_bytes_hum() ])
}

///|
/// The text with all ANSI codes dropped.
pub fn to_unstyled(t : ArrayView[Element]) -> Bytes {
  let parts = []
  for element in t {
    if element is Text(txt) {
      parts.push(txt.str)
    }
  }
  @bstr.concat(parts)
}

///|
/// Replace each element for which `f` gives `Some`.
pub fn map(t : ArrayView[Element], f : (Element) -> Element?) -> AnsiText {
  [ for e in t => f(e).unwrap_or(e) ]
}

///|
/// Combine adjacent `Text` or `Style` elements; compress all styles.
pub fn compress(t : ArrayView[Element]) -> AnsiText {
  let combined : Array[Element] = []
  for element in t {
    match (combined.last(), element) {
      (_, Text(txt)) if txt.is_empty() => ()
      (Some(Style(prev)), Style(next)) => {
        let joined = prev.copy()
        joined.push_iter(next.iter())
        combined[combined.length() - 1] = Style(joined)
      }
      (Some(Text(prev)), Text(next)) =>
        combined[combined.length() - 1] = Text(prev + next)
      _ => combined.push(element)
    }
  }
  let out = []
  for element in combined {
    match element {
      Style(sty) => {
        let sty = style_compress(sty)
        if !sty.is_empty() {
          out.push(Element::Style(sty))
        }
      }
      element => out.push(element)
    }
  }
  out
}

///|
/// Rewrite styles as the minimal transition from the preceding state.
pub fn simplify_styles(t : ArrayView[Element]) -> AnsiText {
  let mut old_style : Style = []
  let deltas = []
  for element in compress(t) {
    match element {
      Style(added_style) => {
        let delta = style_delta(old_style~, added_style~)
        old_style = style_update(old_style~, added_style~)
        deltas.push(Element::Style(delta))
      }
      element => deltas.push(element)
    }
  }
  compress(deltas)
}

///|
/// The active style after `t`.
pub fn style_at_end(t : ArrayView[Element]) -> Style {
  let mut style : Style = []
  for element in t {
    if element is Style(added_style) {
      style = style_update(old_style=style, added_style~)
    }
  }
  style
}

///|
/// Splits at display column `pos`. Any active style is turned off at the end of
/// the first part and back on at the start of the second.
pub fn split(t : ArrayView[Element], pos~ : Int) -> (AnsiText, AnsiText) {
  let mut found : (Int, Int)? = None
  let mut len = 0
  for idx, element in t {
    if element is Text(txt) {
      let w = txt.width
      if len + w >= pos {
        found = Some((idx, len))
        break
      }
      len += w
    }
  }
  guard found is Some((idx, len)) else { return (t.to_owned(), []) }
  let at_boundary = match t[idx] {
    Text(txt) => txt
    _ => Text::of_bytes(b"") // should be impossible
  }
  let (before, after) = if len + at_boundary.width == pos {
    (t[:idx + 1].to_owned(), t[idx + 1:].to_owned())
  } else {
    let (prefix, suffix) = at_boundary.split(pos=pos - len)
    let before = t[:idx].to_owned()
    before.push(Text(prefix))
    let after : Array[Element] = [Text(suffix)]
    after.push_iter(t[idx + 1:].iter())
    (before, after)
  }
  let to_turn_on = style_delta(old_style=[], added_style=style_at_end(before))
  before.push(Style(style_turn_off(to_turn_on)))
  if to_turn_on.is_empty() {
    return (before, after)
  }
  match after.get(0) {
    Some(Style(sty)) => {
      // If we're putting one non-trivial style in front of another, compress
      // them.
      let joined = to_turn_on.copy()
      joined.push_iter(sty.iter())
      after[0] = Style(style_compress(joined))
    }
    _ => after.insert(0, Style(to_turn_on))
  }
  (before, after)
}
