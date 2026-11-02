///|
/// A line of one side of a side-by-side diff. A line in the previous file will
/// only ever have `Prev` and `Same` segments while lines in the next file will
/// only have `Same` and `Next`, so all deletions are denoted on the left and all
/// additions on the right.
pub(all) struct Line {
  /// The line number in the original file. Only `None` for an empty line
  /// produced when padding to match alignment.
  line_number : Int?
  contents : Array[(Tag, @ansi_text.AnsiText)]
} derive(Debug, Eq)

///|
pub fn Line::to_bytes(self : Line) -> Bytes {
  @bstr.concat([ for segment in self.contents => @ansi_text.to_unstyled(segment.1) ])
}

///|
/// `style` gets applied to each phrase, then phrases are concatenated.
pub fn Line::styled_string(
  self : Line,
  output? : Output = Ansi,
  style~ : (Tag, Bytes) -> Bytes,
) -> Bytes {
  @bstr.concat([
    for segment in self.contents => {
      let (tag, text) = segment
      match output {
        Ansi => style(tag, @ansi_text.to_bytes(text))
        Ascii | Html => style(tag, @ansi_text.to_unstyled(text))
      }
    }
  ])
}

///|
pub fn Line::any_non_same(self : Line) -> Bool {
  self.contents.iter().any(segment => !(segment.0 is Same))
}

///|
fn Line::empty() -> Line {
  { line_number: None, contents: [] }
}

///|
/// The width of the line if it were printed in the terminal.
pub fn Line::width(self : Line) -> Int {
  self.contents.fold(init=0, (acc, segment) => acc + @ansi_text.width(segment.1))
}

///|
pub fn Line::wrap(self : Line, width~ : Int) -> Array[Line] {
  let max_width = width
  if max_width <= 1 {
    abort("width is too narrow")
  }
  let lines : Array[Array[(Tag, @ansi_text.AnsiText)]] = []
  let mut curr_len = 0
  let mut curr_line : Array[(Tag, @ansi_text.AnsiText)] = []
  for segment in self.contents {
    let (tag, text) = segment
    let word_len = @ansi_text.width(text)
    if curr_len + word_len <= max_width {
      curr_len += word_len
      curr_line.push(segment)
    } else {
      let (word_start, word_rest) = @ansi_text.split(text, pos=max_width - curr_len)
      curr_line.push((tag, word_start))
      lines.push(curr_line)
      let mut rest = word_rest
      while @ansi_text.width(rest) > max_width {
        let (prefix, suffix) = @ansi_text.split(rest, pos=max_width)
        lines.push([(tag, prefix)])
        rest = suffix
      }
      curr_len = @ansi_text.width(rest)
      curr_line = [(tag, rest)]
    }
  }
  if !curr_line.is_empty() {
    lines.push(curr_line)
  }
  [
    for i, line in lines => {
      line_number: if i == 0 { self.line_number } else { None },
      contents: line,
    }
  ]
}

///|
pub fn Line::truncate(self : Line, width~ : Int) -> Line {
  let mut len = 0
  let contents = []
  for segment in self.contents {
    let (tag, text) = segment
    let text_width = @ansi_text.width(text)
    if text_width + len > width {
      contents.push((tag, @ansi_text.truncate(text, width=width - len)))
      break
    }
    len += text_width
    contents.push(segment)
  }
  { ..self, contents }
}

///|
/// A row of a side-by-side diff.
pub(all) enum LineInfo {
  Same(Line, Line)
  Prev(Line, @pd.MoveId?)
  Next(Line, @pd.MoveId?)
} derive(Debug, Eq)

///|
/// In the case of a `Same` line, it may be necessary to pad one side with empty
/// lines.
pub fn LineInfo::wrap(self : LineInfo, width~ : Int) -> Array[LineInfo] {
  match self {
    Prev(line, mv) => [ for ln in line.wrap(width~) => Prev(ln, mv) ]
    Next(line, mv) => [ for ln in line.wrap(width~) => Next(ln, mv) ]
    Same(prev, next) => {
      let prev = prev.wrap(width~)
      let next = next.wrap(width~)
      while prev.length() < next.length() {
        prev.push(Line::empty())
      }
      while next.length() < prev.length() {
        next.push(Line::empty())
      }
      [ for i, line in prev => Same(line, next[i]) ]
    }
  }
}

