// The format of configuration files. There have been four versions of it, which
// are still understood: a file is parsed as the newest version that accepts it.

///|
/// A prefix or a suffix, possibly with an associated style.
pub(all) struct DiskAffix {
  text : Bytes?
  style : Array[@ansi_text.Attr]?
} derive(Debug, Eq)

///|
fn DiskAffix::get_text(self : DiskAffix) -> Bytes {
  self.text.unwrap_or(b"")
}

///|
fn DiskAffix::to_internal(self : DiskAffix, min_width~ : Int) -> Affix {
  Affix::new(
    @bstr.pad_left(self.get_text(), min_width),
    styles=self.style.unwrap_or([]),
  )
}

///|
pub(all) struct DiskRule {
  prefix : DiskAffix?
  suffix : DiskAffix?
  style : Array[@ansi_text.Attr]?
} derive(Debug, Eq)

///|
fn DiskRule::blank() -> DiskRule {
  { prefix: None, suffix: None, style: None }
}

///|
fn DiskRule::to_internal(self : DiskRule) -> Rule {
  let affix_of = (opt : DiskAffix?) => match opt {
    Some(affix) => affix.to_internal(min_width=0)
    None => Affix::blank()
  }
  Rule::new(
    pre=affix_of(self.prefix),
    suf=affix_of(self.suffix),
    self.style.unwrap_or([]),
  )
}

///|
pub(all) struct DiskLineRule {
  prefix : DiskAffix?
  suffix : DiskAffix?
  style : Array[@ansi_text.Attr]?
  word_same : Array[@ansi_text.Attr]?
} derive(Debug, Eq)

///|
fn line_rule(
  text : Bytes,
  prefix_style : Array[@ansi_text.Attr],
  style? : Array[@ansi_text.Attr],
  word_same? : Array[@ansi_text.Attr],
) -> DiskLineRule {
  {
    prefix: Some({ text: Some(text), style: Some(prefix_style) }),
    suffix: None,
    style,
    word_same,
  }
}

///|
fn line_same_default() -> DiskLineRule {
  line_rule(b" |", black_on(Bright(Black)))
}

///|
fn line_old_default() -> DiskLineRule {
  line_rule(
    b"-|",
    black_on(Standard(Red)),
    style=[Fg(Standard(Red))],
    word_same=[Fg(Gray24(@ansi_text.Gray24::of_level(12)))],
  )
}

///|
fn line_new_default() -> DiskLineRule {
  line_rule(b"+|", black_on(Standard(Green)), style=[Fg(Standard(Green))])
}

///|
fn line_unified_default() -> DiskLineRule {
  line_rule(b"!|", black_on(Standard(Yellow)))
}

///|
fn header_old_default() -> DiskLineRule {
  line_rule(b"------ ", [Fg(Standard(Red))], style=[Bold])
}

///|
fn header_new_default() -> DiskLineRule {
  line_rule(b"++++++ ", [Fg(Standard(Green))], style=[Bold])
}

///|
fn line_from_old_default() -> DiskLineRule {
  line_rule(b"<|", black_on(Standard(Magenta)), style=[Fg(Standard(Magenta))])
}

///|
fn line_to_new_default() -> DiskLineRule {
  line_rule(b">|", black_on(Standard(Cyan)), style=[Fg(Standard(Cyan))])
}

///|
fn line_removed_in_move_default() -> DiskLineRule {
  line_rule(b">|", black_on(Standard(Red)), style=[Fg(Standard(Red))])
}

///|
fn line_added_in_move_default() -> DiskLineRule {
  line_rule(b">|", black_on(Standard(Green)), style=[Fg(Standard(Green))])
}

///|
fn line_unified_in_move_default() -> DiskLineRule {
  line_rule(b">|", black_on(Standard(Yellow)))
}

///|
pub(all) enum DiskOutput {
  OAscii
  OHtml
  OAnsi
  OUnrefinedAnsi
  OUnrefinedHtml
  OSideBySide(WrapOrTruncate)
} derive(Debug, Eq)

///|
/// The contents of a configuration file, in the newest format.
pub(all) struct OnDisk {
  dont_produce_unified_lines : Bool?
  dont_overwrite_word_old_word_new : Bool?
  config_path : Bytes?
  context : Int?
  line_big_enough : Int?
  word_big_enough : Int?
  keep_whitespace : Bool?
  find_moves : Bool?
  split_long_lines : Bool?
  interleave : Bool?
  assume_text : Bool?
  quiet : Bool?
  shallow : Bool?
  double_check : Bool?
  mask_uniques : Bool?
  output : DiskOutput
  alt_old : Bytes?
  alt_new : Bytes?
  header_old : DiskRule?
  header_new : DiskRule?
  hunk : DiskRule?
  line_same : DiskLineRule?
  line_old : DiskLineRule?
  line_new : DiskLineRule?
  line_unified : DiskLineRule?
  line_from_old : DiskLineRule?
  line_to_new : DiskLineRule?
  line_removed_in_move : DiskLineRule?
  line_added_in_move : DiskLineRule?
  line_unified_in_move : DiskLineRule?
  word_old : DiskRule?
  word_new : DiskRule?
  location_style : LocationStyle
  warn_if_no_trailing_newline_in_both : Bool
  width_override : Int?
} derive(Debug, Eq)

// Reading s-expressions.

///|
fn sexp_error(msg : String) -> @sexp.SexpError {
  @sexp.SexpError(msg)
}

///|
fn atom_text(sexp : @sexp.Sexp) -> String raise @sexp.SexpError {
  guard sexp is Atom(s) else { raise sexp_error("expected an atom") }
  @bstr.to_string(s)
}

