///|
/// Port of `ansi_text/test/test_styles.ml`.
fn test_delta(old_style : Array[Attr], added_style : Array[Attr]) -> String {
  @ansi_text.style_to_string_hum(
    @ansi_text.style_delta(old_style~, added_style~),
  )
}

///|
test "simple deltas" {
  let bold : Array[Attr] = [Bold]
  let red : Array[Attr] = [Fg(Standard(Red))]
  let green : Array[Attr] = [Fg(Standard(Green))]
  let empty : Array[Attr] = []
  let off : Array[Attr] = [Reset]
  // Note that [delta] does not remove the bold here, it only ensures that
  // [added_style] is applied.
  @test.assert_eq(test_delta(bold, empty), "")
  @test.assert_eq(test_delta(empty, bold), "(+bold)")
  @test.assert_eq(test_delta(bold, bold), "")
  @test.assert_eq(test_delta(bold, off), "(off)")
  @test.assert_eq(test_delta(off, bold), "(+bold)")
  @test.assert_eq(test_delta(bold, red), "(fg:red)")
  @test.assert_eq(test_delta(red, bold), "(+bold)")
  @test.assert_eq(test_delta(red, green), "(fg:green)")
  @test.assert_eq(test_delta(green, red), "(fg:red)")
}

///|
test "both styles have resets" {
  @test.assert_eq(
    test_delta(
      [Underline, Reset, Fg(Standard(Red)), Bg(Standard(Green)), Italic],
      [Reset, Italic, Underline],
    ),
    "(off +italic +uline)",
  )
  @test.assert_eq(
    test_delta(
      [Underline, Fg(Standard(Red)), Reset, Bg(Standard(Green)), Italic],
      [Reset, Italic, Underline],
    ),
    "(bg:default +uline)",
  )
}

///|
test "reset in the second style" {
  @test.assert_eq(
    test_delta([Bold, Underline, Fg(Standard(Red)), Bg(Standard(Green))], [
      Blink,
      Reset,
      Italic,
      Underline,
    ]),
    "(off +italic +uline)",
  )
}

///|
test "reset in the first style" {
  @test.assert_eq(
    test_delta([Bold, Underline, Reset, Italic, Fg(Standard(Red))], [
      Blink,
      Italic,
      Underline,
    ]),
    "(+blink +uline)",
  )
}

///|
test "no resets" {
  @test.assert_eq(
    test_delta([Bold, Underline, Italic, Fg(Standard(Red))], [
      Blink,
      Italic,
      Underline,
      Bg(Default),
    ]),
    "(+blink bg:default)",
  )
}
