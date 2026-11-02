///|
/// Which side a piece of refined text came from.
#derive(Debug, Eq)
pub(all) enum Tag {
  Prev
  Same
  Next
}

///|
/// A hunk whose lines are lists of tagged segments.
pub type StructuredHunk = @pd.Hunk[Array[(Tag, Bytes)]]

///|
/// A token of refinement. `Newline(n, ws)` stands for `n` consecutive newlines
/// followed by the whitespace `ws`; this collapses consecutive whitespace as
/// tightly as possible, but some consecutive whitespace does not get collapsed.
#derive(Debug, Eq)
pub(all) enum Piece {
  Newline(Int32, Bytes?)
  Word(Bytes)
}

///|
/// Splits lines, already split into words, into an array of pieces.
fn explode_internal(
  lines : ArrayView[Array[Bytes]],
  keep_ws~ : Bool,
) -> Array[Piece] {
  let words : Array[Piece] = []
  for line in lines {
    match line {
      [hd, .. tl] => {
        if keep_ws && !hd.is_empty() && is_ws(hd) {
          words.push(Newline(1, Some(hd)))
        } else {
          words.push(Newline(1, None))
          words.push(Word(hd))
        }
        for word in tl {
          words.push(Word(word))
        }
      }
      [] => words.push(Newline(1, None))
    }
  }
  // Going backwards, look at what we've accumulated so far to see if there's any
  // whitespace that can be collapsed. The top of this stack is the leftmost piece.
  let acc : Array[Piece] = []
  for x in words.rev_iter() {
    match (acc.last(), x) {
      (Some(Newline(i, None)), Newline(j, opt)) =>
        // Collapse by summing the number of consecutive newlines.
        acc[acc.length() - 1] = Newline(i + j, opt)
      (Some(Newline(i, Some(s1))), Newline(j, opt)) =>
        // Collapse by concatenating any subsequent whitespace and summing the
        // number of consecutive newlines.
        acc[acc.length() - 1] = Newline(i + j, Some(opt.unwrap_or(b"") + s1))
      _ => acc.push(x)
    }
  }
  let pieces = acc.rev()
  // Throw away the very first newline.
  if pieces.get(0) is Some(Newline(i, opt)) {
    pieces[0] = Newline(i - 1, opt)
  }
  // Append a newline to the end, if this array has any words. Don't drop this
  // section if it includes only a single newline.
  if !pieces.is_empty() {
    pieces.push(Newline(1, None))
  }
  pieces
}

///|
/// Splits lines into an array of pieces.
pub fn explode(lines : ArrayView[Bytes], keep_ws~ : Bool) -> Array[Piece] {
  let words = if keep_ws {
    [
      for line in lines => split(line, keep_ws~)
    ]
  } else {
    [
      for line in lines => whitespace_ignorant_split(line)
    ]
  }
  explode_internal(words, keep_ws~)
}

///|
priv enum CollapseKind {
  PrevOnly
  NextOnly
}

///|
/// Takes ranges of pieces and collapses them back into lines of tagged segments.
fn collapse_structured(
  ranges : ArrayView[@pd.Range[Piece]],
  kind~ : CollapseKind,
) -> Array[Array[(Tag, Bytes)]] {
  // The kind of range currently being collapsed.
  let mut flag : Tag = Same
  // The current series of words being processed.
  let segment : Array[Bytes] = []
  // The current series of formatted segments.
  let mut line : Array[(Tag, Bytes)] = []
  let lines = []
  let finish_segment = () => {
    line.push((flag, @bstr.concat(segment)))
    segment.clear()
  }
  let newline = i => {
    for _ in 0..<i {
      finish_segment()
      lines.push(line)
      line = []
    }
  }
  for range in ranges {
    // When calling collapse, we always call `prev_only` or `next_only` first,
    // which removes all `Replace`s; `Unified`s are never produced for pieces.
    let ar : Array[Piece] = match range {
      Same(ar) => {
        flag = Same
        // Depending on what kind of collapse this is, we want only one or the
        // other of the pair.
        match kind {
          PrevOnly => [ for pair in ar => pair.0 ]
          NextOnly => [ for pair in ar => pair.1 ]
        }
      }
      Prev(ar, _) => {
        flag = Prev
        ar
      }
      Next(ar, _) => {
        flag = Next
        ar
      }
      Replace(_, _, _) | Unified(_, _) => abort("collapse: unexpected range")
    }
    for piece in ar {
      match piece {
        Newline(i, None) => newline(i)
        Newline(i, Some(s)) => {
          newline(i)
          segment.push(s)
        }
        Word(s) => segment.push(s)
      }
    }
    finish_segment()
  }
  match line {
    [] => ()
    [(_, text)] if text.is_empty() => ()
    line => {
      let text = @bstr.concat([ for pair in line => pair.1 ])
      // This branch was unreachable in regression tests, but it can't be proven
      // unreachable in all cases. Rather than fail, drop this whitespace.
      if !is_ws(text) {
        abort(
          "Invariant violated: collapse got a line not terminated with a newline",
        )
      }
    }
  }
  lines
}

