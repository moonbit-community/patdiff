///|
pub const DEFAULT_REFINE_LINE_LENGTH = 78

///|
const MIN_COL_WIDTH = 60

///|
fn is_space(c : Byte) -> Bool {
  @bstr.is_whitespace(c)
}

///|
/// Strips whitespace from a line and collapses each inner run to one space.
pub fn remove_ws(s : Bytes) -> Bytes {
  let buf = Buffer(size_hint=s.length())
  let mut in_ws = false
  let mut found_char = false
  for ch in s {
    if is_space(ch) {
      in_ws = true
    } else {
      if in_ws && found_char {
        buf.write_byte(b' ')
      }
      buf.write_byte(ch)
      in_ws = false
      found_char = true
    }
  }
  buf.contents()
}

///|
/// Whether some line of `s` is entirely whitespace.
fn is_ws(s : Bytes) -> Bool {
  let mut all_ws = true
  for c in s {
    if c == b'\n' {
      if all_ws {
        return true
      }
      all_ws = true
    } else if !is_space(c) {
      all_ws = false
    }
  }
  all_ws
}

///|
fn is_delim(c : Byte) -> Bool {
  match c {
    b'"'
    | b'{'
    | b'}'
    | b'['
    | b']'
    | b'#'
    | b','
    | b'.'
    | b';'
    | b'('
    | b')'
    | b'_' => true
    _ => false
  }
}

///|
fn is_punct(c : Byte) -> Bool {
  match c {
    b'='
    | b'`'
    | b'+'
    | b'-'
    | b'/'
    | b'!'
    | b'@'
    | b'$'
    | b'%'
    | b'^'
    | b'&'
    | b'*'
    | b':'
    | b'|'
    | b'<'
    | b'>' => true
    _ => false
  }
}

///|
/// The end of the delimiter starting at `i`, if there is one: a single `delim`,
/// a run of `punct`, a run of whitespace or a whole ANSI SGR sequence. We don't
/// want to split up ANSI color sequences, so they get through intact.
fn match_word_delimiter(s : Bytes, i : Int32) -> Int32? {
  let n = s.length()
  let c = s[i]
  let run = (f : (Byte) -> Bool) => {
    let mut j = i + 1
    while j < n && f(s[j]) {
      j += 1
    }
    j
  }
  if is_delim(c) {
    Some(i + 1)
  } else if is_punct(c) {
    Some(run(is_punct))
  } else if is_space(c) {
    Some(run(is_space))
  } else if c == 0x1B && i + 1 < n && s[i + 1] == b'[' {
    let mut j = i + 2
    while j < n && (s[j] == b';' || (s[j] >= b'0' && s[j] <= b'9')) {
      j += 1
    }
    if j < n && s[j] == b'm' {
      Some(j + 1)
    } else {
      None
    }
  } else {
    None
  }
}

///|
/// Split a string into tokens, delimiters included.
fn split(s : Bytes, keep_ws~ : Bool) -> Array[Bytes] {
  let s = if keep_ws { s } else { @bstr.rstrip(s) }
  if s.is_empty() && keep_ws {
    return [b""]
  }
  let tokens = []
  let mut text_start = 0
  let mut i = 0
  while i < s.length() {
    match match_word_delimiter(s, i) {
      Some(end) => {
        if text_start < i {
          tokens.push(@bstr.sub(s, text_start, i))
        }
        tokens.push(@bstr.sub(s, i, end))
        i = end
        text_start = end
      }
      None => i += 1
    }
  }
  if text_start < s.length() {
    tokens.push(@bstr.sub(s, text_start, s.length()))
  }
  tokens
}

///|
/// Ensures that the tokens passed to patience diff do not include whitespace.
/// Whitespace is appended to words, and then removed by `transform` later on.
/// The point is to make the semantic cleanup go well: we don't want whitespace
/// matches to count as part of the length of a match.
fn whitespace_ignorant_split(s : Bytes) -> Array[Bytes] {
  if s.is_empty() {
    return []
  }
  let groups = []
  let group = []
  for token in split(s, keep_ws=false) {
    group.push(token)
    if !token.iter().any(is_space) {
      groups.push(@bstr.concat(group))
      group.clear()
    }
  }
  if !group.is_empty() {
    groups.push(@bstr.concat(group))
  }
  groups
}

