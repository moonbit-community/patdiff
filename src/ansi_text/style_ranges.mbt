///|
/// A style applied between two display columns.
pub(all) struct StyleRange {
  start : Int
  end : Int
  style : Array[Attr]
} derive(Debug, Eq)

///|
fn attr_key(attr : Attr) -> String {
  attr.to_string()
}

///|
fn StyleRange::compare(self : StyleRange, other : StyleRange) -> Int {
  let by_start = self.start.compare(other.start)
  if by_start != 0 {
    return by_start
  }
  let by_end = self.end.compare(other.end)
  if by_end != 0 {
    return by_end
  }
  let a = [ for attr in self.style => attr_key(attr) ]
  let b = [ for attr in other.style => attr_key(attr) ]
  a.compare(b)
}

///|
/// Find the ranges of `t` between a style and the style closing it. Returns them
/// with the ANSI codes that aren't accounted for by any range.
pub fn style_ranges_identify(
  t : ArrayView[Element],
) -> (Array[StyleRange], Array[Element]) {
  // Most recently opened first.
  let open_ranges : Array[(Int, Array[Attr])] = []
  let closed_ranges = []
  let other_ansi = []
  let mut position = 0
  for element in t {
    match element {
      Text(txt) => position += txt.width
      Style(new_style) => {
        let mut found = None
        for i, item in open_ranges {
          if style_closes(new_style~, old_style=item.1) {
            found = Some(i)
            break
          }
        }
        match found {
          None => open_ranges.insert(0, (position, new_style))
          Some(i) => {
            let (start, old_style) = open_ranges.remove(i)
            closed_ranges.push(StyleRange::{ start, end: position, style: old_style })
          }
        }
      }
      other => other_ansi.push(other)
    }
  }
  let unaccounted = []
  for item in open_ranges.rev_iter() {
    unaccounted.push(Element::Style(item.1))
  }
  unaccounted.push_iter(other_ansi.iter())
  (@bstr.stable_sorted_by(closed_ranges, StyleRange::compare), unaccounted)
}

///|
/// Insert the styles of `ranges` into `text`.
pub fn style_ranges_apply(text~ : Text, ranges : ArrayView[StyleRange]) -> AnsiText {
  let styles = [ for r in ranges => (r.start, r.style) ]
  styles.push_iter(ranges.iter().map(r => (r.end, style_turn_off(r.style))))
  let styles = @bstr.stable_sorted_by(styles, (a, b) => a.0.compare(b.0))
  let out : Array[Element] = []
  let mut text_remaining = text
  let mut last_pos = 0
  for item in styles {
    let (pos, style) = item
    if pos != last_pos {
      let (text_before, rest) = text_remaining.split(pos=pos - last_pos)
      text_remaining = rest
      out.push(Text(text_before))
    }
    out.push(Style(style))
    last_pos = pos
  }
  out.push(Text(text_remaining))
  out
}

///|
/// Shift the starts and ends of `ranges`.
pub fn style_ranges_adjust_by(
  ranges : ArrayView[StyleRange],
  start? : Int = 0,
  end? : Int = 0,
) -> Array[StyleRange] {
  [ for r in ranges => { ..r, start: r.start + start, end: r.end + end } ]
}

///|
/// Remove the styles between `start` and `end`.
pub fn style_ranges_exclude(
  ranges : ArrayView[StyleRange],
  start~ : Int,
  end~ : Int,
) -> Array[StyleRange] {
  let out = []
  for r in ranges {
    let (s, e) = (r.start, r.end)
    if start <= s && e <= end {
      continue
    } else if s <= start && end <= e {
      out.push({ ..r, end: start })
      out.push({ ..r, start: end })
    } else if s <= start && start <= e {
      out.push({ ..r, end: start })
    } else if s <= end && end <= e {
      out.push({ ..r, start: end })
    } else {
      out.push(r)
    }
  }
  out
}

