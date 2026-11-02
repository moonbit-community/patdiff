///|
/// What `[%expect]` compares: the printed output with leading and trailing
/// blank lines dropped, and trailing whitespace on each line ignored.
fn html_trim_blank_lines(s : String) -> String {
  let lines : Array[String] = []
  for line in s.split("\n") {
    lines.push(@bstr.to_string(@bstr.rstrip(b(line.to_owned()))))
  }
  let is_blank = (line : String) => line.iter().all(c => c == ' ' || c == '\t' || c == '\r')
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
fn html_print(output : Bytes) -> String {
  shown(output) + "\n"
}

///|
/// The equivalent of `[%expect {| expected |}]` for everything printed so far.
fn html_expect(printed : String, expected : String) -> Unit raise {
  let actual = html_trim_blank_lines(printed)
  let expected = html_trim_blank_lines(expected)
  if actual != expected {
    fail("expected:\n\{expected}\n---- actual:\n\{actual}\n----")
  }
}

///|
test "test outputting a move to HTML" {
  let prev =
    #|
    #|Some code that is going to get moved somewhere. Make it long so
    #|things are really similar. We only match on at least 3 lines
    #|so make it 3 lines long.
    #|a
    #|b
    #|c
    #|d
    #|e
    #|f
    #|this is deleted
    #|
  let next =
    #|
    #|a
    #|b
    #|c
    #|Some code that is going to get moved somewhere. Make it long so
    #|things are really differs. We only match on at least 3 lines
    #|so make it 3 lines long.
    #|d
    #|e
    #|f
    #|Some code that is going to get moved somewhere. Make it long so
    #|things are really similar. We only match on at least 3 lines
    #|so make it 3 lines long.
    #|
  let prev = @kernel.DiffInput::of_string("old", prev)
  let next = @kernel.DiffInput::of_string("new", next)
  let out = @kernel.patdiff(
    find_moves=true,
    prev~,
    next~,
    output=Html,
    produce_unified_lines=false,
  )
  let expected =
    #|<pre style="font-family:consolas,monospace">
    #|-1,11 +1,13
    #|
    #|<span style="color:#880088"><span style="font-weight:bold"><|</span></span><span style="color:#880088">Some code that is going to get moved somewhere. Make it long so</span>
    #|<span style="color:#880088"><span style="font-weight:bold"><|</span></span><span style="color:#880088">things are really similar. We only match on at least 3 lines</span>
    #|<span style="color:#880088"><span style="font-weight:bold"><|</span></span><span style="color:#880088">so make it 3 lines long.</span>
    #|  a
    #|  b
    #|  c
    #|<span style="color:#008800"><span style="font-weight:bold">+|</span></span><span style="color:#008800">Some code that is going to get moved somewhere. Make it long so</span>
    #|<span style="color:#008800"><span style="font-weight:bold">+|</span></span><span style="color:#008800">things are really differs. We only match on at least 3 lines</span>
    #|<span style="color:#008800"><span style="font-weight:bold">+|</span></span><span style="color:#008800">so make it 3 lines long.</span>
    #|  d
    #|  e
    #|  f
    #|<span style="color:#880000"><span style="font-weight:bold">-|</span></span><span style="color:#880000">this is deleted</span>
    #|<span style="color:#008888"><span style="font-weight:bold">>|</span></span><span style="color:#008888">Some code that is going to get moved somewhere. Make it long so</span>
    #|<span style="color:#008888"><span style="font-weight:bold">>|</span></span><span style="color:#008888">things are really similar. We only match on at least 3 lines</span>
    #|<span style="color:#008888"><span style="font-weight:bold">>|</span></span><span style="color:#008888">so make it 3 lines long.</span>
    #|</pre>
  html_expect(html_print(out), expected)
}