///|
/// Takes ranges of pieces and collapses them back into lines, formatting
/// appropriately.
fn collapse(
  ranges : ArrayView[@pd.Range[Piece]],
  rule_same~ : Rule,
  rule_prev~ : Rule,
  rule_next~ : Rule,
  kind~ : CollapseKind,
  output~ : Output,
) -> Array[Bytes] {
  let apply = (rule, s : Bytes) => {
    if s.is_empty() {
      b""
    } else {
      apply_rule(s, rule~, output~, refined=false)
    }
  }
  [
    for line in collapse_structured(ranges, kind~) => {
      @bstr.concat(
        [
          for segment in line => {
            let (tag, word) = segment
            match tag {
              Same => apply(rule_same, word)
              Prev => apply(rule_prev, word)
              Next => apply(rule_next, word)
            }
          }
        ],
      )
    }
  ]
}

///|
/// Get the hunks from two arrays of pieces.
fn diff_pieces(
  prev_pieces~ : Array[Piece],
  next_pieces~ : Array[Piece],
  keep_ws~ : Bool,
  word_big_enough~ : Int32,
) -> Array[@pd.Hunk[Piece]] {
  let transform = (piece : Piece) => {
    match piece {
      Word(s) => if keep_ws { s } else { remove_ws(s) }
      Newline(lines, trailing) =>
        if keep_ws {
          let newlines = if lines > 0 { Bytes::make(lines, b'\n') } else { b"" }
          newlines + trailing.unwrap_or(b"")
        } else if lines == 0 {
          b""
        } else {
          b" "
        }
    }
  }
  @pd.get_hunks(
    transform~,
    context=-1,
    big_enough=word_big_enough,
    max_slide=0,
    prev=prev_pieces,
    next=next_pieces,
  )
}

///|
fn ranges_are_just_whitespace(ranges : ArrayView[@pd.Range[Piece]]) -> Bool {
  ranges
  .iter()
  .all(range => {
    match range {
      Prev(pieces, _) | Next(pieces, _) =>
        pieces
        .iter()
        .all(piece => {
          match piece {
            Word(s) => remove_ws(s).is_empty()
            Newline(_, _) => true
          }
        })
      _ => true
    }
  })
}

///|
/// Interleaves the display of minus lines and plus lines so that equal words are
/// presented close together. There is some heuristic for when we think doing
/// this improves the diff.
fn split_for_readability(
  rangelist : ArrayView[@pd.Range[Piece]],
) -> Array[Array[@pd.Range[Piece]]] {
  let ans = []
  let mut pending : Array[@pd.Range[Piece]] = []
  for range in rangelist {
    let mut split_was_executed = false
    if range is Same(seq) {
      let mut first_newline = None
      for i, pair in seq {
        if pair is (Newline(n1, ws1), Newline(n2, ws2)) && n1 != 0 && n2 != 0 {
          first_newline = Some((i, n1, ws1, n2, ws2))
          break
        }
      }
      if first_newline is Some((i, n1, ws1, n2, ws2)) &&
        seq.length() - i > TOO_SHORT_TO_SPLIT {
        pending.push(Same(seq[0:i].to_owned()))
        // A non-zero newline is required for `collapse` to work properly.
        pending.push(Same([(Newline(1, None), Newline(1, None))]))
        ans.push(pending)
        pending = []
        let suf = seq[i:].to_owned()
        suf[0] = (Newline(n1 - 1, ws1), Newline(n2 - 1, ws2))
        pending.push(Same(suf))
        split_was_executed = true
      }
    }
    if !split_was_executed {
      pending.push(range)
    }
  }
  if !pending.is_empty() {
    ans.push(pending)
  }
  ans
}

