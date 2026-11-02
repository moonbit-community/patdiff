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
/// Keep only what `prev` sees: `Replace` becomes `Prev` and `Next` disappears.
pub fn[A] prev_only(ranges : ArrayView[Range[A]]) -> Array[Range[A]] {
  let out = []
  for range in ranges {
    match range {
      Replace(l_range, _, move_id) => out.push(Prev(l_range, within_move(move_id)))
      Next(_, _) => ()
      range => out.push(range)
    }
  }
  out
}

///|
/// Keep only what `next` sees: `Replace` becomes `Next` and `Prev` disappears.
pub fn[A] next_only(ranges : ArrayView[Range[A]]) -> Array[Range[A]] {
  let out = []
  for range in ranges {
    match range {
      Replace(_, r_range, move_id) => out.push(Next(r_range, within_move(move_id)))
      Prev(_, _) => ()
      range => out.push(range)
    }
  }
  out
}

///|
pub fn[A] Range::prev_size(self : Range[A]) -> Int {
  match self {
    Unified(lines, _) | Replace(lines, _, _) | Prev(lines, _) => lines.length()
    Same(lines) => lines.length()
    Next(_, _) => 0
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