///|
/// Width available for rendering side-by-side output.
pub fn output_width(
  width_override? : Int32,
  platform~ : Platform = Platform::without_unix(),
) -> Int32 {
  let console = (platform.console_width)()
  match (width_override, console, platform.am_running_test) {
    // Since we often render diffs indented by one (whenever we have multiple
    // hunks to display), subtracting 1 helps to ensure that we don't exceed the
    // width of the terminal we're printing to.
    (Some(width), Some(console), false) if width >= console => width - 1
    (Some(width), _, _) => width
    (None, Some(console), false) => console - 1
    (None, Some(console), true) => console
    (None, None, _) => default_double_column_width
  }
}

///|
fn format_range(
  rules : Rules,
  output : Output,
  range : @pd.Range[Bytes],
) -> @pd.Range[Bytes] {
  let formatted = (ar : Array[Bytes], rule : Rule, refined : Bool) => {
    [
      for x in ar => apply_rule(x, rule~, output~, refined~)
    ]
  }
  match range {
    Same(ar) =>
      Same(
        [
          for pair in ar => {
            let app = x => {
              apply_rule(x, rule=rules.line_same, output~, refined=false)
            }
            (app(pair.0), app(pair.1))
          }
        ],
      )
    Next(ar, move_kind) => {
      let rule = match move_kind {
        Some(Move(_)) => rules.moved_to_next
        Some(WithinMove(_)) => rules.added_in_move
        None => rules.line_next
      }
      Next(formatted(ar, rule, false), move_kind)
    }
    Prev(ar, move_kind) => {
      let rule = match move_kind {
        Some(Move(_)) => rules.moved_from_prev
        Some(WithinMove(_)) => rules.removed_in_move
        None => rules.line_prev
      }
      Prev(formatted(ar, rule, false), move_kind)
    }
    Unified(ar, move_id) => {
      let rule = match move_id {
        None => rules.line_unified
        Some(_) => rules.line_unified_in_move
      }
      Unified(formatted(ar, rule, true), move_id)
    }
    Replace(ar1, ar2, move_id) => {
      let (prev_rule, next_rule) = match move_id {
        None => (rules.line_prev, rules.line_next)
        Some(_) => (rules.removed_in_move, rules.added_in_move)
      }
      Replace(
        formatted(ar1, prev_rule, true),
        formatted(ar2, next_rule, true),
        move_id,
      )
    }
  }
}