///|
fn words_of_lines(
  lines : ArrayView[Bytes],
  keep_ws~ : Bool,
) -> Array[Array[Bytes]] {
  if keep_ws {
    [
      for line in lines => split(line, keep_ws~)
    ]
  } else {
    [
      for line in lines => whitespace_ignorant_split(line)
    ]
  }
}

///|
fn word_count(lines : ArrayView[Array[Bytes]]) -> Int32 {
  lines.fold(init=0, (acc, line) => acc + line.length())
}

///|
/// Maps each break word to the first line that has it as the line's first break
/// word.
fn first_line_of_words(
  lines : ArrayView[Array[Bytes]],
  word_breaks : Map[Bytes, Bool],
) -> Map[Bytes, Int32] {
  let found = Map([])
  for i, line in lines {
    for word in line {
      if word_breaks.contains(word) {
        if !found.contains(word) {
          found[word] = i
        }
        break
      }
    }
  }
  found
}

///|
/// Turn lines into words and apply a heuristic to break up large blocks of lines
/// by relatively unique words.
///
/// Ties among equally frequent words are broken by first appearance. The OCaml
/// version breaks them by hash table order instead, so which of them get chosen,
/// and hence the layout of a very large `Replace`, can differ.
fn words_break_heuristic(
  prev_ar : ArrayView[Bytes],
  next_ar : ArrayView[Bytes],
  keep_ws~ : Bool,
) -> Array[(Array[Array[Bytes]], Array[Array[Bytes]])] {
  let target_block_size = 100
  let target_num_blocks = @cmp.minimum(prev_ar.length(), next_ar.length()) /
    target_block_size
  let prev_words = words_of_lines(prev_ar, keep_ws~)
  let next_words = words_of_lines(next_ar, keep_ws~)
  if prev_words.length() < target_block_size * 2 &&
    next_words.length() < target_block_size {
    // The `Replace` range is small enough don't apply the heuristic.
    return [(prev_words, next_words)]
  }
  // Count word frequencies.
  let word_freq : Map[Bytes, (Int32, Int32)] = Map([])
  for line in prev_words {
    for word in line {
      let (cnt, other) = word_freq.get(word).unwrap_or((0, 0))
      word_freq[word] = (cnt + 1, other)
    }
  }
  for line in next_words {
    for word in line {
      let (other, cnt) = word_freq.get(word).unwrap_or((0, 0))
      word_freq[word] = (other, cnt + 1)
    }
  }
  let prev_freq_cutoff = word_count(prev_words).to_double().sqrt().to_int()
  let next_freq_cutoff = word_count(next_words).to_double().sqrt().to_int()
  // Find all words shared between the two files and sort by least common.
  let candidates = []
  for word, counts in word_freq {
    let (cnt_prev, cnt_next) = counts
    // Don't break on words that are too common.
    if cnt_prev > 0 &&
      cnt_next > 0 &&
      cnt_prev < prev_freq_cutoff &&
      cnt_next < next_freq_cutoff {
      candidates.push((word, cnt_prev + cnt_next))
    }
  }
  let sorted = @bstr.stable_sorted_by(candidates, (a, b) => a.1.compare(b.1))
  let word_breaks : Map[Bytes, Bool] = Map([])
  for i, candidate in sorted {
    if i >= target_num_blocks {
      break
    }
    word_breaks[candidate.0] = true
  }
  let line_breaks_in_prev = first_line_of_words(prev_words, word_breaks)
  let line_breaks_in_next = first_line_of_words(next_words, word_breaks)
  let line_breaks_to_consider = []
  for word, prev in line_breaks_in_prev {
    if line_breaks_in_next.get(word) is Some(next) {
      line_breaks_to_consider.push((prev, next))
    }
  }
  let line_breaks_to_consider = @bstr.stable_sorted_by(
    line_breaks_to_consider,
    (a, b) => a.1.compare(b.1),
  )
  // Find the actual line numbers to split on.
  let line_breaks = []
  let mut last_prev = -1
  let mut last_next = -1
  for pair in line_breaks_to_consider {
    let (prev, next) = pair
    // Avoid overlapping indices and don't make small segments.
    if prev > last_prev &&
      prev - last_prev > target_block_size / 2 &&
      next - last_next > target_block_size / 2 {
      last_prev = prev
      last_next = next
      line_breaks.push(pair)
    }
  }
  line_breaks.push((prev_ar.length(), next_ar.length()))
  // Break up the arrays.
  let arrays = []
  let mut last_prev_i = 0
  let mut last_next_i = 0
  for pair in line_breaks {
    let (prev_i, next_i) = pair
    arrays.push(
      (
        prev_words[last_prev_i:prev_i].to_owned(),
        next_words[last_next_i:next_i].to_owned(),
      ),
    )
    last_prev_i = prev_i
    last_next_i = next_i
  }
  arrays
}

