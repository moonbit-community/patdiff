///|
/// Text placed before or after something, with how to style it.
pub(all) struct Affix {
  text : Bytes
  styles : Array[@ansi_text.Attr]
} derive(Debug, Eq)

///|
pub fn Affix::new(text : Bytes, styles? : Array[@ansi_text.Attr] = []) -> Affix {
  { text, styles }
}

///|
pub fn Affix::blank() -> Affix {
  Affix::new(b"")
}

///|
fn Affix::strip_styles(self : Affix) -> Affix {
  { ..self, styles: [] }
}

///|
/// How to render a piece of output: the content itself is styled with `styles`,
/// between a prefix and a suffix.
pub(all) struct Rule {
  pre : Affix
  suf : Affix
  styles : Array[@ansi_text.Attr]
} derive(Debug, Eq)

///|
pub fn Rule::new(
  pre? : Affix = Affix::blank(),
  suf? : Affix = Affix::blank(),
  styles : Array[@ansi_text.Attr],
) -> Rule {
  { pre, suf, styles }
}

///|
pub fn Rule::blank() -> Rule {
  Rule::new([])
}

///|
pub fn Rule::unstyled_prefix(text : Bytes) -> Rule {
  { ..Rule::blank(), pre: Affix::new(text) }
}

///|
pub fn Rule::strip_styles(self : Rule) -> Rule {
  {
    pre: self.pre.strip_styles(),
    suf: self.suf.strip_styles(),
    styles: [],
  }
}

///|
pub fn Rule::strip_prefix(self : Rule) -> Rule {
  { ..self, pre: Affix::blank() }
}

///|
pub fn Rule::use_prefix_text_from(self : Rule, this_prefix~ : Rule) -> Rule {
  { ..self, pre: { ..self.pre, text: this_prefix.pre.text } }
}

///|
/// A rule for each kind of output.
pub(all) struct Rules {
  line_same : Rule
  line_prev : Rule
  line_next : Rule
  line_unified : Rule
  word_same_prev : Rule
  word_same_next : Rule
  word_same_unified : Rule
  word_same_unified_in_move : Rule
  word_prev : Rule
  word_next : Rule
  hunk : Rule
  header_prev : Rule
  header_next : Rule
  moved_from_prev : Rule
  moved_to_next : Rule
  removed_in_move : Rule
  added_in_move : Rule
  line_unified_in_move : Rule
} derive(Debug, Eq)

///|
pub(all) struct ColorPalette {
  added : @ansi_text.Color
  removed : @ansi_text.Color
  moved_from_prev : @ansi_text.Color
  moved_to_next : @ansi_text.Color
}

///|
pub fn ColorPalette::default() -> ColorPalette {
  {
    added: Standard(Green),
    removed: Standard(Red),
    moved_from_prev: Standard(Magenta),
    moved_to_next: Standard(Cyan),
  }
}

///|
fn inner_line_change(text : Bytes, color : @ansi_text.Color) -> Rule {
  Rule::new(pre=Affix::new(text, styles=[Bold, Fg(color)]), [Fg(color)])
}

///|
fn line_unified_rule(is_move~ : Bool) -> Rule {
  Rule::new(
    pre=Affix::new(if is_move { b">|" } else { b"!|" }, styles=[
      Bold,
      Fg(Standard(Yellow)),
    ]),
    [],
  )
}

///|
pub fn Rules::with_color_palette(palette : ColorPalette) -> Rules {
  {
    line_same: Rule::unstyled_prefix(b"  "),
    line_prev: inner_line_change(b"-|", palette.removed),
    line_next: inner_line_change(b"+|", palette.added),
    line_unified: line_unified_rule(is_move=false),
    word_same_prev: Rule::blank(),
    word_same_next: Rule::blank(),
    word_same_unified: Rule::blank(),
    word_same_unified_in_move: Rule::blank(),
    word_prev: Rule::new([Fg(palette.removed)]),
    word_next: Rule::new([Fg(palette.added)]),
    hunk: Rule::blank(),
    header_prev: Rule::blank(),
    header_next: Rule::blank(),
    moved_from_prev: inner_line_change(b"<|", palette.moved_from_prev),
    moved_to_next: inner_line_change(b">|", palette.moved_to_next),
    removed_in_move: inner_line_change(b">|", palette.removed),
    added_in_move: inner_line_change(b">|", palette.added),
    line_unified_in_move: line_unified_rule(is_move=true),
  }
}