///|
fn ranges_to_strings(
  rules~ : Rules,
  output~ : Output,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[@pd.Hunk[Bytes]] {
  [
    for hunk in hunks => {
      {
        ..hunk,
        ranges: [
          for range in hunk.ranges => format_range(rules, output, range)
        ],
      }
    }
  ]
}

///|
/// Renders each line for a single-column diff, preserving the structure of the
/// hunk list (which usually comes from `diff` or `refine`).
pub fn build_unified(
  annotation_gutter~ : AnnotationGutter = AnnotationGutter::empty(),
  rules~ : Rules,
  output~ : Output,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[Array[Bytes]] {
  let formatted_hunks = ranges_to_strings(rules~, output~, hunks)
  let blocks : Array[Array[Bytes]] = []
  iter_with_line_info(
    f_hunk_break=_ => blocks.push([]),
    f_line=(side, line) => {
      blocks[blocks.length() - 1].push((annotation_gutter.render)(side) + line)
    },
    formatted_hunks,
  )
  blocks
}

///|
/// Print a hunk list (usually from `diff` or `refine`) as a single-column diff.
pub fn print_unified(
  print_global_header~ : Bool = true,
  file_names~ : (FileName, FileName),
  rules~ : Rules,
  output~ : Output,
  print~ : (Bytes) -> Unit,
  location_style~ : LocationStyle,
  platform~ : Platform = Platform::without_unix(),
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Unit {
  print_output(
    output,
    print_global_header~,
    file_names~,
    rules~,
    print~,
    location_style~,
    platform~,
    ranges_to_strings(rules~, output~, hunks),
  )
}

///|
/// A right-aligned number followed by a space.
fn line_num_text(line_num : Int32?, len~ : Int32) -> Bytes {
  let n = match line_num {
    None => b""
    Some(n) => @bstr.of_int(n)
  }
  @bstr.pad_left(n, len) + b" "
}

///|
fn[A] max_line_number(hunks : ArrayView[@pd.Hunk[A]]) -> Int32 {
  let mut m = 0
  for hunk in hunks {
    m = @cmp.maximum(m, hunk.prev_start + hunk.prev_size - 1)
    m = @cmp.maximum(m, hunk.next_start + hunk.next_size - 1)
  }
  m
}

///|
fn get_gutters(
  wrapped~ : Bool = false,
  rules~ : Rules,
  output~ : Output,
  line : LineInfo,
) -> (Bytes, Bytes) {
  let empty = @bstr.spaces(rules.line_same.pre.text.length())
  if wrapped {
    // No gutter if the text wrapped from a previous line.
    return (empty, empty)
  }
  let gutter_for = rule => apply_rule(b"", rule~, output~, refined=false)
  match line {
    Same(prev, next) => {
      let gutter = if prev.any_non_same() || next.any_non_same() {
        gutter_for(rules.line_unified)
      } else {
        gutter_for(rules.line_same)
      }
      (gutter, gutter)
    }
    Prev(_, None) => (gutter_for(rules.line_prev), empty)
    Prev(_, _) => (gutter_for(rules.moved_from_prev), empty)
    Next(_, None) => (empty, gutter_for(rules.line_next))
    Next(_, _) => (empty, gutter_for(rules.moved_to_next))
  }
}

///|
fn get_diff_style(
  rules~ : Rules,
  output~ : Output,
  line : LineInfo,
) -> (Tag, Bytes) -> Bytes {
  let apply = (rule, str) => apply_rule(str, rule~, output~, refined=false)
  match line {
    Same(_, _) | Prev(_, None) | Next(_, None) =>
      (tag, str) => {
        match tag {
          Prev => apply(rules.word_prev, str)
          Same => apply(rules.word_same_unified, str)
          Next => apply(rules.word_next, str)
        }
      }
    Prev(_, Some(_)) =>
      (tag, str) => {
        match tag {
          Prev => apply(rules.word_prev, str)
          Same => apply(rules.moved_from_prev.strip_prefix(), str)
          // Shouldn't be called, but returning the word seems safe.
          Next => str
        }
      }
    Next(_, Some(_)) =>
      (tag, str) => {
        match tag {
          // Shouldn't be called, but returning the word seems safe.
          Prev => str
          Same => apply(rules.moved_to_next.strip_prefix(), str)
          Next => apply(rules.word_next, str)
        }
      }
  }
}

///|
fn render_side_by_side_line(
  line_num_width~ : Int32 = 0,
  annotation_gutter~ : AnnotationGutter = AnnotationGutter::empty(),
  rules~ : Rules,
  output~ : Output,
  wrap_or_truncate~ : WrapOrTruncate,
  pane_cols~ : Int32,
  line : LineInfo,
) -> Array[(Bytes, Bytes)] {
  let annotation_width = annotation_gutter.width
  let render_annotation = annotation_gutter.render
  let prefix_column_width = rules.line_same.pre.text.length()
  let width = if line_num_width <= 0 {
    pane_cols - prefix_column_width - annotation_width
  } else {
    pane_cols - prefix_column_width - line_num_width - 1 - annotation_width
  }
  let lines : Array[(Line, Line)] = match wrap_or_truncate {
    Wrap => [ for l in line.wrap(width~) => l.lines() ]
    Truncate => [line.truncate(width~).lines()]
    Neither => [line.lines()]
  }
  let (prev_line_num, next_line_num) = line.numbers()
  let blank_annotation = @bstr.spaces(annotation_width)
  // A `Same` line info with non-`Same` segments is a `Replace` pair collapsed by
  // `align_replace_lines`; render it as `Prev` left / `Next` right.
  let pane_annotations = match line {
    Prev(_, _) =>
      match prev_line_num {
        Some(line) => (render_annotation(Prev(line~)), blank_annotation)
        None => (blank_annotation, blank_annotation)
      }
    Next(_, _) =>
      match next_line_num {
        Some(line) => (blank_annotation, render_annotation(Next(line~)))
        None => (blank_annotation, blank_annotation)
      }
    Same(prev_segs, next_segs) =>
      match (prev_line_num, next_line_num) {
        (Some(prev), Some(next)) if prev_segs.any_non_same() ||
          next_segs.any_non_same() =>
          (
            render_annotation(Prev(line=prev)),
            render_annotation(Next(line=next)),
          )
        (Some(prev), Some(next)) => {
          let s = render_annotation(Same(prev~, next~))
          (s, s)
        }
        _ => (blank_annotation, blank_annotation)
      }
  }
  let style = get_diff_style(rules~, output~, line)
  [
    for i, item in lines => {
      let (left, right) = item
      let wrapped = i > 0
      let (lnum, rnum) = if line_num_width <= 0 {
        (b"", b"")
      } else {
        (
          line_num_text(left.line_number, len=line_num_width),
          line_num_text(right.line_number, len=line_num_width),
        )
      }
      let (lannot, rannot) = if wrapped {
        (blank_annotation, blank_annotation)
      } else {
        pane_annotations
      }
      let (lgut, rgut) = get_gutters(wrapped~, rules~, output~, line)
      let lpad = @bstr.spaces(width - left.width())
      let ltext = left.styled_string(output~, style~)
      let rtext = right.styled_string(output~, style~)
      (
        lannot + lnum + lgut + ltext + lpad,
        @bstr.rstrip(rannot + rnum + rgut + rtext),
      )
    }
  ]
}

///|
/// Renders both sides of each line for a double-column diff, preserving the
/// structure of the hunk list (which usually comes from `refine_structured`).
pub fn build_side_by_side(
  annotation_gutter? : AnnotationGutter,
  width_override? : Int32,
  include_line_numbers~ : Bool = true,
  rules~ : Rules,
  wrap_or_truncate~ : WrapOrTruncate,
  output~ : Output,
  platform~ : Platform = Platform::without_unix(),
  hunks : ArrayView[StructuredHunk],
) -> Array[Array[(Bytes, Bytes)]] {
  // Need one character for the center divider.
  let pane_cols = (output_width(width_override?, platform~) - 1) / 2
  let pane_cols = @cmp.maximum(pane_cols, MIN_COL_WIDTH)
  let line_num_width = if include_line_numbers {
    max_line_number(hunks).to_string().length()
  } else {
    0
  }
  let blocks = []
  for hunk in hunks_to_lines(hunks) {
    let lines = []
    for line in hunk {
      lines.push_iter(
        render_side_by_side_line(
          line,
          annotation_gutter?,
          rules~,
          output~,
          pane_cols~,
          line_num_width~,
          wrap_or_truncate~,
        ).iter(),
      )
    }
    blocks.push(lines)
  }
  blocks
}

///|
fn make_divider(output : Output) -> Bytes {
  match output {
    Ansi | Html => b"\xe2\x94\x82"
    Ascii => b"|"
  }
}

///|
fn render_filenames(
  annotation_gutter~ : AnnotationGutter = AnnotationGutter::empty(),
  prev_file~ : FileName,
  next_file~ : FileName,
  pane_cols~ : Int32,
  output~ : Output,
  rules~ : Rules,
  line_num_width~ : Int32,
) -> Array[Bytes] {
  let annotation_width = annotation_gutter.width
  let cols_available = pane_cols - line_num_width - annotation_width
  let prefix = @bstr.spaces(annotation_width + line_num_width)
  let middle_divider = make_divider(output)
  let render_file_name = (rule, file : FileName) => {
    apply_rule(b"", rule~, output~, refined=false) + file.display_name()
  }
  // Add a header block with the file names.
  let prev = render_file_name(rules.line_prev, prev_file)
  let next = render_file_name(rules.line_next, next_file)
  match output {
    Ansi | Ascii =>
      [
        for
          pair in @ansi_text.to_double_column(
            width=cols_available,
            left=prev,
            right=next,
          ) => prefix + pair.0 + middle_divider + prefix + pair.1
      ]
    Html => {
      let buff = @bstr.spaces(pane_cols - prev_file.display_name().length())
      // Don't try to use ansi_text to wrap HTML!
      [prefix + prev + buff + middle_divider + prefix + next]
    }
  }
}

///|
/// Print a hunk list, usually from `refine_structured`, as a double-column diff.
pub fn print_side_by_side(
  annotation_gutter? : AnnotationGutter,
  width_override? : Int32,
  file_names? : (FileName, FileName),
  rules~ : Rules,
  wrap_or_truncate~ : WrapOrTruncate,
  output~ : Output,
  print~ : (Bytes) -> Unit,
  platform~ : Platform = Platform::without_unix(),
  hunks : ArrayView[StructuredHunk],
) -> Unit {
  let lines = build_side_by_side(
    annotation_gutter?,
    width_override?,
    rules~,
    wrap_or_truncate~,
    output~,
    platform~,
    hunks,
  )
  if output is Html {
    print(b"<pre style=\"font-family:consolas,monospace\">")
  }
  let middle_divider = make_divider(output)
  if file_names is Some((prev_file, next_file)) {
    let line_num_width = max_line_number(hunks).to_string().length() + 1
    let pane_cols = (output_width(width_override?, platform~) - 1) / 2
    render_filenames(
      annotation_gutter?,
      prev_file~,
      next_file~,
      pane_cols~,
      output~,
      rules~,
      line_num_width~,
    ).each(print)
  }
  for block in lines {
    for pair in block {
      print(pair.0 + middle_divider + pair.1)
    }
  }
  if output is Html {
    print(b"</pre>")
  }
}

///|
/// `(indentation width, index of first non-indentation byte)`.
fn indentation(line : Bytes) -> (Int32, Int32) {
  let mut n = 0
  for i, c in line {
    match c {
      b' ' => n += 1
      // tabs count for 4 spaces
      b'\t' => n += 4
      _ => return (n, i)
    }
  }
  (n, line.length())
}

///|
/// Order of priority is roughly:
/// 1. low indentation for second line
/// 2. lower indentation for second line than first
/// 3. bonus points for certain patterns at the (non-whitespace) start of the line
///
/// But it isn't priority, we just add things. We try to counteract failures for
/// the case where the line below the boundary starts with e.g. `;;` by removing
/// the "decreasing indentation bonus" in that case.
fn score_line(side : @pd.Side, line1 : Bytes, line2 : Bytes) -> Int32 {
  let (i1, start_of_1) = indentation(line1)
  let (i2, start_of_2) = indentation(line2)
  let some_lines_are_blank = line1.is_empty() || line2.is_empty()
  let base_score = {
    let i2 = if some_lines_are_blank { @cmp.maximum(i1, i2) } else { i2 }
    @cmp.maximum(-90, 90 - i2 * 2)
  }
  let decreasing_indentation_bonus = if some_lines_are_blank {
    0
  } else {
    // This hopefully helps us prefer a diff like `end [ module ... end ]` to one
    // like `[ end module ... ] end`, where [] marks the boundary of the diff.
    let bonus = if i1 == i2 {
      match side {
        Left => 1
        Right => 0
      }
    } else {
      i1 - i2
    }
    @cmp.minimum(@cmp.maximum(bonus, -2), 3)
  }
  // `above` picks the line before the boundary and `below` the one after.
  // `only` restricts the bonus to one boundary of the diff region. The bonus
  // applies if `str` is at the start of the line, after indentation.
  let bonus = fn(
    n : Int32,
    above : Bool,
    only : @pd.Side?,
    str : Bytes,
  ) -> Int32 {
    let (line, i) = if above {
      (line1, start_of_1)
    } else {
      (line2, start_of_2)
    }
    let applies = match only {
      None => true
      Some(only) => only == side
    }
    if applies && @bstr.is_substring_at(line, i, str) {
      n
    } else {
      0
    }
  }
  let ending_token = @cmp.minimum(-1, -decreasing_indentation_bonus)
  let bonus_for_chars = bonus(1, false, None, b"((") + // start of record bonus
    bonus(3, false, None, b"(") +
    bonus(1, true, Some(Right), b"}") +
    bonus(-1, false, None, b"}") +
    bonus(1, false, None, b"{") +
    // XML. Big bonus here as we prefer to break between </ and < despite equal
    // indentation.
    bonus(5, true, None, b"</") +
    bonus(-4, false, Some(Left), b"</") + // discount for starting diff on a </...>
    bonus(3, false, None, b"<") +
    bonus(2, false, None, b"*") + // heading
    bonus(1, false, None, b"-") + // bullet point
    bonus(3, true, Some(Right), b";;") +
    bonus(1, true, Some(Left), b";;") +
    bonus(4, false, Some(Left), b"let") +
    bonus(-1, false, Some(Left), b"let%") +
    bonus(2, false, Some(Left), b"let%test") +
    bonus(2, false, Some(Left), b"let%expect") +
    bonus(2, false, Some(Right), b"let") +
    bonus(1, true, None, b"in") +
    bonus(4, false, Some(Left), b"module") +
    bonus(3, true, Some(Right), b"end") +
    // In these cases, we typically get decreasing indentation but we want the
    // ending token (e.g. ;;) above the boundaries.
    bonus(ending_token, false, None, b";;") +
    bonus(ending_token, false, None, b"end") +
    // starting on a blank line gives bonus
    (if start_of_2 >= line2.length() { 2 } else { 0 })
  base_score + decreasing_indentation_bonus + bonus_for_chars
}

///|
priv struct RangeInfo {
  range_index : Int32
  size_of_range : Int32
  replace_id : Int32?
}

///|
/// Tracks the state of `Replace` ranges when we explode them into a `Prev` and a
/// `Next`.
priv struct RangeWithReplacesInfo {
  hunk_index : Int32
  former_replace : Bool
}

///|
fn sum_of_lengths(lines : ArrayView[Bytes]) -> Int32 {
  lines.fold(init=0, (acc, line) => acc + line.length())
}

///|
fn max_similarity(a : RangeInfo, b : RangeInfo) -> Double {
  let a_size = a.size_of_range.to_double()
  let b_size = b.size_of_range.to_double()
  @cmp.minimum(a_size, b_size) / @cmp.maximum(a_size, b_size)
}

///|
/// Index of the last element of `sorted` no bigger than `key`.
fn last_at_most(
  sorted : ArrayView[(RangeInfo, Array[Bytes])],
  key : RangeInfo,
) -> Int32? {
  let mut lo = 0
  let mut hi = sorted.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if sorted[mid].0.size_of_range <= key.size_of_range {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo == 0 {
    None
  } else {
    Some(lo - 1)
  }
}

///|
const MINIMUM_MATCH_PERC : Double = 0.7

///|
const MINIMUM_LINES = 3

///|
priv struct MoveInfo {
  move_index : @pd.MoveId
  mut lines_to_trim_at_beg : Int32?
  mut lines_to_trim_at_end : Int32?
}

///|
/// Finds `Prev` and `Next` ranges (including halves of `Replace` ranges) that
/// are similar enough to be a moved block of lines.
pub fn find_moves(
  line_big_enough~ : Int32,
  keep_ws~ : Bool,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[@pd.Hunk[Bytes]] {
  // Rewrite `Replace` ranges as a `Prev` and `Next` so we can consider them for
  // moves, and extract all ranges from the hunks so they're easier to work with.
  let all_ranges : Array[(RangeWithReplacesInfo, @pd.Range[Bytes])] = []
  let replace_ids : Array[Int32?] = []
  let mut next_replace_id = 0
  for hunk_index, hunk in hunks {
    for range in hunk.ranges {
      match range {
        Replace(prev, next, None) => {
          let info = RangeWithReplacesInfo::{
            hunk_index,
            former_replace: true,
          }
          all_ranges.push((info, Prev(prev, None)))
          all_ranges.push((info, Next(next, None)))
          replace_ids.push(Some(next_replace_id))
          replace_ids.push(Some(next_replace_id))
          next_replace_id += 1
        }
        _ => {
          all_ranges.push(({ hunk_index, former_replace: false, }, range))
          replace_ids.push(None)
        }
      }
    }
  }
  let prev_ranges : Array[(RangeInfo, Array[Bytes])] = []
  let next_heap : PairingHeap[(RangeInfo, Array[Bytes])] = PairingHeap::new((
    a,
    b,
  ) => a.0.size_of_range.compare(b.0.size_of_range))
  for range_index, item in all_ranges {
    let replace_id = replace_ids[range_index]
    match item.1 {
      Prev(contents, None) if contents.length() >= MINIMUM_LINES =>
        prev_ranges.push(
          (
            {
              range_index,
              size_of_range: sum_of_lengths(contents),
              replace_id,
            },
            contents,
          ),
        )
      Next(contents, None) if contents.length() >= MINIMUM_LINES =>
        next_heap.add(
          (
            {
              range_index,
              size_of_range: sum_of_lengths(contents),
              replace_id,
            },
            contents,
          ),
        )
      _ => ()
    }
  }
  // Bail out if too expensive.
  if prev_ranges.length() * next_heap.length > 40000 {
    return hunks.to_owned()
  }
  let prevs_used : Map[Int32, MoveInfo] = Map([])
  let nexts_to_replace : Map[Int32, Array[@pd.Range[Bytes]]] = Map([])
  // Find ranges that are similar enough to be moves.
  let next_ranges = []
  while next_heap.pop() is Some(item) {
    next_ranges.push(item)
  }
  let mut move_id : @pd.MoveId = 0
  for prev_item in prev_ranges {
    let (prev_location, prev_contents) = prev_item
    let starting_index = last_at_most(next_ranges, prev_location).unwrap_or(
      next_ranges.length() - 1,
    )
    let starting_index = @cmp.maximum(starting_index, 0)
    let mut left_index = starting_index
    let mut right_index = starting_index + 1
    let next_closest_range = () => {
      let left_range = if left_index >= 0 && left_index < next_ranges.length() {
        Some(next_ranges[left_index])
      } else {
        None
      }
      let right_range = if right_index >= 0 &&
        right_index < next_ranges.length() {
        Some(next_ranges[right_index])
      } else {
        None
      }
      match (left_range, right_range) {
        (None, None) => None
        (Some(_), None) => {
          left_index -= 1
          left_range
        }
        (None, Some(_)) => {
          right_index += 1
          right_range
        }
        (Some(left), Some(right)) =>
          if max_similarity(left.0, prev_location) >=
            max_similarity(right.0, prev_location) {
            left_index -= 1
            left_range
          } else {
            right_index += 1
            right_range
          }
      }
    }
    let mut best_match_so_far : (Double, RangeInfo, Array[Bytes])? = None
    while next_closest_range() is Some(next_item) {
      let (next_location, next_contents) = next_item
      let similarity = max_similarity(prev_location, next_location)
      // If this range can't possibly have the required similarity then none of
      // the subsequent ranges can either, so stop our search here.
      if similarity < MINIMUM_MATCH_PERC {
        break
      }
      if best_match_so_far is Some((best_match_ratio, _, _)) &&
        similarity < best_match_ratio {
        break
      }
      // Don't use the two parts of the same replace for moves.
      let same_replace = match
        (next_location.replace_id, prev_location.replace_id) {
        (Some(next_id), Some(prev_id)) => next_id == prev_id
        _ => false
      }
      if nexts_to_replace.contains(next_location.range_index) || same_replace {
        continue
      }
      // `match_ratio` just does naive string comparisons per line, so strip
      // leading and trailing whitespace.
      let match_ratio = @pd.match_ratio(
        [
          for line in prev_contents => @bstr.strip(line)
        ],
        [
          for line in next_contents => @bstr.strip(line)
        ],
      )
      match best_match_so_far {
        None =>
          if match_ratio >= MINIMUM_MATCH_PERC {
            best_match_so_far = Some(
              (match_ratio, next_location, next_contents),
            )
          }
        Some((best_match_ratio, _, _)) =>
          if match_ratio > best_match_ratio {
            best_match_so_far = Some(
              (match_ratio, next_location, next_contents),
            )
          }
      }
    }
    guard best_match_so_far is Some((_, next_location, next_contents)) else {
      continue
    }
    let hunk = diff_singleton(
      line_big_enough~,
      keep_ws~,
      prev_contents,
      next_contents,
    )
    let move_index = move_id
    let move_info = MoveInfo::{
      move_index,
      lines_to_trim_at_beg: None,
      lines_to_trim_at_end: None,
    }
    prevs_used[prev_location.range_index] = move_info
    move_id += 1
    let num_ranges = hunk.ranges.length()
    let is_on_edge = i => i == 0 || i == num_ranges - 1
    let replacement : Array[@pd.Range[Bytes]] = []
    for i, range in hunk.ranges {
      match range {
        Same(contents) =>
          replacement.push(
            Next([ for pair in contents => pair.1 ], Some(Move(move_index))),
          )
        Replace(prev, next, _) =>
          replacement.push(Replace(prev, next, Some(move_index)))
        Prev(prev, _) =>
          if is_on_edge(i) {
            if i == 0 {
              move_info.lines_to_trim_at_beg = Some(prev.length())
            }
            if i == num_ranges - 1 {
              move_info.lines_to_trim_at_end = Some(prev.length())
            }
          } else {
            replacement.push(Prev(prev, Some(WithinMove(move_index))))
          }
        Next(next, _) =>
          replacement.push(
            Next(
              next,
              if is_on_edge(i) {
                None
              } else {
                Some(WithinMove(move_index))
              },
            ),
          )
        Unified(contents, _) =>
          replacement.push(Unified(contents, Some(move_index)))
      }
    }
    nexts_to_replace[next_location.range_index] = replacement
  }
  // Update the `Next` ranges.
  let ranges : Array[(RangeWithReplacesInfo, @pd.Range[Bytes])] = []
  for range_index, item in all_ranges {
    let (range_data, range) = item
    match (prevs_used.get(range_index), nexts_to_replace.get(range_index)) {
      // This means we think the range is both a next and prev which is impossible.
      (Some(_), Some(_)) => abort("find_moves: range is both next and prev")
      (None, None) => ranges.push(item)
      (Some(move_info), None) => {
        // We should never reference anything except a `Prev` that hasn't been
        // moved.
        guard range is Prev(contents, None) else {
          abort("find_moves: expected an unmoved Prev range")
        }
        let trim_beg = move_info.lines_to_trim_at_beg.unwrap_or(0)
        let trim_end = move_info.lines_to_trim_at_end.unwrap_or(0)
        let len = contents.length()
        let range_data = { ..range_data, former_replace: false, }
        if trim_beg != 0 {
          ranges.push((range_data, Prev(contents[0:trim_beg].to_owned(), None)))
        }
        ranges.push(
          (
            range_data,
            Prev(
              contents[trim_beg:len - trim_end].to_owned(),
              Some(Move(move_info.move_index)),
            ),
          ),
        )
        if trim_end != 0 {
          ranges.push(
            (range_data, Prev(contents[len - trim_end:].to_owned(), None)),
          )
        }
      }
      (None, Some(ranges_to_replace)) => {
        let range_data = { ..range_data, former_replace: false, }
        for range in ranges_to_replace {
          ranges.push((range_data, range))
        }
      }
    }
  }
  // Recover any `Replace` ranges we broke up if we didn't use them for moves.
  let final_ranges : Array[(RangeWithReplacesInfo, @pd.Range[Bytes])] = []
  let mut i = 0
  while i < ranges.length() {
    let item = ranges[i]
    match (item, ranges.get(i + 1)) {
      (
        ({ former_replace: true, hunk_index, }, Prev(prev, None)),
        Some(({ former_replace: true, .. }, Next(next, None))),
      ) => {
        final_ranges.push(
          ({ former_replace: false, hunk_index, }, Replace(prev, next, None)),
        )
        i += 2
      }
      _ => {
        final_ranges.push(item)
        i += 1
      }
    }
  }
  // Place the ranges in the correct hunks.
  let mut position = 0
  [
    for hunk_index, hunk in hunks => {
      let hunk_ranges = []
      while position < final_ranges.length() &&
            final_ranges[position].0.hunk_index == hunk_index {
        hunk_ranges.push(final_ranges[position].1)
        position += 1
      }
      { ..hunk, ranges: hunk_ranges, }
    }
  ]
}

///|
/// `find_moves`, for `diff`, whose label of the same name shadows it.
fn find_moves_impl(
  line_big_enough~ : Int32,
  keep_ws~ : Bool,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[@pd.Hunk[Bytes]] {
  find_moves(line_big_enough~, keep_ws~, hunks)
}

///|
fn line_transform(keep_ws : Bool) -> (Bytes) -> Bytes {
  if keep_ws {
    x => x
  } else {
    remove_ws
  }
}

///|
/// Diff two sets of lines into a single hunk.
fn diff_singleton(
  line_big_enough~ : Int32,
  keep_ws~ : Bool,
  prev : Array[Bytes],
  next : Array[Bytes],
) -> @pd.Hunk[Bytes] {
  // Negative `context` returns a singleton hunk.
  @pd.get_hunks(
    transform=line_transform(keep_ws),
    context=-1,
    big_enough=line_big_enough,
    max_slide=100,
    score=score_line,
    prev~,
    next~,
  )[0]
}

///|
/// A list of hunks describing the comparison between `prev` and `next`.
pub fn diff(
  context~ : Int32,
  line_big_enough~ : Int32,
  keep_ws~ : Bool,
  find_moves~ : Bool,
  prev~ : ArrayView[Bytes],
  next~ : ArrayView[Bytes],
) -> Array[@pd.Hunk[Bytes]] {
  let should_find_moves = find_moves
  let hunks = @pd.get_hunks(
    transform=line_transform(keep_ws),
    context~,
    big_enough=line_big_enough,
    max_slide=100,
    score=score_line,
    prev~,
    next~,
  )
  if should_find_moves {
    find_moves_impl(line_big_enough~, keep_ws~, hunks)
  } else {
    hunks
  }
}