///|
fn bytes_of_sexp(sexp : @sexp.Sexp) -> Bytes raise @sexp.SexpError {
  guard sexp is Atom(s) else { raise sexp_error("expected an atom") }
  s
}

///|
fn int_of_sexp(sexp : @sexp.Sexp) -> Int raise @sexp.SexpError {
  let text = atom_text(sexp)
  @string.parse_int(text) catch {
    _ => raise sexp_error("expected an int, got \{text}")
  }
}

///|
fn bool_of_sexp(sexp : @sexp.Sexp) -> Bool raise @sexp.SexpError {
  match atom_text(sexp) {
    "true" | "True" => true
    "false" | "False" => false
    text => raise sexp_error("expected a bool, got \{text}")
  }
}

///|
/// The name of a variant constructor. As with OCaml's generated converters, the
/// first letter can be written in either case.
fn constructor_name(text : String) -> String {
  match text.get_char(0) {
    Some(c) if c >= 'a' && c <= 'z' => {
      let upper = (c.to_int() - 32).unsafe_to_char()
      "\{upper}\{text.clamped_view(start=1)}"
    }
    _ => text
  }
}

///|
/// The fields of a record, which may only be those in `allowed`.
fn record_fields(
  sexp : @sexp.Sexp,
  allowed : ArrayView[String],
) -> Map[String, @sexp.Sexp] raise @sexp.SexpError {
  guard sexp is List(items) else { raise sexp_error("expected a record") }
  let fields = Map([])
  for item in items {
    guard item is List([Atom(name), value]) else {
      raise sexp_error("expected a (field value) pair")
    }
    let name = @bstr.to_string(name)
    if !allowed.contains(name) {
      raise sexp_error("unknown field \{name}")
    }
    if fields.contains(name) {
      raise sexp_error("duplicate field \{name}")
    }
    fields[name] = value
  }
  fields
}

///|
fn[A] optional_field(
  fields : Map[String, @sexp.Sexp],
  name : String,
  convert : (@sexp.Sexp) -> A raise @sexp.SexpError,
) -> A? raise @sexp.SexpError {
  match fields.get(name) {
    Some(sexp) => Some(convert(sexp))
    None => None
  }
}

///|
fn[A] required_field(
  fields : Map[String, @sexp.Sexp],
  name : String,
  convert : (@sexp.Sexp) -> A raise @sexp.SexpError,
) -> A raise @sexp.SexpError {
  guard fields.get(name) is Some(sexp) else {
    raise sexp_error("missing field \{name}")
  }
  convert(sexp)
}

///|
fn sgr8_of_sexp(sexp : @sexp.Sexp) -> @ansi_text.Sgr8 raise @sexp.SexpError {
  match constructor_name(atom_text(sexp)) {
    "Black" => Black
    "Red" => Red
    "Green" => Green
    "Yellow" => Yellow
    "Blue" => Blue
    "Magenta" => Magenta
    "Cyan" => Cyan
    "White" => White
    other => raise sexp_error("unknown color \{other}")
  }
}

///|
fn rgb_of_sexp(sexp : @sexp.Sexp) -> (Int, Int, Int) raise @sexp.SexpError {
  let fields = record_fields(sexp, ["r", "g", "b"])
  (
    required_field(fields, "r", int_of_sexp),
    required_field(fields, "g", int_of_sexp),
    required_field(fields, "b", int_of_sexp),
  )
}

///|
fn gray24_of_sexp(sexp : @sexp.Sexp) -> @ansi_text.Gray24 raise @sexp.SexpError {
  { level: required_field(record_fields(sexp, ["level"]), "level", int_of_sexp) }
}

///|
fn rgb6_of_sexp(sexp : @sexp.Sexp) -> @ansi_text.Rgb6 raise @sexp.SexpError {
  let (r, g, b) = rgb_of_sexp(sexp)
  { r, g, b }
}

///|
fn rgb256_of_sexp(sexp : @sexp.Sexp) -> @ansi_text.Rgb256 raise @sexp.SexpError {
  let (r, g, b) = rgb_of_sexp(sexp)
  { r, g, b }
}

///|
/// Also accepts the color names of old patdiff configurations.
fn color_of_sexp(sexp : @sexp.Sexp) -> @ansi_text.Color raise @sexp.SexpError {
  match sexp {
    Atom(_) =>
      match atom_text(sexp) {
        "black" | "Black" => Standard(Black)
        "red" | "Red" => Standard(Red)
        "green" | "Green" => Standard(Green)
        "yellow" | "Yellow" => Standard(Yellow)
        "blue" | "Blue" => Standard(Blue)
        "magenta" | "Magenta" => Standard(Magenta)
        "cyan" | "Cyan" => Standard(Cyan)
        "white" | "White" => Standard(White)
        "gray" | "Gray" => Bright(Black)
        "bright_black" | "Bright_black" => Bright(Black)
        "bright_red" | "Bright_red" => Bright(Red)
        "bright_green" | "Bright_green" => Bright(Green)
        "bright_yellow" | "Bright_yellow" => Bright(Yellow)
        "bright_blue" | "Bright_blue" => Bright(Blue)
        "bright_magenta" | "Bright_magenta" => Bright(Magenta)
        "bright_cyan" | "Bright_cyan" => Bright(Cyan)
        "bright_white" | "Bright_white" => Bright(White)
        "default" | "Default" => Default
        other => raise sexp_error("unknown color \{other}")
      }
    List([Atom(_) as name, arg]) =>
      match atom_text(name) {
        "GRAY24" => Gray24(gray24_of_sexp(arg))
        "RGB6" => Rgb6(rgb6_of_sexp(arg))
        "RGB256" => Rgb256(rgb256_of_sexp(arg))
        text =>
          match constructor_name(text) {
            "Standard" => Standard(sgr8_of_sexp(arg))
            "Bright" => Bright(sgr8_of_sexp(arg))
            "Rgb6" => Rgb6(rgb6_of_sexp(arg))
            "Gray24" => Gray24(gray24_of_sexp(arg))
            "Rgb256" => Rgb256(rgb256_of_sexp(arg))
            other => raise sexp_error("unknown color \{other}")
          }
      }
    _ => raise sexp_error("expected a color")
  }
}