///|
pub fn LineInfo::truncate(self : LineInfo, width~ : Int) -> LineInfo {
  match self {
    Same(prev, next) => Same(prev.truncate(width~), next.truncate(width~))
    Prev(prev, move_id) => Prev(prev.truncate(width~), move_id)
    Next(next, move_id) => Next(next.truncate(width~), move_id)
  }
}

///|
/// Produces an empty line on one side if necessary. Move ids are dropped.
pub fn LineInfo::lines(self : LineInfo) -> (Line, Line) {
  match self {
    Same(prev, next) => (prev, next)
    Prev(prev, _) => (prev, Line::empty())
    Next(next, _) => (Line::empty(), next)
  }
}

///|
pub fn LineInfo::numbers(self : LineInfo) -> (Int?, Int?) {
  match self {
    Same(prev, next) => (prev.line_number, next.line_number)
    Prev(prev, _) => (prev.line_number, None)
    Next(next, _) => (None, next.line_number)
  }
}

///|
fn num_same(contents : ArrayView[(Tag, @ansi_text.AnsiText)]) -> Int {
  contents.fold(init=0, (count, segment) => {
    if segment.0 is Same && !@ansi_text.is_empty(segment.1) {
      count + 1
    } else {
      count
    }
  })
}

///|
fn align_replace_lines(
  get_prev_line_number~ : () -> Int?,
  get_next_line_number~ : () -> Int?,
  queue : Array[LineInfo],
  prev_lines : ArrayView[Array[(Tag, @ansi_text.AnsiText)]],
  next_lines : ArrayView[Array[(Tag, @ansi_text.AnsiText)]],
) -> Unit {
  let mut prev_index = 0
  let mut next_index = 0
  let mut num_same_words_prev = 0
  let mut num_same_words_next = 0
  let prev_line = contents => Line::{ line_number: get_prev_line_number(), contents }
  let next_line = contents => Line::{ line_number: get_next_line_number(), contents }
  while prev_index < prev_lines.length() || next_index < next_lines.length() {
    if next_index >= next_lines.length() {
      queue.push(Prev(prev_line(prev_lines[prev_index]), None))
      prev_index += 1
    } else if prev_index >= prev_lines.length() {
      queue.push(Next(next_line(next_lines[next_index]), None))
      next_index += 1
    } else {
      let prev_contents = prev_lines[prev_index]
      let next_contents = next_lines[next_index]
      let new_num_same_words_prev = num_same_words_prev + num_same(prev_contents)
      let new_num_same_words_next = num_same_words_next + num_same(next_contents)
      if new_num_same_words_prev <= num_same_words_next {
        queue.push(Prev(prev_line(prev_contents), None))
        prev_index += 1
        num_same_words_prev = new_num_same_words_prev
      } else if new_num_same_words_next <= num_same_words_prev {
        queue.push(Next(next_line(next_contents), None))
        next_index += 1
        num_same_words_next = new_num_same_words_next
      } else {
        // Evaluated in this order so that the line numbers are bumped in order.
        let left = prev_line(prev_contents)
        let right = next_line(next_contents)
        queue.push(Same(left, right))
        prev_index += 1
        next_index += 1
        num_same_words_prev = new_num_same_words_prev
        num_same_words_next = new_num_same_words_next
      }
    }
  }
}

///|
fn retag_same(
  contents : ArrayView[(Tag, @ansi_text.AnsiText)],
  tag : Tag,
) -> Array[(Tag, @ansi_text.AnsiText)] {
  [
    for segment in contents => {
      if segment.0 is Same {
        (tag, segment.1)
      } else {
        segment
      }
    }
  ]
}

///|
fn to_contents(line : ArrayView[(Tag, Bytes)]) -> Array[(Tag, @ansi_text.AnsiText)] {
  [ for segment in line => (segment.0, @ansi_text.parse(segment.1)) ]
}

