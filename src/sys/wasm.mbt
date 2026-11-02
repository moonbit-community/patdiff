///|
/// The Wasm host doesn't tell us the size of the terminal.
fn terminal_width() -> Int32 {
  -1
}

///|
#unsafe_skip_stub_check
fn process_exit(code : Int32) = "moonbitlang/async" "runtime/exit"