///|
fn line_length_so_far(len_so_far : Int32, tokens : ArrayView[Piece]) -> Int32 {
  tokens.fold(init=len_so_far, (len, token) => {
    match token {
      Newline(_, _) => 0
      Word(word) => len + word.length()
    }
  })
}

///|
fn make_newline() -> @pd.Range[Piece] {
  Same([(Newline(1, None), Newline(1, None))])
}

///|
/// Takes token pairs from `start` until we exceed `max_len` or hit a newline.
/// Returns (new length so far, new range, index of the next token, hit newline).
fn take_until_max(
  len_so_far : Int32,
  tokenpairs : Array[(Piece, Piece)],
  start : Int32,
  max_len : Int32,
) -> (Int32, @pd.Range[Piece], Int32, Bool) {
  let mut len = len_so_far
  let mut i = start
  while i < tokenpairs.length() {
    match tokenpairs[i].0 {
      Newline(_, _) =>
        return (0, Same(tokenpairs[start:i + 1].to_owned()), i + 1, true)
      Word(word) => {
        let wordlen = word.length()
        if wordlen + len > max_len && len > 0 {
          return (0, Same(tokenpairs[start:i].to_owned()), i, false)
        }
        len += wordlen
        i += 1
      }
    }
  }
  (len, Same(tokenpairs[start:].to_owned()), i, false)
}

///|
/// Produces a list of "range lists", where each range list should be displayed
/// all together in one unbroken piece before being followed by the next.
fn split_long_lines_of_ranges(
  sub_diff : ArrayView[@pd.Range[Piece]],
) -> Array[Array[@pd.Range[Piece]]] {
  let max_len = DEFAULT_REFINE_LINE_LENGTH
  let mut len_so_far = 0
  let mut range_accum : Array[@pd.Range[Piece]] = []
  let range_list_accum = []
  for range in sub_diff {
    match range {
      Same(tokenpairs) => {
        let mut i = 0
        while i < tokenpairs.length() {
          let (new_len, new_range, next_i, hit_newline) = take_until_max(
            len_so_far, tokenpairs, i, max_len,
          )
          range_accum.push(new_range)
          // If there are token pairs left, we hit `max_len`, so break here.
          if next_i < tokenpairs.length() && !hit_newline {
            range_accum.push(make_newline())
            range_list_accum.push(range_accum)
            range_accum = []
          }
          len_so_far = new_len
          i = next_i
        }
      }
      Next(tokens, _) | Prev(tokens, _) => {
        len_so_far = line_length_so_far(len_so_far, tokens)
        range_accum.push(range)
      }
      Replace(prev, next, _) => {
        len_so_far = @cmp.maximum(
          line_length_so_far(len_so_far, prev),
          line_length_so_far(len_so_far, next),
        )
        range_accum.push(range)
      }
      Unified(_, _) => abort("split_long_lines: unexpected Unified range")
    }
  }
  if !range_accum.is_empty() {
    range_list_accum.push(range_accum)
  }
  range_list_accum
}

