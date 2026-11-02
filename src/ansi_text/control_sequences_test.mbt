///|
/// Port of `ansi_text/test/test_control_sequences.ml`. `Control.of_csi_params`
/// is private in the MoonBit port, so the same control sequences are built by
/// parsing the CSI text for the given params/terminal.
fn control_of_csi(input : String) -> Control {
  match @ansi_text.parse(b(input)) {
    [Control(c)] => c
    other => {
      abort("expected a single Control, got \{str(@ansi_text.to_bytes_hum(other))}")
    }
  }
}

///|
test "of_csi_params |> to_string round-trips" {
  // of_csi_params [] ~terminal:'A'
  @test.assert_eq(str(control_of_csi("\u{1b}[A").to_bytes()), "\u{1b}[A")
  // of_csi_params [ Some 1 ] ~terminal:'B'
  @test.assert_eq(str(control_of_csi("\u{1b}[1B").to_bytes()), "\u{1b}[1B")
  // of_csi_params [] ~terminal:'H'
  @test.assert_eq(str(control_of_csi("\u{1b}[H").to_bytes()), "\u{1b}[H")
  // of_csi_params [ None; None ] ~terminal:'H'
  // Not literally idempotent, but ;H and H are equivalent.
  @test.assert_eq(str(control_of_csi("\u{1b}[;H").to_bytes()), "\u{1b}[H")
  // of_csi_params [ None; Some 2 ] ~terminal:'H'
  @test.assert_eq(str(control_of_csi("\u{1b}[;2H").to_bytes()), "\u{1b}[;2H")
  // of_csi_params [ Some 3; Some 4 ] ~terminal:'H'
  @test.assert_eq(str(control_of_csi("\u{1b}[3;4H").to_bytes()), "\u{1b}[3;4H")
}

///|
test "visualization with to_string_hum" {
  @test.assert_eq(control_of_csi("\u{1b}[E").to_string_hum(), "(CursorNextLine)")
  @test.assert_eq(control_of_csi("\u{1b}[K").to_string_hum(), "(EraseLine:ToEnd)")
  @test.assert_eq(
    control_of_csi("\u{1b}[12C").to_string_hum(),
    "(CursorForward:12)",
  )
  @test.assert_eq(
    control_of_csi("\u{1b}[1;2H").to_string_hum(),
    "(CursorToPos:1;2)",
  )
}
