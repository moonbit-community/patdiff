///|
/// Plain Myers diff, used when a region has too few unique tokens for patience
/// diff to give good results. This follows GNU diff's `diffseq.h` via camlp5's
/// `diff.ml`, including its "too expensive" heuristic, because which of several
/// equal-cost scripts it picks is visible in the output.

///|
priv struct Partition {
  xmid : Int32
  ymid : Int32
  lo_minimal : Bool
  hi_minimal : Bool
}

///|
priv struct PlainDiff {
  // Equal ids mean equal elements; only elements present in both inputs appear.
  x : FixedArray[Int32]
  y : FixedArray[Int32]
  fd : FixedArray[Int32]
  bd : FixedArray[Int32]
  sh : Int32
  too_expensive : Int32
}

///|
fn PlainDiff::diag(
  self : PlainDiff,
  xoff : Int32,
  xlim : Int32,
  yoff : Int32,
  ylim : Int32,
  find_minimal : Bool,
) -> Partition {
  let { x: xv, y: yv, fd, bd, sh, too_expensive, } = self
  let max_value = 2147483647
  let dmin = xoff - ylim
  let dmax = xlim - yoff
  let fmid = xoff - yoff
  let bmid = xlim - ylim
  let odd = ((fmid - bmid) & 1) != 0
  fd[sh + fmid] = xoff
  bd[sh + bmid] = xlim
  let mut fmin = fmid
  let mut fmax = fmid
  let mut bmin = bmid
  let mut bmax = bmid
  let mut c = 1
  while true {
    // Extend the forward search by one edit step in each diagonal.
    if fmin > dmin {
      fd[sh + fmin - 2] = -1
      fmin -= 1
    } else {
      fmin += 1
    }
    if fmax < dmax {
      fd[sh + fmax + 2] = -1
      fmax += 1
    } else {
      fmax -= 1
    }
    let mut d = fmax
    while d >= fmin {
      let tlo = fd[sh + d - 1]
      let thi = fd[sh + d + 1]
      let mut x = if tlo >= thi { tlo + 1 } else { thi }
      let mut y = x - d
      while x < xlim && y < ylim && xv[x] == yv[y] {
        x += 1
        y += 1
      }
      fd[sh + d] = x
      if odd && bmin <= d && d <= bmax && bd[sh + d] <= fd[sh + d] {
        return { xmid: x, ymid: y, lo_minimal: true, hi_minimal: true, }
      }
      d -= 2
    }
    // Similarly extend the backward search.
    if bmin > dmin {
      bd[sh + bmin - 2] = max_value
      bmin -= 1
    } else {
      bmin += 1
    }
    if bmax < dmax {
      bd[sh + bmax + 2] = max_value
      bmax += 1
    } else {
      bmax -= 1
    }
    d = bmax
    while d >= bmin {
      let tlo = bd[sh + d - 1]
      let thi = bd[sh + d + 1]
      let mut x = if tlo < thi { tlo } else { thi - 1 }
      let mut y = x - d
      while x > xoff && y > yoff && xv[x - 1] == yv[y - 1] {
        x -= 1
        y -= 1
      }
      bd[sh + d] = x
      if !odd && fmin <= d && d <= fmax && bd[sh + d] <= fd[sh + d] {
        return { xmid: x, ymid: y, lo_minimal: true, hi_minimal: true, }
      }
      d -= 2
    }
    // Heuristic: if we've gone well beyond the call of duty, give up and report
    // halfway between our best results so far.
    if !find_minimal && c >= too_expensive {
      let mut fxybest = -1
      let mut fxbest = fmax
      d = fmax
      while d >= fmin {
        let mut x = @cmp.minimum(fd[sh + d], xlim)
        let mut y = x - d
        if ylim < y {
          x = ylim + d
          y = ylim
        }
        if fxybest < x + y {
          fxybest = x + y
          fxbest = x
        }
        d -= 2
      }
      let mut bxybest = max_value
      let mut bxbest = bmax
      d = bmax
      while d >= bmin {
        let mut x = @cmp.maximum(xoff, bd[sh + d])
        let mut y = x - d
        if y < yoff {
          x = yoff + d
          y = yoff
        }
        if x + y < bxybest {
          bxybest = x + y
          bxbest = x
        }
        d -= 2
      }
      if xlim + ylim - bxybest < fxybest - (xoff + yoff) {
        return {
          xmid: fxbest,
          ymid: fxybest - fxbest,
          lo_minimal: true,
          hi_minimal: false,
        }
      } else {
        return {
          xmid: bxbest,
          ymid: bxybest - bxbest,
          lo_minimal: false,
          hi_minimal: true,
        }
      }
    }
    c += 1
  }
  abort("unreachable")
}

