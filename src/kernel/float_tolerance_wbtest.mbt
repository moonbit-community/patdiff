// White-box ports of the inline expect tests of upstream's `float_tolerance.ml`.
// The expectations are upstream's, verbatim, compared as parsed s-expressions.

///|
fn ft_atom(s : String) -> @sexp.Sexp {
  @sexp.Sexp::Atom(@bstr.of_string(s))
}

///|
fn ft_list(xs : Array[@sexp.Sexp]) -> @sexp.Sexp {
  @sexp.Sexp::List(xs)
}

///|
fn ft_bytes(s : Bytes) -> @sexp.Sexp {
  @sexp.Sexp::Atom(s)
}

///|
/// Floats as OCaml's sexp printer shows them: no trailing `.0`.
fn ft_float(x : Double) -> @sexp.Sexp {
  let s = x.to_string()
  ft_atom(if s.has_suffix(".0") { s[:s.length() - 2].to_owned() } else { s })
}

///|
fn ft_with_floats(t : StringWithFloats) -> @sexp.Sexp {
  ft_list([
    ft_list([ft_atom("floats"), ft_list([for f in t.floats => ft_float(f)])]),
    ft_list([ft_atom("without_floats"), ft_bytes(t.without_floats)]),
  ])
}

///|
fn ft_expect(actual : @sexp.Sexp, expected : String) -> Unit raise {
  let parsed = @sexp.Sexp::parse(@bstr.of_string(expected))
  if actual != parsed {
    fail(
      "expected:\n\{@bstr.to_string(parsed.to_bytes_hum())}\n---- actual:\n\{@bstr.to_string(actual.to_bytes_hum())}\n----",
    )
  }
}

///|
fn ft_create(s : String) -> StringWithFloats {
  StringWithFloats::new(@bstr.of_string(s))
}

///|
test "String_with_floats: trailing [.]" {
  let t = ft_create("(foo 12.)")
  let expected =
    #|(t ((floats (12)) (without_floats "(foo )")))
  ft_expect(ft_list([ft_atom("t"), ft_with_floats(t)]), expected)
}

///|
test "String_with_floats: scientific notation" {
  let ts = [
    ft_create("(foo -12345678910.11)"),
    ft_create("(foo -1.234567891011e10)"),
    ft_create("(foo -1.234567891011e+10)"),
    ft_create("(foo -1.234567891011E10)"),
    ft_create("(foo -1.234567891011E+10)"),
    ft_create("(foo -123456789101.1e-1)"),
    ft_create("(foo -1234567891011.e-2)"),
    ft_create("(foo -1234567891011e-2)"),
  ]
  let actual = ft_list(
    [
      for i, t in ts =>
        ft_list([ft_atom("t\{i + 1}"), ft_with_floats(t)])
    ],
  )
  let expected =
    #|((t1 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t2 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t3 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t4 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t5 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t6 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t7 ((floats (-12345678910.11)) (without_floats "(foo )")))
    #| (t8 ((floats (-12345678910.11)) (without_floats "(foo )"))))
  ft_expect(actual, expected)
}

///|
test "String_with_floats: price range" {
  let prev = ft_create("(dynamic (Ok ((price_range (-18.8305 39.1095)))))\n")
  let next = ft_create("(dynamic (Ok ((price_range (-18.772 38.988)))))\n")
  let expected =
    #|((prev
    #|  ((floats (-18.8305 39.1095))
    #|   (without_floats "(dynamic (Ok ((price_range ( )))))\n")))
    #| (next
    #|  ((floats (-18.772 38.988))
    #|   (without_floats "(dynamic (Ok ((price_range ( )))))\n"))))
  ft_expect(
    ft_list([
      ft_list([ft_atom("prev"), ft_with_floats(prev)]),
      ft_list([ft_atom("next"), ft_with_floats(next)]),
    ]),
    expected,
  )
}

///|
test "String_with_floats: times" {
  let prev = ft_create(
    "(primary_exchange_core_session (09:30:00.000000 16:00:00.000000))",
  )
  let next = ft_create(
    "(primary_exchange_core_session (09:30:00.000000 15:59:00.000000))",
  )
  let expected =
    #|((prev
    #|  ((floats (9 30 0 16 0 0))
    #|   (without_floats "(primary_exchange_core_session (:: ::))")))
    #| (next
    #|  ((floats (9 30 0 15 59 0))
    #|   (without_floats "(primary_exchange_core_session (:: ::))"))))
  ft_expect(
    ft_list([
      ft_list([ft_atom("prev"), ft_with_floats(prev)]),
      ft_list([ft_atom("next"), ft_with_floats(next)]),
    ]),
    expected,
  )
}

