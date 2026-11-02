///|
/// A port of Bram Cohen's patience diff algorithm as found in Bazaar 1.14.1, by
/// way of Jane Street's `patience_diff` library.

///|
/// A card in the patience game, with its backpointer. Following `tag` from the
/// top of the last pile yields the longest increasing subsequence in reverse.
priv struct Card {
  value : (Int32, Int32)
  tag : Card?
}

///|
/// Index of the leftmost pile whose top is strictly greater than `x`, or `None`
/// when `x` needs a new pile on the right.
fn find_pile(piles : ArrayView[Card], x : Int32) -> Int32? {
  let n = piles.length()
  if n == 0 || piles[n - 1].value.0 < x {
    return None
  }
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if piles[mid].value.0 > x {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  if lo < n {
    Some(lo)
  } else {
    None
  }
}

///|
/// Longest increasing subsequence of `pairs` by first coordinate, with `pairs`
/// sorted by second coordinate; see
/// http://en.wikipedia.org/wiki/Patience_sorting. Only the top of each pile is
/// ever consulted, so a pile is represented by its top card alone.
fn longest_increasing_subsequence(
  pairs : ArrayView[(Int32, Int32)],
) -> Array[(Int32, Int32)] {
  if pairs.is_empty() {
    return []
  }
  let piles : Array[Card] = []
  for x in pairs {
    let pile_opt = find_pile(piles, x.0)
    let tag = match pile_opt {
      None => piles.last()
      Some(0) => None
      Some(i) => Some(piles[i - 1])
    }
    let card = Card::{ value: x, tag, }
    match pile_opt {
      None => piles.push(card)
      Some(i) => piles[i] = card
    }
  }
  let reversed = []
  let mut card = piles.last()
  while card is Some(c) {
    reversed.push(c.value)
    card = c.tag
  }
  reversed.rev()
}

// Configurable parameters for `semantic_cleanup` and `unique_lcs`, all chosen
// based on empirical observation.

///|
/// Called on the edge case of semantic cleanup, when a change is exactly the
/// same length as the size of the match. If the insert on the next side is a
/// lot larger than the match it should be cleaned up, but most of the time it
/// should be left alone.
fn should_discard_if_other_side_equal(big_enough : Int32) -> Int32 {
  100 / big_enough
}

///|
/// Numerator and denominator of the cutoff for aborting patience diff in
/// `unique_lcs` and using plain diff instead. The range of this cutoff is from
/// 0 to 1, where 0 means we always switch and 1 means we never switch.
const SWITCH_TO_PLAIN_DIFF_NUMERATOR = 1

///|
const SWITCH_TO_PLAIN_DIFF_DENOMINATOR = 10

///|
priv enum LineMetadata {
  UniqueInA(index_in_a~ : Int32)
  UniqueInAB(index_in_a~ : Int32, index_in_b~ : Int32)
  NotUnique(occurrences_in_a~ : Int32)
}

///|
/// The LCS of the elements unique in both slices, or `None` when too few
/// elements are unique for that to mean anything.
fn[E : Hash + Eq] unique_lcs(
  alpha : ArrayView[E],
  alo : Int32,
  ahi : Int32,
  bravo : ArrayView[E],
  blo : Int32,
  bhi : Int32,
) -> Array[(Int32, Int32)]? {
  // Map elements of a to their index iff they're unique, and otherwise to their
  // frequency in a.
  let unique : @hashmap.HashMap[E, LineMetadata] = HashMap([])
  for pos in alo..<ahi {
    let x = alpha[pos]
    match unique.get(x) {
      None => unique.set(x, UniqueInA(index_in_a=pos))
      Some(UniqueInA(_)) => unique.set(x, NotUnique(occurrences_in_a=2))
      Some(NotUnique(occurrences_in_a=n)) =>
        unique.set(x, NotUnique(occurrences_in_a=n + 1))
      // This case doesn't occur until the second pass through `unique`.
      Some(UniqueInAB(_)) => abort("unique_lcs: impossible state")
    }
  }
  // `num_pairs` is the size of the list we use for Longest Increasing
  // Subsequence. `intersection_size` is the number of tokens in the
  // intersection of the two sequences, with multiplicity, and is an upper bound
  // on the size of the LCS.
  let mut num_pairs = 0
  let mut intersection_size = 0
  for pos in blo..<bhi {
    let x = bravo[pos]
    match unique.get(x) {
      None => ()
      Some(NotUnique(occurrences_in_a=n)) =>
        if n > 0 {
          unique.set(x, NotUnique(occurrences_in_a=n - 1))
          intersection_size += 1
        }
      Some(UniqueInA(index_in_a~)) => {
        num_pairs += 1
        intersection_size += 1
        unique.set(x, UniqueInAB(index_in_a~, index_in_b=pos))
      }
      Some(UniqueInAB(_)) => {
        num_pairs -= 1
        unique.set(x, NotUnique(occurrences_in_a=0))
      }
    }
  }
  // If we're ignoring almost all of the text when we perform the patience diff
  // algorithm, it will often give bad results.
  if num_pairs * SWITCH_TO_PLAIN_DIFF_DENOMINATOR <
    intersection_size * SWITCH_TO_PLAIN_DIFF_NUMERATOR {
    return None
  }
  let a_b = []
  for _, metadata in unique {
    if metadata is UniqueInAB(index_in_a~, index_in_b~) {
      a_b.push((index_in_a, index_in_b))
    }
  }
  a_b.sort_by((p, q) => {
    let by_b = p.1.compare(q.1)
    if by_b != 0 {
      by_b
    } else {
      p.0.compare(q.0)
    }
  })
  Some(longest_increasing_subsequence(a_b))
}

///|
/// `matches(a, b)` returns pairs `(i, j)` such that `a[i] == b[j]`, strictly
/// increasing in both coordinates.
///
/// First applies `unique_lcs` to find matches among elements unique in both `a`
/// and `b`, then recurses on each subinterval determined by those matches. The
/// uniqueness requirement is waived for blocks of matching lines at the
/// beginning or end.
pub fn[E : Hash + Eq] matches(
  alpha : ArrayView[E],
  bravo : ArrayView[E],
) -> Array[(Int32, Int32)] {
  let found = []
  fn recurse_matches(
    alo0 : Int32,
    blo0 : Int32,
    ahi : Int32,
    bhi : Int32,
  ) -> Unit {
    // Tail calls of the recursion are expressed as iterations of this loop, so
    // that deep recursion needs a pathological input, not merely a big file.
    let mut alo = alo0
    let mut blo = blo0
    while alo < ahi && blo < bhi {
      let old_length = found.length()
      if alpha[alo] == bravo[blo] {
        while alo < ahi && blo < bhi && alpha[alo] == bravo[blo] {
          found.push((alo, blo))
          alo += 1
          blo += 1
        }
      } else if alpha[ahi - 1] == bravo[bhi - 1] {
        let mut nahi = ahi - 1
        let mut nbhi = bhi - 1
        while nahi > alo && nbhi > blo && alpha[nahi - 1] == bravo[nbhi - 1] {
          nahi -= 1
          nbhi -= 1
        }
        recurse_matches(alo, blo, nahi, nbhi)
        for i in 0..<(ahi - nahi) {
          found.push((nahi + i, nbhi + i))
        }
        break
      } else {
        let plain_diff = fn(alo : Int32, blo : Int32) {
          plain_diff_iter_matches(alpha[alo:ahi], bravo[blo:bhi], (i1, i2) => {
            found.push((alo + i1, blo + i2))
          })
        }
        match unique_lcs(alpha, alo, ahi, bravo, blo, bhi) {
          None => {
            plain_diff(alo, blo)
            break
          }
          Some(lcs) => {
            let mut last_a_pos = alo - 1
            let mut last_b_pos = blo - 1
            for pair in lcs {
              let (apos, bpos) = pair
              if last_a_pos + 1 != apos || last_b_pos + 1 != bpos {
                recurse_matches(last_a_pos + 1, last_b_pos + 1, apos, bpos)
              }
              last_a_pos = apos
              last_b_pos = bpos
              found.push((apos, bpos))
            }
            // Did unique_lcs find anything at all?
            if found.length() > old_length {
              alo = last_a_pos + 1
              blo = last_b_pos + 1
            } else {
              plain_diff(alo, blo)
              break
            }
          }
        }
      }
    }
  }

  recurse_matches(0, 0, alpha.length(), bravo.length())
  found
}

///|
fn collapse_sequences(
  pairs : ArrayView[(Int32, Int32)],
) -> Array[MatchingBlock] {
  let collapsed = []
  let mut start : (Int32, Int32)? = None
  let mut length = 0
  for pair in pairs {
    let (i_a, i_b) = pair
    match start {
      Some((sa, sb)) if i_a == sa + length && i_b == sb + length => length += 1
      _ => {
        if start is Some((sa, sb)) {
          collapsed.push(MatchingBlock::{
            prev_start: sa,
            next_start: sb,
            length,
          })
        }
        start = Some((i_a, i_b))
        length = 1
      }
    }
  }
  if start is Some((sa, sb)) && length != 0 {
    collapsed.push({ prev_start: sa, next_start: sb, length, })
  }
  collapsed
}

///|
/// Given an insert/delete of size `left_change` to the left and of size
/// `right_change` to the right, should we discard this block of `block_len`?
/// Throw it away if its effective length is too small relative to its
/// surrounding inserts and deletes.
fn should_discard_match(
  big_enough : Int32,
  left_change : Int32,
  right_change : Int32,
  block_len : Int32,
) -> Bool {
  let other_side = block_len + should_discard_if_other_side_equal(big_enough)
  block_len < big_enough &&
  (
    (left_change > block_len && right_change > block_len) ||
    (left_change >= other_side && right_change == block_len) ||
    (right_change >= other_side && left_change == block_len)
  )
}

///|
fn change_between(left : MatchingBlock, right : MatchingBlock) -> Int32 {
  @cmp.maximum(
    right.prev_start - left.prev_start,
    right.next_start - left.next_start,
  ) -
  left.length
}

///|
/// See the "Semantic Chaff" section of https://neil.fraser.name/writing/diff/.
fn basic_semantic_cleanup(
  big_enough : Int32,
  blocks : ArrayView[MatchingBlock],
) -> Array[MatchingBlock] {
  if big_enough <= 1 || blocks.is_empty() {
    return blocks.to_owned()
  }
  let ans : Array[MatchingBlock] = []
  let mut pending = blocks[0]
  for current in blocks[1:] {
    while ans.last() is Some(hd) {
      if should_discard_match(
          big_enough,
          change_between(hd, pending),
          change_between(pending, current),
          pending.length,
        ) {
        pending = hd
        let _ = ans.pop()
      } else {
        break
      }
    }
    ans.push(pending)
    pending = current
  }
  ans.push(pending)
  ans
}

///|
/// Attempts to eliminate the "tunnel vision" problem described in the "Semantic
/// Chaff" section of https://neil.fraser.name/writing/diff/. We go through each
/// pair of consecutive matches and pretend to combine them into one match. If
/// that match would be deleted by `basic_semantic_cleanup`, we delete both.
fn advanced_semantic_cleanup(
  big_enough : Int32,
  blocks : ArrayView[MatchingBlock],
) -> Array[MatchingBlock] {
  if big_enough <= 1 || blocks.length() < 2 {
    return blocks.to_owned()
  }
  let ans : Array[MatchingBlock] = []
  let mut pending_a = blocks[0]
  let mut pending_b = blocks[1]
  for current in blocks[2:] {
    while ans.last() is Some(hd) {
      let combined_len = pending_b.length +
        @cmp.minimum(
          pending_b.prev_start - pending_a.prev_start,
          pending_b.next_start - pending_a.next_start,
        )
      if should_discard_match(
          big_enough,
          change_between(hd, pending_a),
          change_between(pending_b, current),
          combined_len,
        ) {
        pending_b = pending_a
        pending_a = hd
        let _ = ans.pop()
      } else {
        break
      }
    }
    ans.push(pending_a)
    pending_a = pending_b
    pending_b = current
  }
  ans.push(pending_a)
  ans.push(pending_b)
  // The loop above only deleted the second element of each pair we're supposed
  // to delete. This call is guaranteed to finish the job by deleting the
  // remaining element of those pairs.
  basic_semantic_cleanup(big_enough, ans)
}

///|
/// Eliminate small, semantically meaningless matches.
fn semantic_cleanup(
  big_enough : Int32,
  blocks : ArrayView[MatchingBlock],
) -> Array[MatchingBlock] {
  advanced_semantic_cleanup(
    big_enough,
    basic_semantic_cleanup(big_enough, blocks),
  )
}

///|
/// When we have a choice, we'd prefer one block of equality to two. For
/// example, instead of `A <insert>B A</insert> C D E F`, we prefer
/// `<insert>A B</insert> A C D E F`: A is usually something like "let", so the
/// second is more semantically accurate, and semantic cleanup may delete the
/// lone A match but will not delete the A C D E F match.
fn[E : Eq] combine_equalities(
  prev : ArrayView[E],
  next : ArrayView[E],
  blocks : ArrayView[MatchingBlock],
) -> Array[MatchingBlock] {
  if blocks.is_empty() {
    return []
  }
  let ans = []
  let mut pending = blocks[0]
  for block in blocks[1:] {
    let mut shrunk = pending
    let mut grown = block
    while shrunk.length != 0 &&
          prev[shrunk.prev_start + shrunk.length - 1] ==
          prev[grown.prev_start - 1] &&
          next[shrunk.next_start + shrunk.length - 1] ==
          next[grown.next_start - 1] {
      shrunk = { ..shrunk, length: shrunk.length - 1, }
      grown = {
        prev_start: grown.prev_start - 1,
        next_start: grown.next_start - 1,
        length: grown.length + 1,
      }
    }
    // In the original Google heuristic, we would either move all or none of
    // pending. But because it might start with an unmatched `Newline(0, None)`,
    // we are fine with moving all but one token of it.
    if shrunk.length == 0 || shrunk.length == 1 {
      if shrunk.length == 1 {
        ans.push(shrunk)
      }
      pending = grown
    } else {
      ans.push(pending)
      pending = block
    }
  }
  ans.push(pending)
  ans
}

///|
priv struct Aligner[A, E] {
  prev_elts : ArrayView[E]
  prev_scorable : ArrayView[A]
  next_elts : ArrayView[E]
  next_scorable : ArrayView[A]
  max_slide : Int32
  score : (Side, A, A) -> Int32
}

///|
fn[A, E] Aligner::score_side(
  self : Aligner[A, E],
  arr : ArrayView[A],
  left : Int32,
  right : Int32,
) -> Int32 {
  let score_pair = (kind, i) => {
    if i - 1 < 0 || i >= arr.length() {
      100
    } else {
      (self.score)(kind, arr[i - 1], arr[i])
    }
  }
  score_pair(Right, right) + score_pair(Left, left + 1)
}

///|
/// `*_left` and `*_right` are exclusive indexes on either side of the region.
fn[A, E] Aligner::score_boundary(
  self : Aligner[A, E],
  prev_left : Int32,
  prev_right : Int32,
  next_left : Int32,
  next_right : Int32,
) -> Int32 {
  match (prev_left + 1 == prev_right, next_left + 1 == next_right) {
    // This shouldn't happen; it means the two blocks of equal elements touch
    // and should have been merged.
    (true, true) => 0
    // inserting
    (true, false) => self.score_side(self.next_scorable, next_left, next_right)
    // deleting
    (false, true) => self.score_side(self.prev_scorable, prev_left, prev_right)
    // editing. This also shouldn't happen as if e.g. sliding right is viable
    // you could just have had a bigger matching block on the right instead.
    (false, false) =>
      @cmp.minimum(
        self.score_side(self.prev_scorable, prev_left, prev_right),
        self.score_side(self.next_scorable, next_left, next_right),
      )
  }
}

///|
/// How far to slide the change between two blocks: negative is left, 0 keeps it
/// where it is.
fn[A, E : Eq] Aligner::best_slide(
  self : Aligner[A, E],
  left : MatchingBlock,
  right : MatchingBlock,
) -> Int32 {
  let mut best_score = self.score_boundary(
    left.prev_start + left.length - 1,
    right.prev_start,
    left.next_start + left.length - 1,
    right.next_start,
  )
  let mut best_offset = 0
  // Try to shorten `left` and lengthen and move left `right`. Requires the last
  // element of `left` to be equal to the element before `right`.
  let mut i = 1
  while left.length - i >= 0 && i <= self.max_slide {
    let offset_into_left = left.length - i
    let prev_left = left.prev_start + offset_into_left - 1
    let prev_right = right.prev_start - i
    let next_left = left.next_start + offset_into_left - 1
    let next_right = right.next_start - i
    if self.next_elts[next_left + 1] != self.next_elts[next_right] ||
      self.prev_elts[prev_left + 1] != self.prev_elts[prev_right] {
      break
    }
    let score = self.score_boundary(
      prev_left, prev_right, next_left, next_right,
    )
    if score > best_score {
      best_score = score
      best_offset = -i
    }
    i += 1
  }
  // Try to lengthen `left` and shorten and move right `right`. Requires the
  // element after `left` to be equal to the first element of `right`.
  i = 1
  while i <= right.length && i <= self.max_slide {
    let offset_into_left = left.length + i - 1
    let prev_left = left.prev_start + offset_into_left
    let prev_right = right.prev_start + i
    let next_left = left.next_start + offset_into_left
    let next_right = right.next_start + i
    if self.next_elts[next_left] != self.next_elts[next_right - 1] ||
      self.prev_elts[prev_left] != self.prev_elts[prev_right - 1] {
      break
    }
    let score = self.score_boundary(
      prev_left, prev_right, next_left, next_right,
    )
    if score > best_score {
      best_score = score
      best_offset = i
    }
    i += 1
  }
  best_offset
}

///|
/// Transforms e.g. `foo f<insert>rob f</insert>lip` into
/// `foo <insert>frob </insert>flip` by scoring each boundary.
fn[A, E : Eq] Aligner::align(
  self : Aligner[A, E],
  blocks : ArrayView[MatchingBlock],
) -> Array[MatchingBlock] {
  if self.max_slide == 0 || blocks.is_empty() {
    return blocks.to_owned()
  }
  let acc = []
  let mut left = blocks[0]
  for right in blocks[1:] {
    // It is possible to end up with a length 0 block due to sliding the
    // previous block to include it. If this happens we drop it (so long as it
    // isn't the last block; we want a length 0 block at the end).
    if left.length == 0 {
      left = right
      continue
    }
    match self.best_slide(left, right) {
      0 => {
        acc.push(left)
        left = right
      }
      slide => {
        let new_left = { ..left, length: left.length + slide, }
        if new_left.length > 0 {
          acc.push(new_left)
        }
        left = {
          prev_start: right.prev_start + slide,
          next_start: right.next_start + slide,
          length: right.length - slide,
        }
      }
    }
  }
  acc.push(left)
  acc
}

///|
/// Matching blocks between `prev` and `next` after comparing them through
/// `transform`, with a dummy zero-length block at the end.
///
/// `big_enough` governs how aggressively spurious matches are cleaned up; the
/// default of 1 means no cleanup at all. `max_slide` controls how far a diff
/// may be shifted when it is immediately preceded or followed by the same lines
/// it ends or starts with; positions are compared by summing `score` at the two
/// boundaries.
pub fn[A, E : Hash + Eq] get_matching_blocks(
  transform~ : (A) -> E,
  big_enough~ : Int32 = 1,
  max_slide~ : Int32 = 0,
  score~ : (Side, A, A) -> Int32 = (_, _, _) => 100,
  prev~ : ArrayView[A],
  next~ : ArrayView[A],
) -> Array[MatchingBlock] {
  let prev_elts = [ for x in prev => transform(x) ]
  let next_elts = [ for x in next => transform(x) ]
  let found = collapse_sequences(matches(prev_elts, next_elts))
  let blocks = combine_equalities(prev_elts, next_elts, found)
  blocks.push({
    prev_start: prev_elts.length(),
    next_start: next_elts.length(),
    length: 0,
  })
  // We want to score untransformed elements (e.g. still with whitespace).
  Aligner::{
    prev_elts,
    prev_scorable: prev,
    next_elts,
    next_scorable: next,
    max_slide,
    score,
  }.align(semantic_cleanup(big_enough, blocks))
}

///|
fn[A] slice(ar : ArrayView[A], i : Int32, j : Int32) -> Array[A] {
  if j <= i {
    []
  } else {
    ar[i:j].to_owned()
  }
}

///|
fn[A, E : Hash + Eq] get_ranges(
  transform~ : (A) -> E,
  big_enough~ : Int32,
  max_slide~ : Int32,
  score~ : (Side, A, A) -> Int32,
  prev~ : ArrayView[A],
  next~ : ArrayView[A],
) -> Array[Range[A]] {
  let blocks = get_matching_blocks(
    transform~,
    big_enough~,
    max_slide~,
    score~,
    prev~,
    next~,
  )
  let ranges = []
  let mut i = 0
  let mut j = 0
  for block in blocks {
    let { prev_start: prev_index, next_start: next_index, length: size, } = block
    // Throw away crossover matches.
    if prev_index < i || next_index < j {
      continue
    }
    if i < prev_index && j < next_index {
      ranges.push(
        Replace(slice(prev, i, prev_index), slice(next, j, next_index), None),
      )
    } else if i < prev_index {
      ranges.push(Prev(slice(prev, i, prev_index), None))
    } else if j < next_index {
      ranges.push(Next(slice(next, j, next_index), None))
    }
    let prev_stop = prev_index + size
    let next_stop = next_index + size
    if size != 0 {
      ranges.push(
        Same(
          [
            for k in 0..<size => (prev[prev_index + k], next[next_index + k])
          ],
        ),
      )
    }
    i = prev_stop
    j = next_stop
  }
  ranges
}

///|
/// Turns indexes into line numbers, returning a new hunk.
fn[A] create_hunk(
  prev_start : Int32,
  prev_stop : Int32,
  next_start : Int32,
  next_stop : Int32,
  ranges : Array[Range[A]],
) -> Hunk[A] {
  {
    prev_start: prev_start + 1,
    prev_size: prev_stop - prev_start,
    next_start: next_start + 1,
    next_size: next_stop - next_start,
    ranges,
  }
}

///|
/// Compares `prev` and `next` and produces a list of hunks, whose `Same` ranges
/// hold at most `context` elements. Negative `context` is equivalent to
/// infinity, producing a singleton hunk list.
///
/// See `get_matching_blocks` for `big_enough`, `max_slide` and `score`.
pub fn[A, E : Hash + Eq] get_hunks(
  transform~ : (A) -> E,
  context~ : Int32,
  big_enough~ : Int32 = 1,
  max_slide~ : Int32 = 0,
  score~ : (Side, A, A) -> Int32 = (_, _, _) => 100,
  prev~ : ArrayView[A],
  next~ : ArrayView[A],
) -> Array[Hunk[A]] {
  let ranges = get_ranges(
    transform~,
    big_enough~,
    max_slide~,
    score~,
    prev~,
    next~,
  )
  if context < 0 {
    return [create_hunk(0, prev.length(), 0, next.length(), ranges)]
  }
  let hunks = []
  let mut alo = 0
  let mut ahi = 0
  let mut blo = 0
  let mut bhi = 0
  // If the first range is a Same, shave off the front of it, according to
  // context. Keep it in the ranges so hunk construction can see where the range
  // begins.
  if ranges.get(0) is Some(Same(range)) {
    let stop = range.length()
    let start = @cmp.maximum(0, stop - context)
    ranges[0] = Same(slice(range, start, stop))
    alo = start
    ahi = start
    blo = start
    bhi = start
  }
  let mut curr_ranges = []
  let mut i = 0
  while i < ranges.length() {
    match ranges[i] {
      Same(range) if i == ranges.length() - 1 => {
        // If the last range is a Same, we might need to crop to context.
        let stop = @cmp.minimum(range.length(), context)
        curr_ranges.push(Same(slice(range, 0, stop)))
        ahi += stop
        bhi += stop
        i += 1
        hunks.push(create_hunk(alo, ahi, blo, bhi, curr_ranges))
        return hunks
      }
      Same(range) => {
        let size = range.length()
        if size > context * 2 {
          // If this Same range is sufficiently large, split off a new hunk.
          curr_ranges.push(Same(slice(range, 0, context)))
          ahi += context
          bhi += context
          hunks.push(create_hunk(alo, ahi, blo, bhi, curr_ranges))
          curr_ranges = []
          alo = ahi + size - 2 * context
          ahi = alo
          blo = bhi + size - 2 * context
          bhi = blo
          // Push the remainder of the Same range back onto the ranges.
          ranges[i] = Same(slice(range, size - context, size))
        } else {
          // Otherwise this range is small enough that it qualifies as context
          // for both the previous and forthcoming range.
          curr_ranges.push(Same(range))
          ahi += size
          bhi += size
          i += 1
        }
      }
      range => {
        // Any range that isn't a Same is important and not just context.
        curr_ranges.push(range)
        ahi += range.prev_size()
        bhi += range.next_size()
        i += 1
      }
    }
  }
  hunks.push(create_hunk(alo, ahi, blo, bhi, curr_ranges))
  hunks
}

///|
/// `2 * len(matches(a, b)) / (len(a) + len(b))`: closer to 1.0 means `a` and `b`
/// are very much alike.
pub fn[E : Hash + Eq] match_ratio(a : ArrayView[E], b : ArrayView[E]) -> Double {
  (matches(a, b).length() * 2).to_double() /
  (a.length() + b.length()).to_double()
}
