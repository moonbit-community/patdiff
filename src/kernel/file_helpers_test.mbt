///|
/// Renders the result of `lines_of_contents` like the upstream test's sexp.
fn fh_show(contents : String) -> String {
  let (lines, trailing_newline) = @kernel.lines_of_contents(b(contents))
  let items = lines.map(line => shown(line)).join(" ")
  let tag = if trailing_newline {
    "With_trailing_newline"
  } else {
    "Missing_trailing_newline"
  }
  "((" + items + ") " + tag + ")"
}

///|
test "lines_of_contents" {
  let expected =
    #|(() With_trailing_newline)
  assert_eq(fh_show(""), expected)
  let expected =
    #|((hello) Missing_trailing_newline)
  assert_eq(fh_show("hello"), expected)
  let expected =
    #|((hello world) Missing_trailing_newline)
  assert_eq(fh_show("hello\nworld"), expected)
  let expected =
    #|((hello world) With_trailing_newline)
  assert_eq(fh_show("hello\nworld\n"), expected)
}
