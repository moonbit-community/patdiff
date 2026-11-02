///|
/// A line with its floats taken out.
priv struct StringWithFloats {
  floats : Array[Double]
  without_floats : Bytes
}

///|
fn is_float_delim(c : Byte) -> Bool {
  match c {
    b' ' | b';' | b':' | b',' | b'\\' | b'|' | b'#' | b'&' | b'(' | b')' | b'{' | b'}' | b'[' | b']' | b'<' | b'>' | b'~' | b'=' | b'+' | b'-' | b'*' | b'/' =>
      true
    _ => false
  }
}

///|
fn is_digit(c : Byte) -> Bool {
  c >= b'0' && c <= b'9'
}

///|
/// The word characters of the `Re` library, which include Latin-1 letters.
fn is_word_char(c : Byte) -> Bool {
  (c >= b'a' && c <= b'z') ||
  (c >= b'A' && c <= b'Z') ||
  is_digit(c) ||
  c == b'_' ||
  c == 0xAA ||
  c == 0xB5 ||
  c == 0xBA ||
  (c >= 0xC0 && c != 0xD7 && c != 0xF7)
}

///|
/// `-?[0-9]+(\.[0-9]*)?([eE][+-]?[0-9]+)?` at `i`, giving the end of the match.
fn scan_float(s : Bytes, i : Int) -> Int? {
  let n = s.length()
  let digits_from = (start : Int) => {
    let mut j = start
    while j < n && is_digit(s[j]) {
      j += 1
    }
    j
  }
  let start = if i < n && s[i] == b'-' { i + 1 } else { i }
  let mut j = digits_from(start)
  if j == start {
    return None
  }
  if j < n && s[j] == b'.' {
    j = digits_from(j + 1)
  }
  if j < n && (s[j] == b'e' || s[j] == b'E') {
    let exp_start = if j + 1 < n && (s[j + 1] == b'+' || s[j + 1] == b'-') {
      j + 2
    } else {
      j + 1
    }
    let exp_end = digits_from(exp_start)
    if exp_end > exp_start {
      j = exp_end
    }
  }
  Some(j)
}

///|
/// What may follow a float, giving the end of the match: the end of the input,
/// `%`, a delimiter, or a unit (`bp`, `s`, `m`, `ms`) ending a word.
fn scan_float_suffix(s : Bytes, i : Int) -> Int? {
  let n = s.length()
  if i == n {
    return Some(i)
  }
  if s[i] == b'%' || is_float_delim(s[i]) {
    return Some(i + 1)
  }
  let at_word_end = j => j == n || !is_word_char(s[j])
  let unit = (u : Bytes) => {
    @bstr.is_substring_at(s, i, u) && at_word_end(i + u.length())
  }
  if unit(b"ms") || unit(b"bp") {
    Some(i + 2)
  } else if unit(b"s") || unit(b"m") {
    Some(i + 1)
  } else {
    None
  }
}

///|
/// The offsets of the first float in `s` that's delimited on both sides. As with
/// the leftmost-longest regexp of the OCaml version, of two matches from the
/// same place the longer wins, and of equally long matches the one with no
/// prefix wins, so that a leading `-` is a sign rather than a delimiter.
fn find_float(s : Bytes) -> (Int, Int)? {
  for i in 0..<s.length() {
    let mut best : (Int, Int)? = None
    let mut best_end = -1
    let attempt = (float_start : Int) => {
      guard scan_float(s, float_start) is Some(float_end) else { return }
      guard scan_float_suffix(s, float_end) is Some(suffix_end) else { return }
      if suffix_end > best_end {
        best = Some((float_start, float_end))
        best_end = suffix_end
      }
    }
    if i == 0 {
      attempt(0)
    }
    if s[i] == b'$' || is_float_delim(s[i]) {
      attempt(i + 1)
    }
    if best is Some(_) {
      return best
    }
  }
  None
}

///|
fn parse_float(s : Bytes) -> Double {
  let text = @bstr.to_string(s)
  // It can only fail by overflowing, given what `scan_float` accepts.
  @string.parse_double(text) catch {
    _ => if text.has_prefix("-") { @double.neg_infinity } else { @double.infinity }
  }
}

///|
fn StringWithFloats::new(line : Bytes) -> StringWithFloats {
  let floats = []
  let mut line = line
  while find_float(line) is Some((float_start, float_end)) {
    floats.push(parse_float(@bstr.sub(line, float_start, float_end)))
    line = @bstr.sub(line, 0, float_start) +
      @bstr.sub(line, float_end, line.length())
  }
  { floats, without_floats: line }
}

