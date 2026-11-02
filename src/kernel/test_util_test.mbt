///|
/// Bytes of UTF-8 text.
fn b(s : String) -> Bytes {
  @bstr.of_string(s)
}

///|
/// Shows output in the `Debug`-free form the upstream expect tests print: text,
/// with raw ESC bytes displayed as `␛` so that expectations stay readable.
fn shown(output : Bytes) -> String {
  @bstr.to_string(output).replace_all(old="\u{1b}", new="␛")
}