///|
/// Names of the attributes without arguments, as `(sexp name, attribute)`.
fn plain_attrs() -> Array[(String, @ansi_text.Attr)] {
  [
    ("Reset", Reset),
    ("Bold", Bold),
    ("Faint", Faint),
    ("Normal_weight", NormalWeight),
    ("Italic", Italic),
    ("Fraktur", Fraktur),
    ("Not_emphasis", NotEmphasis),
    ("Underline", Underline),
    ("Double_ul", DoubleUl),
    ("Not_underline", NotUnderline),
    ("Blink", Blink),
    ("Fast_blink", FastBlink),
    ("Not_blink", NotBlink),
    ("Framed", Framed),
    ("Encircled", Encircled),
    ("Not_framed", NotFramed),
    ("Superscript", Superscript),
    ("Subscript", Subscript),
    ("Not_script", NotScript),
    ("Invert", Invert),
    ("Not_invert", NotInvert),
    ("Hide", Hide),
    ("Not_hide", NotHide),
    ("Strike", Strike),
    ("Not_strike", NotStrike),
    ("Overline", Overline),
    ("Not_overline", NotOverline),
    ("Variable_width", VariableWidth),
    ("Fixed_width", FixedWidth),
  ]
}

///|
/// Also accepts the attribute names of old patdiff configurations.
fn attr_of_sexp(sexp : @sexp.Sexp) -> @ansi_text.Attr raise @sexp.SexpError {
  match sexp {
    Atom(_) => {
      let text = atom_text(sexp)
      match text {
        "dim" => return Faint
        "inverse" => return Invert
        "emph" => return Italic
        _ => ()
      }
      let name = constructor_name(text)
      for item in plain_attrs() {
        if item.0 == name {
          return item.1
        }
      }
      raise sexp_error("unknown style \{text}")
    }
    List([Atom(_) as name, arg]) =>
      match constructor_name(atom_text(name)) {
        "Fg" => Fg(color_of_sexp(arg))
        "Bg" => Bg(color_of_sexp(arg))
        "Ul_color" => UlColor(color_of_sexp(arg))
        "Font" => Font(int_of_sexp(arg))
        "Ideogram" => Ideogram(int_of_sexp(arg))
        "Other" => {
          guard arg is List(items) else { raise sexp_error("expected a list") }
          let codes = []
          for item in items {
            codes.push(int_of_sexp(item))
          }
          Other(codes)
        }
        other => raise sexp_error("unknown style \{other}")
      }
    _ => raise sexp_error("expected a style")
  }
}

///|
fn style_of_sexp(sexp : @sexp.Sexp) -> Array[@ansi_text.Attr] raise @sexp.SexpError {
  guard sexp is List(items) else { raise sexp_error("expected a list of styles") }
  let attrs = []
  for item in items {
    attrs.push(attr_of_sexp(item))
  }
  attrs
}

///|
fn affix_of_sexp(sexp : @sexp.Sexp) -> DiskAffix raise @sexp.SexpError {
  let fields = record_fields(sexp, ["text", "style"])
  {
    text: optional_field(fields, "text", bytes_of_sexp),
    style: optional_field(fields, "style", style_of_sexp),
  }
}

///|
fn rule_of_sexp(sexp : @sexp.Sexp) -> DiskRule raise @sexp.SexpError {
  let fields = record_fields(sexp, ["prefix", "suffix", "style"])
  {
    prefix: optional_field(fields, "prefix", affix_of_sexp),
    suffix: optional_field(fields, "suffix", affix_of_sexp),
    style: optional_field(fields, "style", style_of_sexp),
  }
}

///|
fn line_rule_of_sexp(sexp : @sexp.Sexp) -> DiskLineRule raise @sexp.SexpError {
  let fields = record_fields(sexp, ["prefix", "suffix", "style", "word_same"])
  {
    prefix: optional_field(fields, "prefix", affix_of_sexp),
    suffix: optional_field(fields, "suffix", affix_of_sexp),
    style: optional_field(fields, "style", style_of_sexp),
    word_same: optional_field(fields, "word_same", style_of_sexp),
  }
}

///|
fn location_style_of_sexp(sexp : @sexp.Sexp) -> LocationStyle raise @sexp.SexpError {
  match constructor_name(atom_text(sexp)) {
    "Diff" => Diff
    "Omake" => Omake
    "None" => NoLocation
    "Separator" => Separator
    other => raise sexp_error("unknown location style \{other}")
  }
}

///|
fn output_of_sexp(sexp : @sexp.Sexp) -> DiskOutput raise @sexp.SexpError {
  match sexp {
    Atom(_) =>
      match atom_text(sexp) {
        "ascii" => OAscii
        "html" => OHtml
        "ansi" => OAnsi
        other => raise sexp_error("unknown output \{other}")
      }
    List([Atom(_) as name, arg]) =>
      match (atom_text(name), atom_text(arg)) {
        ("unrefined", "ansi") => OUnrefinedAnsi
        ("unrefined", "html") => OUnrefinedHtml
        ("side_by_side", "wrap") => OSideBySide(Wrap)
        ("side_by_side", "truncate") => OSideBySide(Truncate)
        _ => raise sexp_error("unknown output")
      }
    _ => raise sexp_error("expected an output")
  }
}