///|
/// Finds which elements changed. `ai` and `bi` map positions in the reduced
/// sequences `x`, `y` back to positions in the originals.
fn PlainDiff::compare_seq(
  self : PlainDiff,
  xoff : Int32,
  xlim : Int32,
  yoff : Int32,
  ylim : Int32,
  find_minimal : Bool,
  ai : FixedArray[Int32],
  bi : FixedArray[Int32],
  chng1 : FixedArray[Bool],
  chng2 : FixedArray[Bool],
) -> Unit {
  let mut xoff = xoff
  let mut yoff = yoff
  let mut xlim = xlim
  let mut ylim = ylim
  while xoff < xlim && yoff < ylim && self.x[xoff] == self.y[yoff] {
    xoff += 1
    yoff += 1
  }
  while xlim > xoff && ylim > yoff && self.x[xlim - 1] == self.y[ylim - 1] {
    xlim -= 1
    ylim -= 1
  }
  if xoff == xlim {
    for y in yoff..<ylim {
      chng2[bi[y]] = true
    }
  } else if yoff == ylim {
    for x in xoff..<xlim {
      chng1[ai[x]] = true
    }
  } else {
    let { xmid, ymid, lo_minimal, hi_minimal, } = self.diag(
      xoff, xlim, yoff, ylim, find_minimal,
    )
    self.compare_seq(xoff, xmid, yoff, ymid, lo_minimal, ai, bi, chng1, chng2)
    self.compare_seq(xmid, xlim, ymid, ylim, hi_minimal, ai, bi, chng1, chng2)
  }
}

///|
/// Calls `f` with each pair of matched positions in `a[alo:ahi]` and
/// `b[blo:bhi]`, relative to `alo` and `blo`.
fn[E : Hash + Eq] plain_diff_iter_matches(
  a : ArrayView[E],
  b : ArrayView[E],
  f : (Int32, Int32) -> Unit,
) -> Unit {
  // Intern every element so the main loop compares ints, not elements.
  let ids : @hashmap.HashMap[E, Int32] = HashMap([])
  let intern = fn(e) {
    match ids.get(e) {
      Some(id) => id
      None => {
        let id = ids.length()
        ids.set(e, id)
        id
      }
    }
  }
  let a_ids = FixedArray::from_iter(a.iter().map(intern))
  let b_ids = FixedArray::from_iter(b.iter().map(intern))
  let in_a = FixedArray::make(ids.length(), false)
  let in_b = FixedArray::make(ids.length(), false)
  for id in a_ids {
    in_a[id] = true
  }
  for id in b_ids {
    in_b[id] = true
  }
  // Skip elements which appear on only one side; they are certainly changes.
  let ai_list = []
  for i, id in a_ids {
    if in_b[id] {
      ai_list.push(i)
    }
  }
  let bi_list = []
  for j, id in b_ids {
    if in_a[id] {
      bi_list.push(j)
    }
  }
  let ai = FixedArray::from_array(ai_list)
  let bi = FixedArray::from_array(bi_list)
  let n = ai.length()
  let m = bi.length()
  let diags = n + m + 3
  let too_expensive = {
    let mut diags = diags
    let mut cost = 1
    while diags != 0 {
      diags = diags >> 2
      cost = cost << 1
    }
    @cmp.maximum(4096, cost)
  }
  let state = PlainDiff::{
    x: FixedArray::from_iter(ai_list.iter().map(i => a_ids[i])),
    y: FixedArray::from_iter(bi_list.iter().map(j => b_ids[j])),
    fd: FixedArray::make(diags, 0),
    bd: FixedArray::make(diags, 0),
    sh: m + 1,
    too_expensive,
  }
  let chng1 = FixedArray::make(a.length(), true)
  let chng2 = FixedArray::make(b.length(), true)
  for i in ai {
    chng1[i] = false
  }
  for j in bi {
    chng2[j] = false
  }
  state.compare_seq(0, n, 0, m, false, ai, bi, chng1, chng2)
  let mut i1 = 0
  let mut i2 = 0
  while i1 < chng1.length() && i2 < chng2.length() {
    match (chng1[i1], chng2[i2]) {
      (false, false) => {
        f(i1, i2)
        i1 += 1
        i2 += 1
      }
      (false, true) => i2 += 1
      (true, false) => i1 += 1
      (true, true) => {
        i1 += 1
        i2 += 1
      }
    }
  }
}