///|
fn[A] ft_range(r : @pd.Range[A], f : (A) -> @sexp.Sexp) -> @sexp.Sexp {
  let arr = (xs : Array[A]) => ft_list([for x in xs => f(x)])
  let kind = (k : @pd.MoveKind?) => match k {
    None => ft_list([])
    Some(Move(id)) => ft_list([ft_list([ft_atom("Move"), ft_atom(id.to_string())])])
    Some(WithinMove(id)) =>
      ft_list([ft_list([ft_atom("Within_move"), ft_atom(id.to_string())])])
  }
  let id_opt = (id : Int?) => match id {
    None => ft_list([])
    Some(id) => ft_list([ft_atom(id.to_string())])
  }
  match r {
    Same(pairs) =>
      ft_list([
        ft_atom("Same"),
        ft_list([for p in pairs => ft_list([f(p.0), f(p.1)])]),
      ])
    Prev(xs, k) => ft_list([ft_atom("Prev"), arr(xs), kind(k)])
    Next(xs, k) => ft_list([ft_atom("Next"), arr(xs), kind(k)])
    Replace(xs, ys, id) =>
      ft_list([ft_atom("Replace"), arr(xs), arr(ys), id_opt(id)])
    Unified(xs, id) => ft_list([ft_atom("Unified"), arr(xs), id_opt(id)])
  }
}

///|
test "recover_ranges" {
  let prev = [b"a", b"b"]
  let next = [b"z"]
  let a = needleman_wunsch(prev, next, (x, y) => x == y)
  let actual = ft_list(
    [for row in a => ft_list([for n in row => ft_atom(n.to_string())])],
  )
  ft_expect(actual, "((0 1) (1 1) (2 2))")
  let ranges = recover_ranges(prev, next, a)
  ft_expect(
    ft_list([for r in ranges => ft_range(r, ft_bytes)]),
    "((Replace (a b) (z) ()))",
  )
}

///|
fn ft_position(p : RangePosition) -> @sexp.Sexp {
  match p {
    Start => ft_atom("Start")
    Middle => ft_atom("Middle")
    End => ft_atom("End")
  }
}

///|
test "Merged_with_position" {
  let test_ = (ranges : Array[@pd.Range[Bytes]]) => ft_list(
    [
      for item in merged_with_position(ranges) =>
        ft_list([ft_range(item.0, ft_bytes), ft_position(item.1)])
    ],
  )
  let same : @pd.Range[Bytes] = Same([(b"same", b"same")])
  let not_same : @pd.Range[Bytes] = Next([b"new"], None)
  ft_expect(test_([same, same]), "()")
  let expected =
    #|(((Same ((same same))) Start) ((Next (new) ()) Middle)
    #| ((Same ((same same) (same same))) Middle) ((Next (new) ()) Middle)
    #| ((Same ((same same) (same same))) End))
  ft_expect(
    test_([same, not_same, same, same, not_same, same, same]),
    expected,
  )
}

// Upstream's `Drop_or_keep` and `Reconstruct_hunk` tests exercise helpers that
// the port folds into `enforce_context_limit`, so this checks the same inputs
// (context 1) through it. The expectation is derived by hand from upstream's
// `Drop_or_keep` output, applying `Reconstruct_hunk` (prev_start = next_start = 1):
//   Drop 1 -> skipped (empty), start moves to 2;
//   Keep Same1, Next, Same2, Next, Same1, then Drop 1 -> hunk (2, 4, 2, 6),
//   the next start moves to (7, 9); Keep Same1, Next, Same1 -> hunk (7, 2, 9, 3).

///|
test "enforce_context_limit (Drop_or_keep and Reconstruct_hunk tests)" {
  let same : @pd.Range[Bytes] = Same([(b"same", b"same")])
  let not_same : @pd.Range[Bytes] = Next([b"new"], None)
  let test_ = (ranges : Array[@pd.Range[Bytes]]) => {
    let prev_size = ranges.fold(init=0, (n, r) => n + r.prev_size())
    let next_size = ranges.fold(init=0, (n, r) => n + r.next_size())
    let hunks = enforce_context_limit(
      context=1,
      @pd.Hunk::{
        prev_start: 1,
        prev_size,
        next_start: 1,
        next_size,
        ranges,
      },
    )
    ft_list(
      [
        for h in hunks =>
          ft_list([
            ft_atom("\{h.prev_start} \{h.prev_size} \{h.next_start} \{h.next_size}"),
            ft_list([for r in h.ranges => ft_range(r, ft_bytes)]),
          ])
      ],
    )
  }
  ft_expect(test_([same, same]), "()")
  let actual = test_([
    same, same, not_same, same, same, not_same, same, same, same, not_same, same,
    same,
  ])
  let expected =
    #|(("2 4 2 6"
    #|  ((Same ((same same))) (Next (new) ())
    #|   (Same ((same same) (same same))) (Next (new) ())
    #|   (Same ((same same)))))
    #| ("7 2 9 3"
    #|  ((Same ((same same))) (Next (new) ()) (Same ((same same))))))
  ft_expect(actual, expected)
}