///|
/// Fields shared by the three newest formats.
let common_fields : ReadOnlyArray[String] = [
  "dont_produce_unified_lines", "dont_overwrite_word_old_word_new", "config_path",
  "context", "line_big_enough", "word_big_enough", "keep_whitespace", "split_long_lines",
  "interleave", "assume_text", "quiet", "shallow", "double_check", "mask_uniques",
  "alt_old", "alt_new", "header_old", "header_new", "hunk", "line_same", "line_old",
  "line_new", "line_unified", "word_old", "word_new", "location_style",
  "warn_if_no_trailing_newline_in_both",
]

///|
fn with_fields(extra : ArrayView[String]) -> Array[String] {
  let fields = common_fields.iter().to_array()
  fields.push_iter(extra.iter())
  fields
}

///|
fn on_disk_of_fields(
  fields : Map[String, @sexp.Sexp],
  output~ : DiskOutput,
  find_moves~ : Bool?,
) -> OnDisk raise @sexp.SexpError {
  {
    dont_produce_unified_lines: optional_field(
      fields, "dont_produce_unified_lines", bool_of_sexp,
    ),
    dont_overwrite_word_old_word_new: optional_field(
      fields, "dont_overwrite_word_old_word_new", bool_of_sexp,
    ),
    config_path: optional_field(fields, "config_path", bytes_of_sexp),
    context: optional_field(fields, "context", int_of_sexp),
    line_big_enough: optional_field(fields, "line_big_enough", int_of_sexp),
    word_big_enough: optional_field(fields, "word_big_enough", int_of_sexp),
    keep_whitespace: optional_field(fields, "keep_whitespace", bool_of_sexp),
    find_moves,
    split_long_lines: optional_field(fields, "split_long_lines", bool_of_sexp),
    interleave: optional_field(fields, "interleave", bool_of_sexp),
    assume_text: optional_field(fields, "assume_text", bool_of_sexp),
    quiet: optional_field(fields, "quiet", bool_of_sexp),
    shallow: optional_field(fields, "shallow", bool_of_sexp),
    double_check: optional_field(fields, "double_check", bool_of_sexp),
    mask_uniques: optional_field(fields, "mask_uniques", bool_of_sexp),
    output,
    alt_old: optional_field(fields, "alt_old", bytes_of_sexp),
    alt_new: optional_field(fields, "alt_new", bytes_of_sexp),
    header_old: optional_field(fields, "header_old", rule_of_sexp),
    header_new: optional_field(fields, "header_new", rule_of_sexp),
    hunk: optional_field(fields, "hunk", rule_of_sexp),
    line_same: optional_field(fields, "line_same", line_rule_of_sexp),
    line_old: optional_field(fields, "line_old", line_rule_of_sexp),
    line_new: optional_field(fields, "line_new", line_rule_of_sexp),
    line_unified: optional_field(fields, "line_unified", line_rule_of_sexp),
    line_from_old: optional_field(fields, "line_from_old", line_rule_of_sexp),
    line_to_new: optional_field(fields, "line_to_new", line_rule_of_sexp),
    line_removed_in_move: optional_field(
      fields, "line_removed_in_move", line_rule_of_sexp,
    ),
    line_added_in_move: optional_field(
      fields, "line_added_in_move", line_rule_of_sexp,
    ),
    line_unified_in_move: optional_field(
      fields, "line_unified_in_move", line_rule_of_sexp,
    ),
    word_old: optional_field(fields, "word_old", rule_of_sexp),
    word_new: optional_field(fields, "word_new", rule_of_sexp),
    location_style: optional_field(
      fields, "location_style", location_style_of_sexp,
    ).unwrap_or(Diff),
    warn_if_no_trailing_newline_in_both: optional_field(
      fields, "warn_if_no_trailing_newline_in_both", bool_of_sexp,
    ).unwrap_or(WARN_IF_NO_TRAILING_NEWLINE_IN_BOTH_DEFAULT),
    width_override: optional_field(fields, "width_override", int_of_sexp),
  }
}

///|
fn OnDisk::of_sexp_v3(sexp : @sexp.Sexp) -> OnDisk raise @sexp.SexpError {
  let fields = record_fields(
    sexp,
    with_fields([
      "find_moves", "output", "line_from_old", "line_to_new", "line_removed_in_move",
      "line_added_in_move", "line_unified_in_move", "width_override",
    ]),
  )
  on_disk_of_fields(
    fields,
    output=optional_field(fields, "output", output_of_sexp).unwrap_or(OAnsi),
    find_moves=optional_field(fields, "find_moves", bool_of_sexp),
  )
}

///|
fn OnDisk::of_sexp_v2(sexp : @sexp.Sexp) -> OnDisk raise @sexp.SexpError {
  let fields = record_fields(sexp, with_fields(["output"]))
  let output = optional_field(fields, "output", output_of_sexp).unwrap_or(OAnsi)
  if output is OSideBySide(_) {
    raise sexp_error("side_by_side output needs a newer configuration")
  }
  on_disk_of_fields(fields, output~, find_moves=Some(false))
}

///|
fn OnDisk::of_sexp_v1(sexp : @sexp.Sexp) -> OnDisk raise @sexp.SexpError {
  let fields = record_fields(sexp, with_fields(["unrefined", "html"]))
  let html = optional_field(fields, "html", bool_of_sexp).unwrap_or(false)
  let unrefined = optional_field(fields, "unrefined", bool_of_sexp).unwrap_or(false)
  let output = match (html, unrefined) {
    (true, true) => OUnrefinedHtml
    (true, false) => OHtml
    (false, true) => OUnrefinedAnsi
    (false, false) => OAnsi
  }
  on_disk_of_fields(fields, output~, find_moves=Some(false))
}

