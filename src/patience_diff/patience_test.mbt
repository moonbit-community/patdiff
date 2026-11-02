///|
fn is_increasing(xs : Array[Int32]) -> Bool {
  let mut last = -1
  for x in xs {
    if x <= last {
      return false
    }
    last = x
  }
  true
}

///|
test "matches" {
  let empty : Array[Int32] = []
  debug_inspect(@patience_diff.matches(empty, empty), content="[]")
  debug_inspect(@patience_diff.matches([0], [0]), content="[(0, 0)]")
  debug_inspect(
    @patience_diff.matches([0, 1, 1, 2], [3, 1, 4, 5]),
    content="[(1, 1)]",
  )
}

///|
test "matches are strictly increasing" {
  let found = @patience_diff.matches([0, 1, 2, 3, 4, 5, 6], [
    2, 5, 6, 3, 0, 4, 1,
  ])
  assert_true(is_increasing([ for m in found => m.0 ]))
  assert_true(is_increasing([ for m in found => m.1 ]))
}

///|
test "get_matching_blocks has a trailing dummy block" {
  let blocks = @patience_diff.get_matching_blocks(
    transform=(x : String) => x,
    prev=["a", "b", "x", "c", "d"],
    next=["a", "b", "c", "d"],
  )
  debug_inspect(
    [
      for b in blocks => (b.prev_start, b.next_start, b.length)
    ],
    content="[(0, 0, 2), (3, 2, 2), (5, 4, 0)]",
  )
}

///|
test "get_hunks splits on context" {
  let prev = [ for i in 0..<40 => i ]
  let next = prev.copy()
  next[5] = 100
  next[30] = 101
  let hunks = @patience_diff.get_hunks(
    transform=(x : Int32) => x,
    context=2,
    prev~,
    next~,
  )
  debug_inspect(
    [
      for h in hunks => (h.prev_start, h.prev_size, h.next_start, h.next_size)
    ],
    content="[(4, 5, 4, 5), (29, 5, 29, 5)]",
  )
}

///|
test "negative context gives a singleton hunk" {
  let hunks = @patience_diff.get_hunks(
    transform=(x : Int32) => x,
    context=-1,
    prev=[1, 2, 3],
    next=[1, 4, 3],
  )
  debug_inspect(
    hunks[0].ranges,
    content="[Same([(1, 1)]), Replace([2], [4], None), Same([(3, 3)])]",
  )
}

///|
test "plain diff handles inputs with no unique tokens" {
  let found = @patience_diff.matches([1, 1, 2, 2, 1, 1, 2], [
    2, 2, 1, 1, 2, 1, 2,
  ])
  assert_true(is_increasing([ for m in found => m.0 ]))
  assert_true(is_increasing([ for m in found => m.1 ]))
  assert_true(found.length() >= 4)
}

///|
test "match_ratio" {
  inspect(
    @patience_diff.match_ratio([1, 2, 3, 4], [1, 2, 3, 5]),
    content="0.75",
  )
}