///|
/// Take structured hunks and produce hunks of `LineInfo`. The elements of the
/// outer array represent the original hunks passed in and the inner elements are
/// the lines within the hunk.
pub fn hunks_to_lines(hunks : ArrayView[StructuredHunk]) -> Array[Array[LineInfo]] {
  let result : Array[Array[LineInfo]] = []
  let mut prev_line_number = 1
  let mut next_line_number = 1
  let start_of_move_in_prev : Map[Int, (Int, Int)] = Map([])
  // Since moves may have been refined we need to remember the next parts of
  // moves so we can rewrite the prev part with the changes that we found during
  // refinement.
  let nexts_by_move_id : Map[Int, Array[@pd.Range[Array[(Tag, Bytes)]]]] = Map([])
  let record_next_move = (move_id, range) => {
    match nexts_by_move_id.get(move_id) {
      None => nexts_by_move_id[move_id] = [range]
      Some(ranges) => ranges.push(range)
    }
  }
  let bump_prev = () => {
    let value = prev_line_number
    prev_line_number += 1
    Some(value)
  }
  let bump_next = () => {
    let value = next_line_number
    next_line_number += 1
    Some(value)
  }
  for hunk in hunks {
    prev_line_number = hunk.prev_start
    next_line_number = hunk.next_start
    let queue : Array[LineInfo] = []
    result.push(queue)
    for range in hunk.ranges {
      match range {
        Same(lines) =>
          for pair in lines {
            let left = Line::{ line_number: bump_prev(), contents: to_contents(pair.0) }
            let right = Line::{ line_number: bump_next(), contents: to_contents(pair.1) }
            queue.push(Same(left, right))
          }
        Prev(lines, move_kind) => {
          if move_kind is Some(WithinMove(move_id)) {
            record_next_move(move_id, range)
          }
          for line in lines {
            let contents = to_contents(line)
            match move_kind {
              None =>
                queue.push(
                  Prev(
                    {
                      line_number: bump_prev(),
                      contents: retag_same(contents, Prev),
                    },
                    None,
                  ),
                )
              Some(Move(move_id)) => {
                if !start_of_move_in_prev.contains(move_id) {
                  start_of_move_in_prev[move_id] = (
                    result.length() - 1,
                    queue.length(),
                  )
                }
                queue.push(
                  Prev({ line_number: bump_prev(), contents }, Some(move_id)),
                )
              }
              Some(WithinMove(_)) => ()
            }
          }
        }
        Next(lines, move_kind) => {
          if move_kind is Some(Move(move_id)) {
            record_next_move(move_id, range)
          }
          for line in lines {
            let contents = to_contents(line)
            let info : LineInfo = match move_kind {
              None =>
                Next(
                  {
                    line_number: bump_next(),
                    contents: retag_same(contents, Next),
                  },
                  None,
                )
              Some(Move(move_id)) =>
                Next({ line_number: bump_next(), contents }, Some(move_id))
              Some(WithinMove(move_id)) =>
                Next(
                  {
                    line_number: bump_next(),
                    contents: retag_same(contents, Next),
                  },
                  Some(move_id),
                )
            }
            queue.push(info)
          }
        }
        Replace(prev_lines, next_lines, None) =>
          align_replace_lines(
            get_prev_line_number=bump_prev,
            get_next_line_number=bump_next,
            queue,
            [ for line in prev_lines => to_contents(line) ],
            [ for line in next_lines => to_contents(line) ],
          )
        Replace(_, next_lines, Some(move_id)) => {
          record_next_move(move_id, range)
          for line in next_lines {
            queue.push(
              Next(
                { line_number: bump_next(), contents: to_contents(line) },
                Some(move_id),
              ),
            )
          }
        }
        Unified(_, _) => abort("Cannot turn unified ranges into side by side view")
      }
    }
  }
  // Rewrite prevs that were refined in moves.
  let move_ids = nexts_by_move_id.keys().to_array()
  move_ids.sort()
  for move_id in move_ids {
    guard start_of_move_in_prev.get(move_id) is Some((hunk_index, start)) else {
      abort("hunks_to_lines: move has no start in prev")
    }
    let mut line_index = start
    for range in nexts_by_move_id[move_id] {
      // Replace ranges have been refined already while Prev ranges haven't. We
      // need to turn their `Same` tags into `Prev`s.
      let amend = (prev_lines : Array[Array[(Tag, Bytes)]], rewrite_tags : Bool) => {
        for line in prev_lines {
          let contents = to_contents(line)
          if result[hunk_index][line_index] is Prev(old, move_info) {
            result[hunk_index][line_index] = Prev(
              {
                ..old,
                contents: if rewrite_tags {
                  retag_same(contents, Prev)
                } else {
                  contents
                },
              },
              move_info,
            )
          }
          line_index += 1
        }
      }
      match range {
        Prev(prev_lines, Some(_)) => amend(prev_lines, true)
        Replace(prev_lines, _, Some(_)) => amend(prev_lines, false)
        Next(lines, Some(Move(_))) => line_index += lines.length()
        Next(_, _) => ()
        _ => abort("hunks_to_lines: unexpected range in move")
      }
    }
  }
  result
}