///|
fn OnDisk::of_sexp_v0(sexp : @sexp.Sexp) -> OnDisk raise @sexp.SexpError {
  let fields = record_fields(sexp, [
    "config_path", "context", "line_big_enough", "word_big_enough", "unrefined",
    "keep_whitespace", "split_long_lines", "interleave", "assume_text", "shallow",
    "quiet", "double_check", "hide_uniques", "header", "line_same", "line_same_prefix",
    "line_changed", "word_same", "word_changed", "chunk", "location_style",
    "warn_if_no_trailing_newline_in_both",
  ])
  let style_or_none = (sexp : @sexp.Sexp) => style_of_sexp(sexp)
  let header = match fields.get("header") {
    None => None
    Some(sexp) =>
      Some(
        record_fields(sexp, [
          "style_old", "style_new", "prefix_old", "suffix_old", "prefix_new", "suffix_new",
        ]),
      )
  }
  let header_rule = (style : String, prefix : String, suffix : String) => {
    match header {
      None => None
      Some(header) =>
        Some(DiskRule::{
          style: optional_field(header, style, style_or_none),
          prefix: optional_field(header, prefix, affix_of_sexp),
          suffix: optional_field(header, suffix, affix_of_sexp),
        })
    }
  }
  let word_same = match fields.get("word_same") {
    None => None
    Some(sexp) => {
      let word_same = record_fields(sexp, ["style_old", "style_new"])
      Some((
        required_field(word_same, "style_old", style_of_sexp),
        required_field(word_same, "style_new", style_of_sexp),
      ))
    }
  }
  let word_changed = match fields.get("word_changed") {
    None => None
    Some(sexp) => {
      let word_changed = record_fields(sexp, [
        "style_old", "style_new", "prefix_old", "suffix_old", "prefix_new", "suffix_new",
      ])
      // The optional fields must still be well formed.
      let _ = optional_field(word_changed, "prefix_old", affix_of_sexp)
      let _ = optional_field(word_changed, "suffix_old", affix_of_sexp)
      let _ = optional_field(word_changed, "prefix_new", affix_of_sexp)
      let _ = optional_field(word_changed, "suffix_new", affix_of_sexp)
      Some((
        required_field(word_changed, "style_old", style_of_sexp),
        required_field(word_changed, "style_new", style_of_sexp),
      ))
    }
  }
  let line_changed = match fields.get("line_changed") {
    None => None
    Some(sexp) => {
      let line_changed = record_fields(sexp, ["prefix_old", "prefix_new"])
      Some((
        required_field(line_changed, "prefix_old", affix_of_sexp),
        required_field(line_changed, "prefix_new", affix_of_sexp),
      ))
    }
  }
  let same_old = word_same.map(pair => pair.0)
  let same_new = word_same.map(pair => pair.1)
  let unrefined = optional_field(fields, "unrefined", bool_of_sexp).unwrap_or(false)
  // The fields with the same name in newer formats have other meanings here, so
  // they are only read through `of_v0`.
  let shared = Map([])
  for name in [
    "config_path", "context", "line_big_enough", "word_big_enough", "keep_whitespace",
    "split_long_lines", "interleave", "assume_text", "shallow", "quiet", "double_check",
    "location_style", "warn_if_no_trailing_newline_in_both",
  ] {
    if fields.get(name) is Some(sexp) {
      shared[name] = sexp
    }
  }
  let base = on_disk_of_fields(
    shared,
    output=if unrefined { OUnrefinedAnsi } else { OAnsi },
    find_moves=Some(false),
  )
  {
    ..base,
    mask_uniques: optional_field(fields, "hide_uniques", bool_of_sexp),
    header_old: header_rule("style_old", "prefix_old", "suffix_old"),
    header_new: header_rule("style_new", "prefix_new", "suffix_new"),
    hunk: optional_field(fields, "chunk", rule_of_sexp),
    line_same: Some({
      prefix: optional_field(fields, "line_same_prefix", affix_of_sexp),
      suffix: None,
      style: optional_field(fields, "line_same", style_of_sexp),
      word_same: same_old,
    }),
    line_old: line_changed.map(pair => {
      prefix: Some(pair.0),
      suffix: None,
      style: word_changed.map(changed => changed.0),
      word_same: same_old,
    }),
    line_new: line_changed.map(pair => {
      prefix: Some(pair.1),
      suffix: None,
      style: word_changed.map(changed => changed.1),
      word_same: same_new,
    }),
  }
}

///|
/// Which format a configuration was understood as.
pub(all) enum DiskVersion {
  Current
  Outdated
}

///|
/// Parses a configuration, trying each format from newest to oldest. When none
/// accepts it, the error from the newest format is raised.
pub fn OnDisk::of_sexp_versioned(
  sexp : @sexp.Sexp,
) -> (OnDisk, DiskVersion) raise @sexp.SexpError {
  let as_v3 = try OnDisk::of_sexp_v3(sexp) catch {
    err => err
  } noraise {
    on_disk => return (on_disk, Current)
  }
  try OnDisk::of_sexp_v2(sexp) catch {
    _ => ()
  } noraise {
    on_disk => return (on_disk, Current)
  }
  try OnDisk::of_sexp_v1(sexp) catch {
    _ => ()
  } noraise {
    on_disk => return (on_disk, Outdated)
  }
  try OnDisk::of_sexp_v0(sexp) catch {
    _ => raise as_v3
  } noraise {
    on_disk => (on_disk, Outdated)
  }
}

///|
pub fn OnDisk::of_sexp(sexp : @sexp.Sexp) -> OnDisk raise @sexp.SexpError {
  OnDisk::of_sexp_versioned(sexp).0
}

