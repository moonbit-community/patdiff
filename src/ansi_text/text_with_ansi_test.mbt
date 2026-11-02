///|
/// Port of `ansi_text/test/test_text_with_ansi.ml`.
test "Ansi_text.width = String.length on boring strings" {
  let s = "Ansi_text.width = String.length on boring strings"
  let t = @ansi_text.parse(b(s))
  @test.assert_eq(@ansi_text.width(t), s.length())
}

///|
test "ignore ANSI, including unknown codes, when computing width" {
  let t = @ansi_text.parse(
    b(
      "\u{1b}[0;31;123mfoo\u{1b}[F\u{1b}[31;42mbar\u{1b}[32;42mbaz\u{1b}[4i\u{1b}[0;32;42m",
    ),
  )
  @test.assert_eq(@ansi_text.width(t), 9)
}

///|
test "width calculations handle unicode" {
  let t = @ansi_text.parse(
    b(
      "\u{1b}[1;41m0123\u{1b}[2;32m4👋│👋5\u{1b}[4;64m6789\u{1b}[0m\u{1b}[E",
    ),
  )
  @test.assert_eq(@ansi_text.width(t), 15)
}

///|
test "a list with only ansi is empty" {
  let only_styles = @ansi_text.parse(
    b("\u{1b}[10T\u{1b}[1;41m\u{1b}[2;32m\u{1b}[4;64m\u{1b}[0m"),
  )
  let with_spaces = @ansi_text.parse(
    b("\u{1b}[1;41m \u{1b}[2;32m\u{1b}[4;64m \u{1b}[0m\u{1b}[10S"),
  )
  @test.assert_eq(@ansi_text.is_empty(only_styles), true)
  @test.assert_eq(@ansi_text.is_empty(with_spaces), false)
}

///|
test "map over styles, controls, and texts" {
  let t = @ansi_text.parse(
    b(
      "\u{1b}[0;1;mfoo\u{1b}[2;3m  bar  \u{1b}[5;6mbaz\u{1b}[38;2;1;1;1;7m\u{1b}[3B\u{1b}[T\u{1b}[B",
    ),
  )
  let t = @ansi_text.map(t, fn(e) {
    match e {
      Style(sty) =>
        Some(
          Element::Style(
            if @ansi_text.style_includes_reset(sty) {
              sty
            } else {
              [Attr::Reset, ..sty]
            },
          ),
        )
      _ => None
    }
  })
  let t = @ansi_text.map(t, fn(e) {
    match e {
      Control(ctl) =>
        Some(
          Element::Control(
            match ctl {
              CursorDown(Some(n)) => Control::CursorDown(Some(n + 1))
              _ => ctl
            },
          ),
        )
      _ => None
    }
  })
  let t = @ansi_text.map(t, fn(e) {
    match e {
      Text(txt) => Some(Element::Text(Text::of_bytes(@bstr.strip(txt.str))))
      _ => None
    }
  })
  @test.assert_eq(
    str(@ansi_text.to_bytes_hum(t)),
    "(off +bold)foo(off +faint +italic)bar(off +blink +fastblink)baz(off fg:rgb256-1-1-1 +invert)(CursorDown:4)(ScrollDown)(CursorDown)",
  )
}

///|
test "simplify_styles combines, shortens, and drops" {
  let t = @ansi_text.parse(
    b(
      "\u{1b}[0;1;m\u{1b}[2;3;mfoo\u{1b}[2;3m  bar  \u{1b}[5;6mbaz\u{1b}[38;2;1;1;1;7m",
    ),
  )
  @test.assert_eq(
    str(@ansi_text.to_bytes_hum(@ansi_text.simplify_styles(t))),
    "(off +faint +italic)foo  bar  (+fastblink)baz(fg:rgb256-1-1-1 +invert)",
  )
}

///|
test "get_style_at_end" {
  let s = "\u{1b}[2A\u{1b}[3;1;2;4;38;5;250m some \u{1b}[22;48;5;1m text \u{1b}[58;5;32m"
  @test.assert_eq(
    str(
      @ansi_text.style_to_string(
        @ansi_text.style_at_end(@ansi_text.parse(b(s))),
      ),
    ),
    "\u{1b}[3;4;38;5;250;22;41;58;5;32m",
  )
}

///|
test "get_style_at_end handles resets" {
  let s1 = "\u{1b}[1;2;3;4;38;5;250m some \u{1b}[K\u{1b}[2;48;5;1m text \u{1b}[0m"
  let s2 = "\u{1b}[1;2;3;4;38;5;250m some \u{1b}[5i\u{1b}[2;48;5;1;0m text \u{1b}[1m"
  @test.assert_eq(
    str(
      @ansi_text.style_to_string(
        @ansi_text.style_at_end(@ansi_text.parse(b(s1))),
      ),
    ),
    "\u{1b}[0m",
  )
  @test.assert_eq(
    str(
      @ansi_text.style_to_string(
        @ansi_text.style_at_end(@ansi_text.parse(b(s2))),
      ),
    ),
    "\u{1b}[0;1m",
  )
}