///|
fn[A] refine_internal(
  mark_newline_changes~ : Bool = false,
  map_non_replace~ : (Bool, @pd.Range[Bytes]) -> Array[@pd.Range[A]],
  line_is_ws~ : (A) -> Bool,
  collapse_range~ : (
    Bool,
    Bool,
    Array[@pd.Range[Piece]],
    Array[@pd.Range[Piece]],
    @pd.MoveId?,
    Bool,
  ) -> (Array[A], Array[A]),
  produce_unified_lines~ : Bool,
  keep_ws~ : Bool,
  split_long_lines~ : Bool,
  interleave~ : Bool,
  word_big_enough~ : Int32,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[@pd.Hunk[A]] {
  let produce_unified_lines_option = produce_unified_lines
  let handle_replace = (
    prev_words : Array[Array[Bytes]],
    next_words : Array[Array[Bytes]],
    move_kind : @pd.MoveId?,
  ) => {
    let prev_pieces = explode_internal(prev_words, keep_ws~)
    let next_pieces = explode_internal(next_words, keep_ws~)
    let sub_diff = diff_pieces(
      prev_pieces~,
      next_pieces~,
      keep_ws~,
      word_big_enough~,
    )
    // Smash the hunks' ranges all together.
    let sub_diff = @pd.ranges(sub_diff)
    // Break it up where lines are too long.
    let sub_diff_pieces = if split_long_lines {
      split_long_lines_of_ranges(sub_diff)
    } else {
      [sub_diff]
    }
    let sub_diff_pieces = if interleave {
      let out = []
      for piece in sub_diff_pieces {
        out.push_iter(split_for_readability(piece).iter())
      }
      out
    } else {
      sub_diff_pieces
    }
    let out : Array[@pd.Range[A]] = []
    for piece in sub_diff_pieces {
      let sub_prev = @pd.prev_only(piece)
      let sub_next = @pd.next_only(piece)
      let all_same = (ranges : Array[@pd.Range[Piece]]) => {
        ranges
        .iter()
        .all(range => {
          match range {
            Same(_) => true
            Prev(a, _) | Next(a, _) =>
              !keep_ws && a.iter().all(token => token is Newline(_, _))
            _ => false
          }
        })
      }
      let prev_all_same = all_same(sub_prev)
      let next_all_same = all_same(sub_next)
      let produce_unified_lines = produce_unified_lines_option &&
        (
          (!ranges_are_just_whitespace(sub_prev) && next_all_same) ||
          (!ranges_are_just_whitespace(sub_next) && prev_all_same)
        )
      // Collapse the pieces back into lines.
      let (prev_ar, next_ar) = collapse_range(
        prev_all_same, next_all_same, sub_prev, sub_next, move_kind, produce_unified_lines,
      )
      let range : @pd.Range[A] = if prev_all_same &&
        next_all_same &&
        move_kind is None {
        // Don't create a same range inside of a move.
        if prev_ar.length() == next_ar.length() {
          Same([ for i, x in prev_ar => (x, next_ar[i]) ])
        } else if mark_newline_changes {
          // Changes that are purely newlines are ignored when `keep_ws` is false,
          // but side by side diffs need this info to track line numbers.
          Replace(prev_ar, next_ar, move_kind)
        } else {
          Same([ for x in next_ar => (x, x) ])
        }
      } else if prev_ar is [line] && line_is_ws(line) {
        // Ugly hack that takes care of empty files.
        Replace([], next_ar, move_kind)
      } else if next_ar is [line] && line_is_ws(line) {
        Replace(prev_ar, [], move_kind)
      } else {
        match (produce_unified_lines, prev_all_same, next_all_same) {
          (true, true, false) => Unified(next_ar, move_kind)
          (true, false, true) => Unified(prev_ar, move_kind)
          (false, _, _) | (_, false, false) =>
            Replace(prev_ar, next_ar, move_kind)
          _ => abort("refine: unexpected unified range")
        }
      }
      out.push(range)
    }
    out
  }
  let refine_range = (range : @pd.Range[Bytes]) => {
    match range {
      Next(_, _) | Prev(_, _) | Same(_) | Unified(_, _) =>
        map_non_replace(keep_ws, range)
      Replace(prev_ar, next_ar, move_kind) => {
        let out : Array[@pd.Range[A]] = []
        for arrays in words_break_heuristic(prev_ar, next_ar, keep_ws~) {
          out.push_iter(handle_replace(arrays.0, arrays.1, move_kind).iter())
        }
        out
      }
    }
  }
  let out = []
  for hunk in hunks {
    let refined = hunk.concat_map(refine_range)
    if !refined.all_same() {
      out.push(refined)
    }
  }
  out
}

///|
fn tag_same(line : Bytes) -> Array[(Tag, Bytes)] {
  [(Same, line)]
}

///|
/// The same as `refine` except returns structured data.
pub fn refine_structured(
  mark_newline_changes~ : Bool = false,
  produce_unified_lines~ : Bool,
  keep_ws~ : Bool,
  split_long_lines~ : Bool,
  interleave~ : Bool,
  word_big_enough~ : Int32,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[StructuredHunk] {
  refine_internal(
    mark_newline_changes~,
    produce_unified_lines~,
    line_is_ws=_ => false,
    keep_ws~,
    split_long_lines~,
    interleave~,
    word_big_enough~,
    hunks,
    map_non_replace=(keep_ws, range) => {
      // When `mark_newline_changes` is true, we preserve whitespace-only lines as
      // changes rather than dropping them. This is to have accurate line counts
      // for side-by-side diffs.
      let droppable = (a : Array[Bytes]) => {
        !mark_newline_changes && !keep_ws && a.iter().all(is_ws)
      }
      match range {
        Next(a, None) if droppable(a) =>
          [Same([ for line in a => (tag_same(line), tag_same(line)) ])]
        Prev(a, None) if droppable(a) => []
        Next(lines, move_info) =>
          [Next([ for line in lines => tag_same(line) ], move_info)]
        Prev(lines, move_info) =>
          [Prev([ for line in lines => tag_same(line) ], move_info)]
        Same(lines) =>
          [Same([ for pair in lines => (tag_same(pair.0), tag_same(pair.1)) ])]
        Unified(lines, move_info) =>
          [Unified([ for line in lines => tag_same(line) ], move_info)]
        Replace(_, _, _) => abort("refine_structured: unexpected Replace")
      }
    },
    collapse_range=(_, _, sub_prev, sub_next, _, _) => {
      (
        collapse_structured(sub_prev, kind=PrevOnly),
        collapse_structured(sub_next, kind=NextOnly),
      )
    },
  )
}

///|
/// Useful if you want an unrefined diff and to produce the same structure as
/// `refine_structured`.
pub fn unrefined_structured(
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[StructuredHunk] {
  let tag_array = (tag : Tag, arr : Array[Bytes]) => {
    [
      for line in arr => [(tag, line)]
    ]
  }
  @pd.concat_map_ranges(hunks, range => {
    match range {
      Same(same) =>
        [Same([ for pair in same => (tag_same(pair.0), tag_same(pair.1)) ])]
      Prev(prev, move_kind) => [Prev(tag_array(Prev, prev), move_kind)]
      Next(next, move_kind) => [Next(tag_array(Next, next), move_kind)]
      Replace(prev, next, move_id) =>
        [Replace(tag_array(Prev, prev), tag_array(Next, next), move_id)]
      Unified(lines, move_id) => [Unified(tag_array(Same, lines), move_id)]
    }
  })
}

///|
/// Refines the diff, splitting the lines into smaller arrays and diffing them,
/// then collapsing them back into their initial lines after applying a format.
///
/// Aborts if `produce_unified_lines` is set with `Ascii` output, which can't
/// display them.
pub fn refine(
  rules~ : Rules,
  produce_unified_lines~ : Bool,
  output~ : Output,
  keep_ws~ : Bool,
  split_long_lines~ : Bool,
  interleave~ : Bool,
  word_big_enough~ : Int32,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[@pd.Hunk[Bytes]] {
  let rule_prev = rules.word_prev
  let rule_next = rules.word_next
  if output is Ascii && produce_unified_lines {
    abort("produce_unified_lines is not supported in Ascii mode")
  }
  refine_internal(
    produce_unified_lines~,
    line_is_ws=line => line.is_empty(),
    keep_ws~,
    split_long_lines~,
    interleave~,
    word_big_enough~,
    hunks,
    map_non_replace=(keep_ws, range) => {
      match range {
        Next(a, _) if !keep_ws && a.iter().all(is_ws) =>
          [Same([ for line in a => (line, line) ])]
        Prev(a, _) if !keep_ws && a.iter().all(is_ws) => []
        Replace(_, _, _) => abort("refine: unexpected Replace")
        range => [range]
      }
    },
    collapse_range=(
      prev_all_same,
      next_all_same,
      sub_prev,
      sub_next,
      move_kind,
      produce_unified_lines,
    ) => {
      let collapse_with = (ranges, rule_same, kind) => {
        collapse(ranges, rule_same~, rule_prev~, rule_next~, kind~, output~)
      }
      let unified_rule = match move_kind {
        None => rules.word_same_unified
        Some(_) => rules.word_same_unified_in_move
      }
      match (prev_all_same, next_all_same) {
        (true, true) =>
          if move_kind is None {
            let next_ar = collapse_with(sub_next, unified_rule, NextOnly)
            (next_ar, next_ar)
          } else {
            (
              collapse_with(sub_prev, unified_rule, PrevOnly),
              collapse_with(sub_next, unified_rule, NextOnly),
            )
          }
        (false, true) => {
          let rule_same = if produce_unified_lines {
            unified_rule
          } else {
            rules.word_same_prev
          }
          (
            collapse_with(sub_prev, rule_same, PrevOnly),
            collapse_with(sub_next, rules.word_same_next, NextOnly),
          )
        }
        (true, false) => {
          let rule_same = if produce_unified_lines {
            unified_rule
          } else {
            rules.word_same_next
          }
          (
            collapse_with(sub_prev, rules.word_same_prev, PrevOnly),
            collapse_with(sub_next, rule_same, NextOnly),
          )
        }
        (false, false) =>
          (
            collapse_with(sub_prev, rules.word_same_prev, PrevOnly),
            collapse_with(sub_next, rules.word_same_next, NextOnly),
          )
      }
    },
  )
}

///|
/// Output a hunk list, usually from `diff` or `refine`, to a string.
pub fn output_to_string(
  print_global_header~ : Bool = false,
  file_names~ : (FileName, FileName),
  rules~ : Rules,
  output~ : Output,
  location_style~ : LocationStyle,
  platform~ : Platform = Platform::without_unix(),
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Bytes {
  let lines = []
  print_unified(
    print_global_header~,
    file_names~,
    rules~,
    output~,
    location_style~,
    platform~,
    print=line => lines.push(line),
    hunks,
  )
  @bstr.concat(lines, sep=b"\n")
}

///|
pub fn output_to_string_side_by_side(
  annotation_gutter? : AnnotationGutter,
  width_override? : Int32,
  file_names~ : (FileName, FileName),
  rules~ : Rules,
  wrap_or_truncate~ : WrapOrTruncate,
  output~ : Output,
  platform~ : Platform = Platform::without_unix(),
  hunks : ArrayView[StructuredHunk],
) -> Bytes {
  let (prev_file, next_file) = file_names
  let line_num_width = max_line_number(hunks).to_string().length() + 1
  let pane_cols = (output_width(width_override?, platform~) - 1) / 2
  let lines = render_filenames(
    annotation_gutter?,
    prev_file~,
    next_file~,
    pane_cols~,
    output~,
    rules~,
    line_num_width~,
  )
  let middle_divider = make_divider(output)
  let blocks = build_side_by_side(
    annotation_gutter?,
    width_override?,
    hunks,
    rules~,
    wrap_or_truncate~,
    output~,
    platform~,
  )
  for block in blocks {
    for pair in block {
      lines.push(pair.0 + middle_divider + pair.1)
    }
  }
  @bstr.concat(lines, sep=b"\n")
}

///|
/// Runs the equivalent of the command line version of patdiff on `prev` and
/// `next`.
pub fn patdiff(
  context~ : Int32 = DEFAULT_CONTEXT,
  keep_ws~ : Bool = false,
  find_moves~ : Bool = false,
  rules~ : Rules = Rules::default(),
  output~ : Output = Ansi,
  produce_unified_lines~ : Bool = true,
  split_long_lines~ : Bool = true,
  print_global_header~ : Bool = false,
  location_style~ : LocationStyle = Diff,
  interleave~ : Bool = true,
  float_tolerance? : Double,
  line_big_enough~ : Int32 = DEFAULT_LINE_BIG_ENOUGH,
  word_big_enough~ : Int32 = DEFAULT_WORD_BIG_ENOUGH,
  prev~ : DiffInput,
  next~ : DiffInput,
) -> Bytes {
  let keep_ws = keep_ws || should_keep_whitespace(prev~, next~)
  let hunks = diff(
    context~,
    keep_ws~,
    find_moves~,
    line_big_enough~,
    prev=@bstr.split_lines(prev.text),
    next=@bstr.split_lines(next.text),
  )
  let hunks = refine(
    rules~,
    produce_unified_lines~,
    output~,
    keep_ws~,
    split_long_lines~,
    interleave~,
    word_big_enough~,
    hunks,
  )
  let hunks = match float_tolerance {
    None => hunks
    Some(tolerance) => float_tolerance_apply(hunks, tolerance, context~)
  }
  output_to_string(
    print_global_header~,
    file_names=(Fake(prev.name), Fake(next.name)),
    rules~,
    output~,
    location_style~,
    hunks,
  )
}