///|
/// Interprets a configuration file.
pub fn OnDisk::to_configuration(self : OnDisk) -> Configuration {
  let line_same = self.line_same.unwrap_or(line_same_default())
  let line_prev = self.line_old.unwrap_or(line_old_default())
  let line_next = self.line_new.unwrap_or(line_new_default())
  let line_unified = self.line_unified.unwrap_or(line_unified_default())
  let line_from_prev = self.line_from_old.unwrap_or(line_from_old_default())
  let line_to_next = self.line_to_new.unwrap_or(line_to_new_default())
  let line_removed_in_move = self.line_removed_in_move.unwrap_or(
    line_removed_in_move_default(),
  )
  let line_added_in_move = self.line_added_in_move.unwrap_or(
    line_added_in_move_default(),
  )
  let line_unified_in_move = self.line_unified_in_move.unwrap_or(
    line_unified_in_move_default(),
  )
  // Padding for prefixes: they should all be the same length.
  let mut min_width = 0
  for line in [
    line_same, line_prev, line_next, line_unified, line_from_prev, line_to_next,
    line_removed_in_move, line_added_in_move,
  ] {
    if line.prefix is Some(prefix) {
      min_width = @cmp.maximum(min_width, prefix.get_text().length())
    }
  }
  let create_line = (line : DiskLineRule) => Rule::new(
    line.style.unwrap_or([]),
    pre=line.prefix
      .unwrap_or({ text: None, style: None })
      .to_internal(min_width~),
  )
  let create_word_same = (line : DiskLineRule) => Rule::new(
    line.word_same.unwrap_or([]),
  )
  let overwrite = !self.dont_overwrite_word_old_word_new.unwrap_or(false)
  let create_word = (line_rule : DiskLineRule, opt : DiskRule?) => {
    if overwrite {
      DiskRule::{ ..DiskRule::blank(), style: line_rule.style }.to_internal()
    } else {
      opt.unwrap_or(DiskRule::blank()).to_internal()
    }
  }
  let create_header = (rule : DiskRule?, prefix : Bytes) => {
    let rule = rule.unwrap_or(DiskRule::blank())
    let affix = rule.prefix.unwrap_or({ text: None, style: None })
    DiskRule::{
      ..rule,
      prefix: Some({ ..affix, text: Some(affix.text.unwrap_or(prefix)) }),
    }.to_internal()
  }
  let hunk_rule = {
    let rule = self.hunk.unwrap_or(DiskRule::blank())
    let prefix = rule.prefix.unwrap_or({ text: None, style: None })
    let suffix = rule.suffix.unwrap_or({ text: None, style: None })
    DiskRule::{
      ..rule,
      prefix: Some({ ..prefix, text: Some(prefix.text.unwrap_or(b"@@ ")) }),
      suffix: Some({ ..suffix, text: Some(suffix.text.unwrap_or(b" @@")) }),
    }.to_internal()
  }
  let output : Output = match self.output {
    OAscii => Ascii
    OUnrefinedHtml | OHtml => Html
    OUnrefinedAnsi | OAnsi | OSideBySide(_) => Ansi
  }
  Configuration::{
    rules: {
      line_same: create_line(line_same),
      line_prev: create_line(line_prev),
      line_next: create_line(line_next),
      line_unified: create_line(line_unified),
      word_same_prev: create_word_same(line_prev),
      word_same_next: create_word_same(line_next),
      word_same_unified: create_word_same(line_unified),
      word_same_unified_in_move: Rule::new(
        self.line_to_new.bind(rule => rule.style).unwrap_or([]),
      ),
      word_prev: create_word(line_prev, self.word_old),
      word_next: create_word(line_next, self.word_new),
      hunk: hunk_rule,
      header_prev: create_header(self.header_old, b"---"),
      header_next: create_header(self.header_new, b"+++"),
      moved_from_prev: create_line(line_from_prev),
      moved_to_next: create_line(line_to_next),
      removed_in_move: create_line(line_removed_in_move),
      added_in_move: create_line(line_added_in_move),
      line_unified_in_move: create_line(line_unified_in_move),
    },
    output,
    context: self.context.unwrap_or(-1),
    word_big_enough: self.word_big_enough.unwrap_or(DEFAULT_WORD_BIG_ENOUGH),
    line_big_enough: self.line_big_enough.unwrap_or(DEFAULT_LINE_BIG_ENOUGH),
    unrefined: self.output is (OUnrefinedAnsi | OUnrefinedHtml | OAscii),
    produce_unified_lines: !self.dont_produce_unified_lines.unwrap_or(false),
    float_tolerance: None,
    keep_ws: self.keep_whitespace.unwrap_or(false),
    find_moves: self.find_moves.unwrap_or(false),
    split_long_lines: self.split_long_lines.unwrap_or(false),
    interleave: self.interleave.unwrap_or(true),
    assume_text: self.assume_text.unwrap_or(false),
    shallow: self.shallow.unwrap_or(false),
    quiet: self.quiet.unwrap_or(false),
    double_check: self.double_check.unwrap_or(false),
    mask_uniques: self.mask_uniques.unwrap_or(false),
    prev_alt: self.alt_old,
    next_alt: self.alt_new,
    location_style: self.location_style,
    warn_if_no_trailing_newline_in_both: self.warn_if_no_trailing_newline_in_both,
    side_by_side: if self.output is OSideBySide(wrap_or_truncate) {
      Some(wrap_or_truncate)
    } else {
      None
    },
    width_override: self.width_override,
  }.check()
}

// Writing s-expressions.

///|
fn sgr8_to_sexp(c : @ansi_text.Sgr8) -> @sexp.Sexp {
  let name = c.to_string_hum()
  @sexp.Sexp::atom(constructor_name(name))
}

