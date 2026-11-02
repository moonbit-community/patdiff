///|
fn bytes(s : String) -> Bytes {
  @bstr.of_string(s)
}

///|
fn mach(s : String) -> String raise {
  @bstr.to_string(@sexp.Sexp::parse(bytes(s)).to_bytes_mach())
}

///|
test "parse and print" {
  inspect(mach("(a  b (c d) ())"), content="(a b(c d)())")
  inspect(mach("(text \" |\")"), content="(text\" |\")")
  inspect(mach("atom"), content="atom")
}

///|
test "comments" {
  inspect(mach("; line\n(a #| block #| nested |# |# b #;(ignored) c)"), content="(a b c)")
}

///|
test "strings" {
  inspect(mach("\"a\\tb\\n\\065\\x41\""), content="\"a\\tb\\nAA\"")
  inspect(mach("\"\""), content="\"\"")
}

///|
test "errors" {
  for input in ["(a", ")", "a b", "\"open", ""] {
    let failed = try {
      let _ = @sexp.Sexp::parse(bytes(input))
      false
    } catch {
      _ => true
    }
    @test.assert_eq(failed, true, msg=input)
  }
}