///|
fn close_enough(
  tolerance : Double,
  t : StringWithFloats,
  other : StringWithFloats,
) -> Bool {
  if t.without_floats != other.without_floats ||
    t.floats.length() != other.floats.length() {
    return false
  }
  for i, f in t.floats {
    let f2 = other.floats[i]
    if !((f - f2).abs() <= tolerance * @cmp.minimum(f.abs(), f2.abs())) {
      return false
    }
  }
  true
}

///|
/// `a[i][j]` is the Levenshtein distance between the first `i` elements of `xs`
/// and the first `j` elements of `ys`. This corresponds to Needleman-Wunsch where
/// matches are 0, and mismatch, insert, and delete are all 1.
fn[A] needleman_wunsch(
  xs : ArrayView[A],
  ys : ArrayView[A],
  equal : (A, A) -> Bool,
) -> Array[Array[Int]] {
  let rows = xs.length()
  let cols = ys.length()
  let a = Array::makei(rows + 1, _ => Array::make(cols + 1, 0))
  for i in 0..=rows {
    a[i][0] = i
  }
  for j in 0..=cols {
    a[0][j] = j
  }
  for i in 1..=rows {
    for j in 1..=cols {
      let replace = a[i - 1][j - 1] + (if equal(xs[i - 1], ys[j - 1]) { 0 } else { 1 })
      a[i][j] = @cmp.minimum(
        @cmp.minimum(a[i - 1][j] + 1, a[i][j - 1] + 1),
        replace,
      )
    }
  }
  a
}

///|
priv enum PartialRangeIndexes {
  Matching(Array[(Int, Int)])
  Nonmatching(Array[Int], Array[Int])
}

///|
/// The traceback step of Needleman-Wunsch: the lowest-scoring ranges that
/// transform `xs` into `ys`.
fn[A] recover_ranges(
  xs : ArrayView[A],
  ys : ArrayView[A],
  a : Array[Array[Int]],
) -> Array[@pd.Range[A]] {
  // Index of smallest element in the triple, with ties going to the element with
  // higher index.
  let smallest = (a : Int, b : Int, c : Int) => {
    if a < b {
      if a < c {
        0
      } else {
        2
      }
    } else if b < c {
      1
    } else {
      2
    }
  }
  // Built backwards: `acc` ends with the first range, and each range's index
  // arrays end with their first index.
  let acc : Array[PartialRangeIndexes] = []
  let mut i = xs.length()
  let mut j = ys.length()
  while i > 0 && j > 0 {
    let (i2, j2, matched) = match smallest(a[i - 1][j], a[i - 1][j - 1], a[i][j - 1]) {
      0 => (i - 1, j, false)
      1 => (i - 1, j - 1, a[i][j] == a[i - 1][j - 1])
      _ => (i, j - 1, false)
    }
    if matched {
      match acc.last() {
        Some(Matching(ijs)) => ijs.push((i - 1, j - 1))
        _ => acc.push(Matching([(i - 1, j - 1)]))
      }
    } else {
      let (is_, js) = match acc.last() {
        Some(Nonmatching(is_, js)) => (is_, js)
        _ => {
          let is_ = []
          let js = []
          acc.push(Nonmatching(is_, js))
          (is_, js)
        }
      }
      if i != i2 {
        is_.push(i - 1)
      }
      if j != j2 {
        js.push(j - 1)
      }
    }
    i = i2
    j = j2
  }
  if i > 0 || j > 0 {
    let (is_, js) = match acc.last() {
      Some(Nonmatching(is_, js)) => (is_, js)
      _ => {
        let is_ = []
        let js = []
        acc.push(Nonmatching(is_, js))
        (is_, js)
      }
    }
    for k = i - 1; k >= 0; k = k - 1 {
      is_.push(k)
    }
    for k = j - 1; k >= 0; k = k - 1 {
      js.push(k)
    }
  }
  [
    for item in acc.rev_iter() => {
      match item {
        Matching(ijs) => Same([ for ij in ijs.rev_iter() => (xs[ij.0], ys[ij.1]) ])
        Nonmatching(is_, []) => Prev([ for i in is_.rev_iter() => xs[i] ], None)
        Nonmatching([], js) => Next([ for j in js.rev_iter() => ys[j] ], None)
        Nonmatching(is_, js) =>
          Replace(
            [ for i in is_.rev_iter() => xs[i] ],
            [ for j in js.rev_iter() => ys[j] ],
            None,
          )
      }
    }
  ]
}