///|
fn int_to_sexp(n : Int) -> @sexp.Sexp {
  @sexp.Sexp::atom(n.to_string())
}

///|
fn sexp_field(name : String, value : @sexp.Sexp) -> @sexp.Sexp {
  List([@sexp.Sexp::atom(name), value])
}

///|
fn rgb_to_sexp(r : Int, g : Int, b : Int) -> @sexp.Sexp {
  List([
    sexp_field("r", int_to_sexp(r)),
    sexp_field("g", int_to_sexp(g)),
    sexp_field("b", int_to_sexp(b)),
  ])
}

///|
fn color_to_sexp(color : @ansi_text.Color) -> @sexp.Sexp {
  match color {
    Default => @sexp.Sexp::atom("Default")
    Standard(c) => sexp_field("Standard", sgr8_to_sexp(c))
    Bright(c) => sexp_field("Bright", sgr8_to_sexp(c))
    Rgb6({ r, g, b }) => sexp_field("Rgb6", rgb_to_sexp(r, g, b))
    Gray24({ level }) =>
      sexp_field("Gray24", List([sexp_field("level", int_to_sexp(level))]))
    Rgb256({ r, g, b }) => sexp_field("Rgb256", rgb_to_sexp(r, g, b))
  }
}

///|
fn attr_to_sexp(attr : @ansi_text.Attr) -> @sexp.Sexp {
  for item in plain_attrs() {
    if item.1 == attr {
      return @sexp.Sexp::atom(item.0)
    }
  }
  match attr {
    Fg(c) => sexp_field("Fg", color_to_sexp(c))
    Bg(c) => sexp_field("Bg", color_to_sexp(c))
    UlColor(c) => sexp_field("Ul_color", color_to_sexp(c))
    Font(n) => sexp_field("Font", int_to_sexp(n))
    Ideogram(n) => sexp_field("Ideogram", int_to_sexp(n))
    Other(codes) =>
      sexp_field("Other", List([ for code in codes => int_to_sexp(code) ]))
    _ => abort("attr_to_sexp: attribute missing from plain_attrs")
  }
}

///|
fn style_to_sexp(style : ArrayView[@ansi_text.Attr]) -> @sexp.Sexp {
  List([ for attr in style => attr_to_sexp(attr) ])
}

///|
fn[A] add_field(
  fields : Array[@sexp.Sexp],
  name : String,
  value : A?,
  convert : (A) -> @sexp.Sexp,
) -> Unit {
  if value is Some(value) {
    fields.push(sexp_field(name, convert(value)))
  }
}

///|
fn affix_to_sexp(affix : DiskAffix) -> @sexp.Sexp {
  let fields = []
  add_field(fields, "text", affix.text, s => @sexp.Atom(s))
  add_field(fields, "style", affix.style, s => style_to_sexp(s))
  List(fields)
}

///|
fn rule_to_sexp(rule : DiskRule) -> @sexp.Sexp {
  let fields = []
  add_field(fields, "prefix", rule.prefix, affix_to_sexp)
  add_field(fields, "suffix", rule.suffix, affix_to_sexp)
  add_field(fields, "style", rule.style, s => style_to_sexp(s))
  List(fields)
}

///|
fn line_rule_to_sexp(rule : DiskLineRule) -> @sexp.Sexp {
  let fields = []
  add_field(fields, "prefix", rule.prefix, affix_to_sexp)
  add_field(fields, "suffix", rule.suffix, affix_to_sexp)
  add_field(fields, "style", rule.style, s => style_to_sexp(s))
  add_field(fields, "word_same", rule.word_same, s => style_to_sexp(s))
  List(fields)
}

///|
fn bool_to_sexp(b : Bool) -> @sexp.Sexp {
  @sexp.Sexp::atom(b.to_string())
}

///|
fn location_style_to_sexp(style : LocationStyle) -> @sexp.Sexp {
  @sexp.Sexp::atom(
    match style {
      Diff => "Diff"
      Omake => "Omake"
      NoLocation => "None"
      Separator => "Separator"
    },
  )
}

