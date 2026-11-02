///|
/// What `[%expect]` compares: the printed output with leading and trailing
/// blank lines dropped, and trailing whitespace on each line ignored.
fn sll_trim_blank_lines(s : String) -> String {
  let lines : Array[String] = []
  for line in s.split("\n") {
    lines.push(@bstr.to_string(@bstr.rstrip(b(line.to_owned()))))
  }
  let is_blank = (line : String) => {
    line.iter().all(c => c == ' ' || c == '\t' || c == '\r')
  }
  let mut lo = 0
  let mut hi = lines.length()
  while lo < hi && is_blank(lines[lo]) {
    lo += 1
  }
  while hi > lo && is_blank(lines[hi - 1]) {
    hi -= 1
  }
  let kept : Array[String] = []
  for i in lo..<hi {
    kept.push(lines[i])
  }
  kept.join("\n")
}

///|
/// What `print_endline` shows for `output`, with ESC displayed as `␛`.
fn sll_print(output : Bytes) -> String {
  shown(output) + "\n"
}

///|
/// The equivalent of `[%expect {| expected |}]` for everything printed so far.
fn sll_expect(printed : String, expected : String) -> Unit raise {
  let actual = sll_trim_blank_lines(printed)
  let expected = sll_trim_blank_lines(expected)
  if actual != expected {
    fail("expected:\n\{expected}\n---- actual:\n\{actual}\n----")
  }
}

///|
fn sll_print_patdiff(prev : String, next : String) -> String {
  sll_print(
    @kernel.patdiff(
      produce_unified_lines=false,
      output=Ascii,
      prev=@kernel.DiffInput::of_string("old", prev),
      next=@kernel.DiffInput::of_string("new", next),
    ),
  )
}

///|
test "refine does not raise with ~split_long_lines:true and no controlling tty" {
  let keep_ws = false
  let hunks = @kernel.diff(
    context=@kernel.DEFAULT_CONTEXT,
    line_big_enough=@kernel.DEFAULT_LINE_BIG_ENOUGH,
    keep_ws~,
    find_moves=false,
    prev=[b("hello"), b("world")],
    next=[b("good bye"), b("world")],
  )
  let hunks = @kernel.refine(
    rules=@kernel.Rules::default(),
    output=Ascii,
    split_long_lines=true,
    produce_unified_lines=false,
    keep_ws~,
    interleave=true,
    word_big_enough=@kernel.DEFAULT_WORD_BIG_ENOUGH,
    hunks,
  )
  let expected =
    #|((
    #|  (prev_start 1)
    #|  (prev_size  2)
    #|  (next_start 1)
    #|  (next_size  2)
    #|  (ranges (
    #|    (Replace
    #|      (hello)
    #|      ("good bye")
    #|      ())
    #|    (Same ((world world)))))))
  sx_expect(sx_hunks(hunks, sx_bytes), expected)
}

///|
test "extra empty lines are not added" {
  let expected =
    #|-1,1 +1,1
    #|-|hello world
    #|+|hello
  sll_expect(sll_print_patdiff("hello world", "hello"), expected)
  let expected =
    #|-1,1 +1,1
    #|-|hello world
    #|+|world
  sll_expect(sll_print_patdiff("hello world", "world"), expected)
  let expected =
    #|-1,1 +1,0
    #|-|hello world
  sll_expect(sll_print_patdiff("hello world", ""), expected)
}

///|
test "extra empty lines are not added for consecutive long lines" {
  let prev =
    #|
    #|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0000000000000000000000000000000000000000
    #|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1111111111111111111111111111111111111111
    #|
  let prev = @bstr.to_string(@bstr.strip(b(prev)))
  let next =
    #|
    #|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    #|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    #|
  let next = @bstr.to_string(@bstr.strip(b(next)))
  let expected =
    #|-1,2 +1,2
    #|-|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0000000000000000000000000000000000000000
    #|-|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1111111111111111111111111111111111111111
    #|+|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    #|+|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  sll_expect(sll_print_patdiff(prev, next), expected)
}