///|
/// Splits `str` at `pos`, returning the serialized halves.
fn split_strs(str : String, pos : Int32) -> (Bytes, Bytes) {
  let (before, after) = @ansi_text.split(@ansi_text.parse(b(str)), pos~)
  (@ansi_text.to_bytes(before), @ansi_text.to_bytes(after))
}

///|
test "split in the middle" {
  let (before, after) = split_strs(
    "\u{1b}[1;41m012345\u{1b}[2;32m6789ab\u{1b}[G\u{1b}[4;64mcdefgh\u{1b}[0m", 10,
  )
  @test.assert_eq(
    str(before),
    "\u{1b}[1;41m012345\u{1b}[2;32m6789\u{1b}[49;22;39m",
  )
  @test.assert_eq(
    str(after),
    "\u{1b}[41;2;32mab\u{1b}[G\u{1b}[4;64mcdefgh\u{1b}[0m",
  )
  @test.assert_eq(
    str(@ansi_text.visualize(before)),
    "(+bold bg:red)012345(+faint fg:green)6789(bg:default -weight fg:default)",
  )
  @test.assert_eq(
    str(@ansi_text.visualize(after)),
    "(bg:red +faint fg:green)ab(CursorToCol:1)(+uline +ideogram:4)cdefgh(off)",
  )
}

///|
test "split at a boundary" {
  let (before, after) = split_strs(
    "\u{1b}[F\u{1b}[1;41m012345\u{1b}[2;32m6789ab\u{1b}[4;64mcdefgh\u{1b}[0m", 12,
  )
  @test.assert_eq(
    str(before),
    "\u{1b}[F\u{1b}[1;41m012345\u{1b}[2;32m6789ab\u{1b}[49;22;39m",
  )
  @test.assert_eq(str(after), "\u{1b}[41;2;32;4;64mcdefgh\u{1b}[0m")
  @test.assert_eq(
    str(@ansi_text.visualize(before)),
    "(CursorPrevLine)(+bold bg:red)012345(+faint fg:green)6789ab(bg:default -weight fg:default)",
  )
  @test.assert_eq(
    str(@ansi_text.visualize(after)),
    "(bg:red +faint fg:green +uline +ideogram:4)cdefgh(off)",
  )
}

///|
test "split resets others" {
  let (before, after) = split_strs(
    "\u{1b}[1;41m some \u{1b}[2;32m more \u{1b}[1K\u{1b}[4;74m text \u{1b}[0m", 14,
  )
  @test.assert_eq(
    str(before),
    "\u{1b}[1;41m some \u{1b}[2;32m more \u{1b}[1K\u{1b}[4;74m t\u{1b}[49;22;39;24;75m",
  )
  @test.assert_eq(str(after), "\u{1b}[41;2;32;4;74mext \u{1b}[0m")
  @test.assert_eq(
    str(@ansi_text.visualize(before)),
    "(+bold bg:red) some (+faint fg:green) more (EraseLine:ToStart)(+uline +subscript) t(bg:default -weight fg:default -uline -script)",
  )
  @test.assert_eq(
    str(@ansi_text.visualize(after)),
    "(bg:red +faint fg:green +uline +subscript)ext (off)",
  )
}

///|
test "split handles unicode" {
  let str = "\u{1b}[1;41m\u{1b}[2J0123\u{1b}[2;32m4👋👋5\u{1b}[4;74m6789\u{1b}[0m"
  let (before_t, after_t) = @ansi_text.split(@ansi_text.parse(b(str)), pos=7)
  @test.assert_eq(@ansi_text.width(before_t), 7)
  @test.assert_eq(@ansi_text.width(after_t), 7)
  let before = @ansi_text.to_bytes(before_t)
  let after = @ansi_text.to_bytes(after_t)
  @test.assert_eq(
    @bstr.to_string(before),
    "\u{1b}[1;41m\u{1b}[2J0123\u{1b}[2;32m4👋\u{1b}[49;22;39m",
  )
  @test.assert_eq(
    @bstr.to_string(after),
    "\u{1b}[41;2;32m👋5\u{1b}[4;74m6789\u{1b}[0m",
  )
  @test.assert_eq(
    @bstr.to_string(@ansi_text.visualize(before)),
    "(+bold bg:red)(EraseScreen)0123(+faint fg:green)4👋(bg:default -weight fg:default)",
  )
  @test.assert_eq(
    @bstr.to_string(@ansi_text.visualize(after)),
    "(bg:red +faint fg:green)👋5(+uline +subscript)6789(off)",
  )
}