///|
pub fn OnDisk::to_sexp(self : OnDisk) -> @sexp.Sexp {
  let fields = []
  let bytes_sexp = (s : Bytes) => @sexp.Atom(s)
  add_field(fields, "dont_produce_unified_lines", self.dont_produce_unified_lines, bool_to_sexp)
  add_field(
    fields, "dont_overwrite_word_old_word_new", self.dont_overwrite_word_old_word_new, bool_to_sexp,
  )
  add_field(fields, "config_path", self.config_path, bytes_sexp)
  add_field(fields, "context", self.context, int_to_sexp)
  add_field(fields, "line_big_enough", self.line_big_enough, int_to_sexp)
  add_field(fields, "word_big_enough", self.word_big_enough, int_to_sexp)
  add_field(fields, "keep_whitespace", self.keep_whitespace, bool_to_sexp)
  add_field(fields, "find_moves", self.find_moves, bool_to_sexp)
  add_field(fields, "split_long_lines", self.split_long_lines, bool_to_sexp)
  add_field(fields, "interleave", self.interleave, bool_to_sexp)
  add_field(fields, "assume_text", self.assume_text, bool_to_sexp)
  add_field(fields, "quiet", self.quiet, bool_to_sexp)
  add_field(fields, "shallow", self.shallow, bool_to_sexp)
  add_field(fields, "double_check", self.double_check, bool_to_sexp)
  add_field(fields, "mask_uniques", self.mask_uniques, bool_to_sexp)
  match self.output {
    OAnsi => ()
    OAscii => fields.push(sexp_field("output", @sexp.Sexp::atom("ascii")))
    OHtml => fields.push(sexp_field("output", @sexp.Sexp::atom("html")))
    OUnrefinedAnsi =>
      fields.push(sexp_field("output", sexp_field("unrefined", @sexp.Sexp::atom("ansi"))))
    OUnrefinedHtml =>
      fields.push(sexp_field("output", sexp_field("unrefined", @sexp.Sexp::atom("html"))))
    OSideBySide(wrap_or_truncate) => {
      let name = if wrap_or_truncate is Truncate { "truncate" } else { "wrap" }
      fields.push(
        sexp_field("output", sexp_field("side_by_side", @sexp.Sexp::atom(name))),
      )
    }
  }
  add_field(fields, "alt_old", self.alt_old, bytes_sexp)
  add_field(fields, "alt_new", self.alt_new, bytes_sexp)
  add_field(fields, "header_old", self.header_old, rule_to_sexp)
  add_field(fields, "header_new", self.header_new, rule_to_sexp)
  add_field(fields, "hunk", self.hunk, rule_to_sexp)
  add_field(fields, "line_same", self.line_same, line_rule_to_sexp)
  add_field(fields, "line_old", self.line_old, line_rule_to_sexp)
  add_field(fields, "line_new", self.line_new, line_rule_to_sexp)
  add_field(fields, "line_unified", self.line_unified, line_rule_to_sexp)
  add_field(fields, "line_from_old", self.line_from_old, line_rule_to_sexp)
  add_field(fields, "line_to_new", self.line_to_new, line_rule_to_sexp)
  add_field(fields, "line_removed_in_move", self.line_removed_in_move, line_rule_to_sexp)
  add_field(fields, "line_added_in_move", self.line_added_in_move, line_rule_to_sexp)
  add_field(fields, "line_unified_in_move", self.line_unified_in_move, line_rule_to_sexp)
  add_field(fields, "word_old", self.word_old, rule_to_sexp)
  add_field(fields, "word_new", self.word_new, rule_to_sexp)
  if self.location_style != Diff {
    fields.push(sexp_field("location_style", location_style_to_sexp(self.location_style)))
  }
  if self.warn_if_no_trailing_newline_in_both !=
    WARN_IF_NO_TRAILING_NEWLINE_IN_BOTH_DEFAULT {
    fields.push(
      sexp_field(
        "warn_if_no_trailing_newline_in_both",
        bool_to_sexp(self.warn_if_no_trailing_newline_in_both),
      ),
    )
  }
  add_field(fields, "width_override", self.width_override, int_to_sexp)
  List(fields)
}

///|
/// The text of the default configuration file.
pub fn default_config_string() -> Bytes {
  let rule = (line_rule : DiskLineRule) => line_rule_to_sexp(line_rule).to_bytes_mach()
  @bstr.concat([
    @bstr.of_string(";; -*- scheme -*-\n;; patdiff Configuration file\n\n(\n (context \{DEFAULT_CONTEXT})\n\n (line_same "),
    rule(line_same_default()),
    b")\n\n (line_old ",
    rule(line_old_default()),
    b")\n\n (line_new ",
    rule(line_new_default()),
    b")\n\n (line_unified ",
    rule(line_unified_default()),
    b")\n\n (header_old ",
    rule(header_old_default()),
    b")\n\n (header_new ",
    rule(header_new_default()),
    b")\n\n (hunk\n  ((prefix ((text \"@|\") (style ((bg (Bright Black)) (Fg (Standard Black))))))\n   (suffix ((text \" ============================================================\") (style ())))\n   (style (bold))))\n\n (line_from_old ",
    rule(line_from_old_default()),
    b")\n\n (line_to_new ",
    rule(line_to_new_default()),
    b")\n\n (line_removed_in_move ",
    rule(line_removed_in_move_default()),
    b")\n\n (line_added_in_move ",
    rule(line_added_in_move_default()),
    b")\n\n (line_unified_in_move ",
    rule(line_unified_in_move_default()),
    b")\n)",
  ])
}

///|
/// A configuration for dark backgrounds.
pub fn dark_bg_configuration() -> Configuration {
  let text =
    #|((context 8)
    #| (line_same ())
    #| (line_changed
    #|  ((prefix_old ((text "-|") (style (Bold (Fg (Standard Red))))))
    #|   (prefix_new ((text "+|") (style (Bold (Fg (Standard Green))))))))
    #| (word_same ((style_old ())
    #|             (style_new ())))
    #| (word_changed ((style_old (Bold Underline (Fg (Standard Red))))
    #|                (style_new ((Fg (Standard Green))))))
    #| (chunk
    #|  ((prefix ((text "@@@@@@@@@@ ") (style (Bold (Fg blue)))))
    #|   (suffix ((text " @@@@@@@@@@") (style (Bold (Fg blue)))))
    #|   (style (Bold (Fg blue)))))
    #| )
  configuration_of_v0(text)
}

///|
/// A configuration for light backgrounds.
pub fn light_bg_configuration() -> Configuration {
  let text =
    #|((context 8)
    #| (line_same (Faint))
    #| (line_changed ((prefix_old ((text "-|") (style (bold (Fg (Standard Red))))))
    #|                (prefix_new ((text "+|") (style (bold (Fg (Standard Green))))))))
    #| (word_same ((style_old ((bg white)))
    #|             (style_new ((Bg (Standard Yellow))))))
    #| (word_changed ((style_old ((bg white) bold))
    #|                (style_new ((Bg (Standard Yellow)) bold))))
    #| )
  configuration_of_v0(text)
}

///|
fn configuration_of_v0(text : String) -> Configuration {
  let parsed = try {
    OnDisk::of_sexp_v0(@sexp.Sexp::parse(@bstr.of_string(text)))
  } catch {
    err => abort("invalid built-in configuration: \{err}")
  }
  parsed.to_configuration()
}