///|
/// Divide `ranges` at `pos`; the second part is relative to `pos`.
pub fn style_ranges_split(
  ranges : ArrayView[StyleRange],
  pos~ : Int,
) -> (Array[StyleRange], Array[StyleRange]) {
  let before = []
  let after_part = []
  let across = []
  for r in ranges {
    if r.end <= pos {
      before.push(r)
    }
    if r.start >= pos {
      after_part.push({ ..r, start: r.start - pos, end: r.end - pos })
    }
    if r.start < pos && r.end > pos {
      across.push(r)
    }
  }
  let after = [ for r in across => { ..r, start: 0, end: r.end - pos } ]
  after.push_iter(after_part.iter())
  before.push_iter(across.iter().map(r => { ..r, end: pos }))
  (before, after)
}

///|
/// Text with its styles held separately, for applying styles to specific ranges
/// or extracting the ranges patdiff applied.
pub(all) struct TextWithStyleRanges {
  text : Text
  ranges : Array[StyleRange]
} derive(Debug, Eq)

///|
pub fn TextWithStyleRanges::width(self : TextWithStyleRanges) -> Int {
  self.text.width
}

///|
pub fn TextWithStyleRanges::is_empty(self : TextWithStyleRanges) -> Bool {
  self.text.is_empty()
}

///|
pub fn TextWithStyleRanges::to_text_with_ansi(
  self : TextWithStyleRanges,
) -> AnsiText {
  let by_pos = (a : (Int, Array[Attr]), b : (Int, Array[Attr])) => a.0.compare(b.0)
  let start_styles = @bstr.stable_sorted_by(
    [ for r in self.ranges => (r.start, r.style) ],
    by_pos,
  )
  let end_styles = @bstr.stable_sorted_by(
    [ for r in self.ranges => (r.end, style_turn_off(r.style)) ],
    by_pos,
  )
  // A stable merge, preferring ends over starts at the same position.
  let styles = []
  let mut i = 0
  let mut j = 0
  while i < end_styles.length() || j < start_styles.length() {
    if j >= start_styles.length() ||
      (i < end_styles.length() && end_styles[i].0 <= start_styles[j].0) {
      styles.push(end_styles[i])
      i += 1
    } else {
      styles.push(start_styles[j])
      j += 1
    }
  }
  let out : Array[Element] = []
  let mut text_remaining = self.text
  let mut last_pos = 0
  for item in styles {
    let (pos, style) = item
    let (text, rest) = text_remaining.split(pos=pos - last_pos)
    text_remaining = rest
    if !text.is_empty() {
      out.push(Text(text))
    }
    out.push(Style(style))
    last_pos = pos
  }
  out
}

///|
/// `None` when `t` has codes that aren't accounted for by a range.
pub fn TextWithStyleRanges::of_text_with_ansi(
  t : ArrayView[Element],
) -> TextWithStyleRanges? {
  let (ranges, unmatched) = style_ranges_identify(t)
  if !unmatched.is_empty() {
    return None
  }
  let texts = []
  for element in t {
    if element is Text(txt) {
      texts.push(txt)
    }
  }
  Some({ text: Text::concat(texts), ranges })
}

///|
pub fn TextWithStyleRanges::to_bytes(self : TextWithStyleRanges) -> Bytes {
  to_bytes(self.to_text_with_ansi())
}

///|
pub fn TextWithStyleRanges::to_bytes_hum(self : TextWithStyleRanges) -> Bytes {
  to_bytes_hum(self.to_text_with_ansi())
}

///|
pub fn TextWithStyleRanges::to_unstyled(self : TextWithStyleRanges) -> Bytes {
  self.text.str
}

///|
pub fn TextWithStyleRanges::unstyle_between(
  self : TextWithStyleRanges,
  start~ : Int,
  end~ : Int,
) -> TextWithStyleRanges {
  { text: self.text, ranges: style_ranges_exclude(self.ranges, start~, end~) }
}

///|
pub fn TextWithStyleRanges::split(
  self : TextWithStyleRanges,
  pos~ : Int,
) -> (TextWithStyleRanges, TextWithStyleRanges) {
  let (text_before, text_after) = self.text.split(pos~)
  let (ranges_before, ranges_after) = style_ranges_split(self.ranges, pos~)
  (
    { text: text_before, ranges: ranges_before },
    { text: text_after, ranges: ranges_after },
  )
}