///|
fn do_tolerance(
  tolerance : Double,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Array[@pd.Hunk[Bytes]] {
  @pd.concat_map_ranges(hunks, range => match range {
    Same(_) | Prev(_, _) | Next(_, _) => [range]
    Unified(_, _) => abort("Unexpected Unified range.")
    Replace(prev, next, _) =>
      recover_ranges(
        prev,
        next,
        needleman_wunsch(
          [ for line in prev => StringWithFloats::new(line) ],
          [ for line in next => StringWithFloats::new(line) ],
          (a, b) => close_enough(tolerance, a, b),
        ),
      )
  })
}

///|
priv enum RangePosition {
  Start
  Middle
  End
}

///|
/// Merges adjacent `Same` ranges and works out where each range lies in the
/// hunk. A hunk that's nothing but `Same` gives nothing.
fn merged_with_position(
  ranges : ArrayView[@pd.Range[Bytes]],
) -> Array[(@pd.Range[Bytes], RangePosition)] {
  let out = []
  if ranges.is_empty() {
    return out
  }
  let mut current = ranges[0]
  let mut position : RangePosition = Start
  for range in ranges[1:] {
    match (current, range) {
      (Same(car), Same(cadr)) => {
        let lines = car.copy()
        lines.push_iter(cadr.iter())
        current = Same(lines)
      }
      (Unified(_, _), _) | (_, Unified(_, _)) => abort("Unexpected unified range.")
      _ => {
        out.push((current, position))
        current = range
        position = Middle
      }
    }
  }
  match (current, position) {
    (Unified(_, _), _) => abort("Unexpected unified range.")
    (Same(_), Start) => ()
    _ => out.push((current, End))
  }
  out
}

///|
/// Limits the `Same` ranges of `hunk` to `context` lines, splitting it into
/// several hunks where lines of context are dropped.
fn enforce_context_limit(
  context~ : Int,
  hunk : @pd.Hunk[Bytes],
) -> Array[@pd.Hunk[Bytes]] {
  let out = []
  let mut prev_start = hunk.prev_start
  let mut next_start = hunk.next_start
  let mut ranges : Array[@pd.Range[Bytes]] = []
  let keep = (range : @pd.Range[Bytes]) => ranges.push(range)
  let finish = () => {
    let prev_size = ranges.fold(init=0, (acc, r) => acc + r.prev_size())
    let next_size = ranges.fold(init=0, (acc, r) => acc + r.next_size())
    if !ranges.is_empty() {
      out.push(@pd.Hunk::{ prev_start, prev_size, next_start, next_size, ranges })
    }
    prev_start += prev_size
    next_start += next_size
    ranges = []
  }
  let drop = (n : Int) => {
    finish()
    prev_start += n
    next_start += n
  }
  for item in merged_with_position(hunk.ranges) {
    let (range, position) = item
    match range {
      Unified(_, _) => abort("Unexpected Unified range.")
      Prev(_, _) | Next(_, _) | Replace(_, _, _) => keep(range)
      Same(lines) => {
        let len = lines.length()
        match position {
          Start =>
            if len - context <= 0 {
              keep(range)
            } else {
              drop(len - context)
              keep(Same(lines[len - context:].to_owned()))
            }
          End =>
            if len - context <= 0 {
              keep(range)
            } else {
              keep(Same(lines[:context].to_owned()))
            }
          Middle =>
            if len - 2 * context <= 0 {
              keep(range)
            } else {
              keep(Same(lines[:context].to_owned()))
              drop(len - 2 * context)
              keep(Same(lines[len - context:].to_owned()))
            }
        }
      }
    }
  }
  if !ranges.is_empty() {
    finish()
  }
  out
}

///|
/// Treats lines as the same when they differ only in floats that changed by no
/// more than `tolerance`, a multiplier.
pub fn float_tolerance_apply(
  hunks : ArrayView[@pd.Hunk[Bytes]],
  tolerance : Double,
  context~ : Int,
) -> Array[@pd.Hunk[Bytes]] {
  let out = []
  for hunk in do_tolerance(tolerance, hunks) {
    out.push_iter(enforce_context_limit(context~, hunk).iter())
  }
  out
}
