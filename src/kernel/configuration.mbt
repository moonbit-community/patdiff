///|
pub const DEFAULT_CONTEXT = 16

// The following constants were all chosen empirically.

///|
/// Default cutoff for line-level semantic cleanup. Any match of this size or
/// more will not be deleted, even if it's surrounded by large inserts and
/// deletes. Raising this quantity can only decrease the number of matches, and
/// lowering it can only increase the number of matches.
pub const DEFAULT_LINE_BIG_ENOUGH = 3

///|
/// Analogous to `DEFAULT_LINE_BIG_ENOUGH`, but for word-level refinement.
pub const DEFAULT_WORD_BIG_ENOUGH = 7

///|
/// Governs the behavior of `split_for_readability`. We only split ranges around
/// matches of size greater than this. It should always be at least 1, otherwise
/// we will split on a single `Newline` token. Raising it results in fewer ranges
/// being split, and setting it to infinity is the same as `interleave=false`.
pub const TOO_SHORT_TO_SPLIT = 2

///|
pub const WARN_IF_NO_TRAILING_NEWLINE_IN_BOTH_DEFAULT = true

///|
pub const DEFAULT_DOUBLE_COLUMN_WIDTH = 121

///|
let default_double_column_width : Int = DEFAULT_DOUBLE_COLUMN_WIDTH

///|
pub(all) enum WrapOrTruncate {
  Wrap
  Truncate
  /// Neither; only accepted when building rows with `build_side_by_side`.
  Neither
} derive(Debug, Eq)

///|
pub(all) struct Configuration {
  output : Output
  rules : Rules
  /// A multiplier: 0.1 is 10%.
  float_tolerance : Double?
  produce_unified_lines : Bool
  unrefined : Bool
  keep_ws : Bool
  find_moves : Bool
  split_long_lines : Bool
  interleave : Bool
  assume_text : Bool
  context : Int
  line_big_enough : Int
  word_big_enough : Int
  shallow : Bool
  quiet : Bool
  double_check : Bool
  mask_uniques : Bool
  prev_alt : Bytes?
  next_alt : Bytes?
  location_style : LocationStyle
  warn_if_no_trailing_newline_in_both : Bool
  side_by_side : WrapOrTruncate?
  width_override : Int?
} derive(Debug, Eq)

///|
/// Checks the invariants, aborting if they don't hold.
pub fn Configuration::check(self : Configuration) -> Configuration {
  if self.output.implies_unrefined() && !self.unrefined {
    abort("output implies unrefined")
  }
  if self.line_big_enough <= 0 {
    abort("line_big_enough must be positive")
  }
  if self.word_big_enough <= 0 {
    abort("word_big_enough must be positive")
  }
  self
}

///|
/// A copy of `self` with the given fields changed. `Some(None)` clears an
/// optional field; `unrefined` is forced on when `output` requires it.
pub fn Configuration::override_with(
  self : Configuration,
  output? : Output,
  rules? : Rules,
  float_tolerance? : Double?,
  produce_unified_lines? : Bool,
  unrefined? : Bool,
  keep_ws? : Bool,
  find_moves? : Bool,
  split_long_lines? : Bool,
  interleave? : Bool,
  assume_text? : Bool,
  context? : Int,
  line_big_enough? : Int,
  word_big_enough? : Int,
  shallow? : Bool,
  quiet? : Bool,
  double_check? : Bool,
  mask_uniques? : Bool,
  prev_alt? : Bytes?,
  next_alt? : Bytes?,
  location_style? : LocationStyle,
  warn_if_no_trailing_newline_in_both? : Bool,
  side_by_side? : WrapOrTruncate?,
  width_override? : Int?,
) -> Configuration {
  let output = output.unwrap_or(self.output)
  {
    output,
    rules: rules.unwrap_or(self.rules),
    float_tolerance: float_tolerance.unwrap_or(self.float_tolerance),
    produce_unified_lines: produce_unified_lines.unwrap_or(
      self.produce_unified_lines,
    ),
    unrefined: unrefined.unwrap_or(self.unrefined) || output.implies_unrefined(),
    keep_ws: keep_ws.unwrap_or(self.keep_ws),
    find_moves: find_moves.unwrap_or(self.find_moves),
    split_long_lines: split_long_lines.unwrap_or(self.split_long_lines),
    interleave: interleave.unwrap_or(self.interleave),
    assume_text: assume_text.unwrap_or(self.assume_text),
    context: context.unwrap_or(self.context),
    line_big_enough: line_big_enough.unwrap_or(self.line_big_enough),
    word_big_enough: word_big_enough.unwrap_or(self.word_big_enough),
    shallow: shallow.unwrap_or(self.shallow),
    quiet: quiet.unwrap_or(self.quiet),
    double_check: double_check.unwrap_or(self.double_check),
    mask_uniques: mask_uniques.unwrap_or(self.mask_uniques),
    prev_alt: prev_alt.unwrap_or(self.prev_alt),
    next_alt: next_alt.unwrap_or(self.next_alt),
    location_style: location_style.unwrap_or(self.location_style),
    warn_if_no_trailing_newline_in_both: warn_if_no_trailing_newline_in_both.unwrap_or(
      self.warn_if_no_trailing_newline_in_both,
    ),
    side_by_side: side_by_side.unwrap_or(self.side_by_side),
    width_override: width_override.unwrap_or(self.width_override),
  }.check()
}