///|
pub fn Rules::default() -> Rules {
  Rules::with_color_palette(ColorPalette::default())
}

///|
pub fn Rules::strip_styles(self : Rules) -> Rules {
  {
    line_same: self.line_same.strip_styles(),
    line_prev: self.line_prev.strip_styles(),
    line_next: self.line_next.strip_styles(),
    line_unified: self.line_unified.strip_styles(),
    word_same_prev: self.word_same_prev.strip_styles(),
    word_same_next: self.word_same_next.strip_styles(),
    word_same_unified: self.word_same_unified.strip_styles(),
    word_same_unified_in_move: self.word_same_unified_in_move.strip_styles(),
    word_prev: self.word_prev.strip_styles(),
    word_next: self.word_next.strip_styles(),
    hunk: self.hunk.strip_styles(),
    header_prev: self.header_prev.strip_styles(),
    header_next: self.header_next.strip_styles(),
    moved_from_prev: self.moved_from_prev.strip_styles(),
    moved_to_next: self.moved_to_next.strip_styles(),
    removed_in_move: self.removed_in_move.strip_styles(),
    added_in_move: self.added_in_move.strip_styles(),
    line_unified_in_move: self.line_unified_in_move.strip_styles(),
  }
}

///|
/// Which line(s) a row of output came from, for `AnnotationGutter`.
pub(all) enum GutterSide {
  Prev(line~ : Int)
  Next(line~ : Int)
  Same(prev~ : Int, next~ : Int)
  Unified(prev~ : Int, next~ : Int)
} derive(Debug, Eq)

///|
/// A column rendered before the +/- diff gutter of each visible line.
pub(all) struct AnnotationGutter {
  width : Int
  render : (GutterSide) -> Bytes
}

///|
pub fn AnnotationGutter::empty() -> AnnotationGutter {
  { width: 0, render: _ => b"" }
}

///|
/// Truncates and pads what `render` returns to `width` columns.
pub fn AnnotationGutter::new(
  width~ : Int,
  render~ : (GutterSide) -> Bytes,
) -> AnnotationGutter {
  {
    width,
    render: side => {
      let text = @ansi_text.truncate(@ansi_text.parse(render(side)), width~)
      @ansi_text.to_bytes(@ansi_text.pad(text, width~))
    },
  }
}

///|
/// How to format the location of a hunk.
pub(all) enum LocationStyle {
  Diff
  Omake
  NoLocation
  Separator
} derive(Debug, Eq)

///|
pub fn LocationStyle::all() -> Array[LocationStyle] {
  [Diff, Omake, NoLocation, Separator]
}

///|
pub fn LocationStyle::to_string(self : LocationStyle) -> String {
  match self {
    Diff => "diff"
    Omake => "omake"
    NoLocation => "none"
    Separator => "separator"
  }
}

///|
pub fn LocationStyle::of_string(s : String) -> LocationStyle? {
  match s {
    "diff" => Some(Diff)
    "omake" => Some(Omake)
    "none" => Some(NoLocation)
    "separator" => Some(Separator)
    _ => None
  }
}

///|
fn omake_style_error_message_start(file~ : Bytes, line~ : Int) -> Bytes {
  b"File \"" +
  file +
  @bstr.of_string("\", line \{line}, characters 0-1:")
}

///|
fn LocationStyle::sprint(
  self : LocationStyle,
  hunk : @pd.Hunk[Bytes],
  prev_filename~ : Bytes,
  rule~ : (Bytes) -> Bytes,
) -> Bytes {
  match self {
    Diff =>
      rule(
        @bstr.of_string(
          "-\{hunk.prev_start},\{hunk.prev_size} +\{hunk.next_start},\{hunk.next_size}",
        ),
      )
    // omake locations must be parseable, so we can't let the user config insert
    // arbitrary prefixes and suffixes and ANSI color rubbish.
    Omake => {
      // Print line number of first difference, skipping past context lines.
      let mut prev_start = hunk.prev_start
      for range in hunk.ranges {
        match range {
          Same(s) => prev_start += s.length()
          _ => break
        }
      }
      omake_style_error_message_start(file=prev_filename, line=prev_start)
    }
    NoLocation => rule(b"")
    Separator => rule(b"=== DIFF HUNK ===")
  }
}
