///|
/// Hunks of plain lines. The lines may already have been rendered.
pub type Hunks = Array[@pd.Hunk[Bytes]]

///|
priv enum RowKind {
  KPrev
  KNext
  KSame
  KUnified
}

///|
/// Tracks the current line numbers of a hunk while emitting its rows.
priv struct LineCursor {
  mut prev_line : Int
  mut next_line : Int
}

///|
fn LineCursor::side(self : LineCursor, kind : RowKind) -> GutterSide {
  let side : GutterSide = match kind {
    KPrev => Prev(line=self.prev_line)
    KNext => Next(line=self.next_line)
    KSame => Same(prev=self.prev_line, next=self.next_line)
    KUnified => Unified(prev=self.prev_line, next=self.next_line)
  }
  match kind {
    KPrev => self.prev_line += 1
    KNext => self.next_line += 1
    KSame | KUnified => {
      self.prev_line += 1
      self.next_line += 1
    }
  }
  side
}

///|
/// Iterates over output rows, reporting only side and line-number metadata.
pub fn[A] iter_sides(
  f_hunk_break~ : (@pd.Hunk[A]) -> Unit,
  f_line~ : (GutterSide) -> Unit,
  hunks : ArrayView[@pd.Hunk[A]],
) -> Unit {
  for hunk in hunks {
    f_hunk_break(hunk)
    let cursor = LineCursor::{
      prev_line: hunk.prev_start,
      next_line: hunk.next_start,
    }
    let emit = (kind, n) => for _ in 0..<n {
      f_line(cursor.side(kind))
    }
    for range in hunk.ranges {
      match range {
        Same(r) => emit(KSame, r.length())
        Prev(r, _) => emit(KPrev, r.length())
        Next(r, _) => emit(KNext, r.length())
        Unified(r, _) => emit(KUnified, r.length())
        Replace(ar1, ar2, _) => {
          emit(KPrev, ar1.length())
          emit(KNext, ar2.length())
        }
      }
    }
  }
}

///|
/// Like `iter`, but `f_line` is also given the side (kind plus prev/next line
/// numbers within the hunk) of the line being emitted.
pub fn iter_with_line_info(
  f_hunk_break~ : (@pd.Hunk[Bytes]) -> Unit,
  f_line~ : (GutterSide, Bytes) -> Unit,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Unit {
  for hunk in hunks {
    f_hunk_break(hunk)
    let cursor = LineCursor::{
      prev_line: hunk.prev_start,
      next_line: hunk.next_start,
    }
    let emit = (kind, lines : ArrayView[Bytes]) => for line in lines {
      f_line(cursor.side(kind), line)
    }
    for range in hunk.ranges {
      match range {
        Same(r) =>
          for pair in r {
            f_line(cursor.side(KSame), pair.1)
          }
        Prev(r, _) => emit(KPrev, r)
        Next(r, _) => emit(KNext, r)
        Unified(r, _) => emit(KUnified, r)
        Replace(ar1, ar2, _) => {
          emit(KPrev, ar1)
          emit(KNext, ar2)
        }
      }
    }
  }
}

///|
pub fn iter(
  f_hunk_break~ : (@pd.Hunk[Bytes]) -> Unit,
  f_line~ : (Bytes) -> Unit,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Unit {
  iter_with_line_info(f_hunk_break~, f_line=(_, line) => f_line(line), hunks)
}