///|
fn affix(text : Bytes, styles : Array[@ansi_text.Attr]) -> Affix {
  Affix::new(text, styles~)
}

///|
fn black_on(color : @ansi_text.Color) -> Array[@ansi_text.Attr] {
  [Bg(color), Fg(Standard(Black))]
}

///|
pub fn Configuration::default() -> Configuration {
  {
    output: Ansi,
    rules: {
      line_same: Rule::new([], pre=affix(b" |", black_on(Bright(Black)))),
      line_prev: Rule::new([Fg(Standard(Red))], pre=affix(b"-|", black_on(Standard(Red)))),
      line_next: Rule::new(
        [Fg(Standard(Green))],
        pre=affix(b"+|", black_on(Standard(Green))),
      ),
      line_unified: Rule::new([], pre=affix(b"!|", black_on(Standard(Yellow)))),
      word_same_prev: Rule::new([Fg(Gray24(@ansi_text.Gray24::of_level(12)))]),
      word_same_next: Rule::blank(),
      word_same_unified: Rule::blank(),
      word_same_unified_in_move: Rule::new([Fg(Standard(Cyan))]),
      word_prev: Rule::new([Fg(Standard(Red))]),
      word_next: Rule::new([Fg(Standard(Green))]),
      hunk: Rule::new(
        [Bold],
        pre=affix(b"@|", black_on(Bright(Black))),
        suf=Affix::new(
          b" ============================================================",
        ),
      ),
      header_prev: Rule::new([Bold], pre=affix(b"------ ", [Fg(Standard(Red))])),
      header_next: Rule::new([Bold], pre=affix(b"++++++ ", [Fg(Standard(Green))])),
      moved_from_prev: Rule::new(
        [Fg(Standard(Magenta))],
        pre=affix(b"<|", black_on(Standard(Magenta))),
      ),
      moved_to_next: Rule::new(
        [Fg(Standard(Cyan))],
        pre=affix(b">|", black_on(Standard(Cyan))),
      ),
      removed_in_move: Rule::new(
        [Fg(Standard(Red))],
        pre=affix(b">|", black_on(Standard(Red))),
      ),
      added_in_move: Rule::new(
        [Fg(Standard(Green))],
        pre=affix(b">|", black_on(Standard(Green))),
      ),
      line_unified_in_move: Rule::new([], pre=affix(b">|", black_on(Standard(Yellow)))),
    },
    float_tolerance: None,
    produce_unified_lines: true,
    unrefined: false,
    keep_ws: false,
    find_moves: false,
    split_long_lines: false,
    interleave: true,
    assume_text: false,
    context: DEFAULT_CONTEXT,
    line_big_enough: DEFAULT_LINE_BIG_ENOUGH,
    word_big_enough: DEFAULT_WORD_BIG_ENOUGH,
    shallow: false,
    quiet: false,
    double_check: false,
    mask_uniques: false,
    prev_alt: None,
    next_alt: None,
    location_style: Diff,
    warn_if_no_trailing_newline_in_both: WARN_IF_NO_TRAILING_NEWLINE_IN_BOTH_DEFAULT,
    side_by_side: None,
    width_override: None,
  }
}
