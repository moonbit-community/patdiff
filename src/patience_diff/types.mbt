///|
/// A contiguous run of elements that is identical in `prev` and `next`.
pub(all) struct MatchingBlock {
  prev_start : Int
  next_start : Int
  length : Int
} derive(Debug, Eq)

///|
/// Identifies one detected move. Ids are small, dense and allocated in the
/// order the moves are found.
pub type MoveId = Int

///|
/// How a line in a `Prev` or `Next` range takes part in a move.
pub(all) enum MoveKind {
  /// The line belongs to the moved text itself.
  Move(MoveId)
  /// The line was added or removed inside moved text.
  WithinMove(MoveId)
} derive(Debug, Eq)

///|
/// A chunk of a diff.
pub(all) enum Range[A] {
  Same(Array[(A, A)])
  Prev(Array[A], MoveKind?)
  Next(Array[A], MoveKind?)
  Replace(Array[A], Array[A], MoveId?)
  Unified(Array[A], MoveId?)
} derive(Debug, Eq)

///|
/// Which boundary of a changed region is being scored by `align_diffs`.
pub(all) enum Side {
  Left
  Right
} derive(Debug, Eq)

///|
pub fn[A] all_same(ranges : ArrayView[Range[A]]) -> Bool {
  for range in ranges {
    if !(range is Same(_)) {
      return false
    }
  }
  true
}

///|
fn within_move(move_id : MoveId?) -> MoveKind? {
  match move_id {
    Some(id) => Some(WithinMove(id))
    None => None
  }
}

///|
/// What `self` contributes to each side.
pub fn[A] Range::prev_and_next(
  self : Range[A],
) -> (Array[Range[A]], Array[Range[A]]) {
  match self {
    Same(_) => ([self], [self])
    Prev(_, None | Some(Move(_))) => ([self], [])
    // Don't include `Prev`s that are within moves because they are showing that
    // some code was deleted from a different `Prev` to create a corresponding
    // `Next`.
    Prev(_, Some(WithinMove(_))) => ([], [])
    Next(_, _) => ([], [self])
    Replace(l_range, r_range, None) => ([Prev(l_range, None)], [Next(r_range, None)])
    // Don't include `Replace`s for the same reason as a `Prev` within a move.
    Replace(_, r_range, Some(move_id)) =>
      ([], [Next(r_range, Some(WithinMove(move_id)))])
    Unified(_, Some(_)) => ([], [self])
    Unified(_, None) => ([self], [self])
  }
}

///|
/// The ranges as seen from `prev`.
pub fn[A] prev_only(ranges : ArrayView[Range[A]]) -> Array[Range[A]] {
  let out = []
  for range in ranges {
    out.push_iter(range.prev_and_next().0.iter())
  }
  out
}

///|
/// The ranges as seen from `next`.
pub fn[A] next_only(ranges : ArrayView[Range[A]]) -> Array[Range[A]] {
  let out = []
  for range in ranges {
    out.push_iter(range.prev_and_next().1.iter())
  }
  out
}

///|
pub fn[A] Range::prev_size(self : Range[A]) -> Int {
  match self {
    Unified(lines, None)
    | Replace(lines, _, None)
    | Prev(lines, None | Some(Move(_))) => lines.length()
    Same(lines) => lines.length()
    // Don't include `Prev`s that are within moves as they are conceptually
    // `Next`s.
    Replace(_, _, Some(_)) | Prev(_, Some(WithinMove(_))) | Next(_, _) | Unified(_, Some(_)) =>
      0
  }
}

///|
pub fn[A] Range::next_size(self : Range[A]) -> Int {
  match self {
    Unified(lines, _) | Replace(_, lines, _) | Next(lines, _) => lines.length()
    Same(lines) => lines.length()
    Prev(_, _) => 0
  }
}

///|
/// A group of ranges, with one-based start lines.
pub(all) struct Hunk[A] {
  prev_start : Int
  prev_size : Int
  next_start : Int
  next_size : Int
  ranges : Array[Range[A]]
} derive(Debug, Eq)

///|
pub fn[A] Hunk::all_same(self : Hunk[A]) -> Bool {
  all_same(self.ranges)
}

///|
pub fn[A, B] Hunk::concat_map(
  self : Hunk[A],
  f : (Range[A]) -> Array[Range[B]],
) -> Hunk[B] {
  let ranges = []
  for range in self.ranges {
    ranges.push_iter(f(range).iter())
  }
  {
    prev_start: self.prev_start,
    prev_size: self.prev_size,
    next_start: self.next_start,
    next_size: self.next_size,
    ranges,
  }
}

///|
pub fn[A, B] concat_map_ranges(
  hunks : ArrayView[Hunk[A]],
  f : (Range[A]) -> Array[Range[B]],
) -> Array[Hunk[B]] {
  [ for hunk in hunks => hunk.concat_map(f) ]
}

///|
/// Split each `Replace` into a `Prev` followed by a `Next`.
pub fn[A] unified(hunks : ArrayView[Hunk[A]]) -> Array[Hunk[A]] {
  concat_map_ranges(hunks, range => match range {
    Replace(l_range, r_range, move_id) => {
      let move_kind = within_move(move_id)
      [Prev(l_range, move_kind), Next(r_range, move_kind)]
    }
    range => [range]
  })
}

///|
/// All the ranges of `hunks`, in order.
pub fn[A] ranges(hunks : ArrayView[Hunk[A]]) -> Array[Range[A]] {
  let out = []
  for hunk in hunks {
    out.push_iter(hunk.ranges.iter())
  }
  out
}
