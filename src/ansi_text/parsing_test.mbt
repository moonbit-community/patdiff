///|
/// Port of `ansi_text/test/test_parsing.ml`.
fn vis(s : String) -> String {
  str(visualize(b(s)))
}

///|
fn mini(s : String) -> String {
  str(minimize(b(s)))
}

///|
fn stripped(s : String) -> String {
  str(strip(b(s)))
}

///|
/// `parse s |> to_string |> String.escaped`
fn round_trip(s : String) -> String {
  escaped(to_bytes(parse(b(s))))
}

///|
test "simple visualize" {
  let out = Out::new()
  out.println(vis("\u{1b}[31mfoo\u{1b}[0m"))
  out.check(
    [
      "(fg:red)foo(off)",
    ]
  )
}

///|
test "ESC[m is equivalent to ESC[0m (reset)" {
  let out = Out::new()
  out.println(vis("\u{1b}[mfoo\u{1b}[0m"))
  out.check(
    [
      "(off)foo(off)",
    ]
  )
}

///|
test "visualize includes unknown codes" {
  let out = Out::new()
  out.println(vis("\u{1b}[6nfoo\u{1b}[110m"))
  out.check(
    [
      "(DSR:cursor-position)foo(ANSI-SGR:110)",
    ]
  )
}

///|
test "simple minimize" {
  let out = Out::new()
  out.println(mini("\u{1b}[0;31mfoo"))
  out.check(
    [
      "\u{1b}[0;31mfoo",
    ]
  )
}

///|
test "minimize resets" {
  let s = "a \u{1b}[0m line of text \u{1b}[0;0;0m\u{1b}[0m"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(vis(mini(s)))
  out.check(
    [
      "a (off) line of text (off off off)(off)",
      "a \u{1b}[0m line of text",
      "a (off) line of text",
    ]
  )
}

///|
test "minimize with newlines" {
  let s = "a \u{1b}[0m line of text\n\u{1b}[0m\n\u{1b}[1;2mline after skip\n\u{1b}[0;0m\u{1b}[0m!\n"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(vis(mini(s)))
  out.check(
    [
      "a (off) line of text",
      "(off)",
      "(+bold +faint)line after skip",
      "(off off)(off)!",
      "",
      "a \u{1b}[0m line of text",
      "",
      "\u{1b}[2mline after skip",
      "\u{1b}[0m!",
      "",
      "a (off) line of text",
      "",
      "(+faint)line after skip",
      "(off)!",
    ]
  )
}

///|
test "strip out ANSI codes that are later overridden by a reset" {
  let s = "\u{1b}[0m\u{1b}[31m\u{1b}[0m\u{1b}[32m\u{1b}[42mf\u{1b}[44moo\u{1b}[0m"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(vis(mini(s)))
  out.check(
    [
      "(off)(fg:red)(off)(fg:green)(bg:green)f(bg:blue)oo(off)",
      "\u{1b}[0;32;42mf\u{1b}[44moo\u{1b}[0m",
      "(off fg:green bg:green)f(bg:blue)oo(off)",
    ]
  )
}

///|
test "combine and simplify adjacent ANSI codes" {
  let out = Out::new()
  out.println(mini("\u{1b}[0;44m\u{1b}[0;31m\u{1b}[1;32;44mfoo"))
  out.check(
    [
      "\u{1b}[0;1;32;44mfoo",
    ]
  )
}

///|
test "ignore a repeated style even with a reset" {
  let s = "  \u{1b}[0;41;30mabc\u{1b}[0;2mdef\u{1b}[A\u{1b}[A\u{1b}[0;1;2mghi\u{1b}[0m"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(vis(mini(s)))
  out.check(
    [
      "(off bg:red fg:black)abc(off +faint)def(CursorUp)(CursorUp)(off +bold +faint)ghi(off)",
      "\u{1b}[0;41;30mabc\u{1b}[0;2mdef\u{1b}[A\u{1b}[Aghi\u{1b}[0m",
      "(off bg:red fg:black)abc(off +faint)def(CursorUp)(CursorUp)ghi(off)",
    ]
  )
}

///|
test "strip out styles that are redundant with earlier codes" {
  let out = Out::new()
  out.println(
    mini("\u{1b}[0;31mfoo\u{1b}[31;42mbar\u{1b}[32;42mbaz\u{1b}[0;32;42m"),
  )
  out.check(
    [
      "\u{1b}[0;31mfoo\u{1b}[42mbar\u{1b}[32mbaz",
    ]
  )
}

///|
test "strip all ANSI codes" {
  let out = Out::new()
  out.println(
    stripped(
      "\u{1b}[0m\u{1b}[31m\u{1b}[0m\u{1b}[5D\u{1b}[32m\u{1b}[42mf\u{1b}[44mo\u{1b}[Bo\u{1b}[0m",
    ),
  )
  out.check(
    [
      "foo",
    ]
  )
}

///|
test "strip known & unknown CSI codes" {
  let s = "\u{1b}[0;31;123mfoo\u{1b}[31;42mbar\u{1b}[32;42Qbaz\u{1b}[0;32;42m\u{1b}[0;32~;42m"
  let out = Out::new()
  out.println(stripped(s))
  out.check(
    [
      "foobarbaz;42m",
    ]
  )
}

///|
test "preserve malformed CSI sequences as text" {
  let s = "before\u{1b}[123\u{1b}[31mafter"
  let out = Out::new()
  out.println(vis(s))
  out.println(stripped(s))
  out.check(
    [
      "before(ANSI-Fe:[)123(fg:red)after",
      "before123after",
    ]
  )
}

///|
test "compress unknown codes" {
  let out = Out::new()
  out.println(mini("\u{1b}[11;12mfoo\u{1b}[10;51;52mbar\u{1b}[54;52m"))
  out.check(
    [
      "\u{1b}[12mfoo\u{1b}[10;52mbar",
    ]
  )
}

///|
test "all the attributes" {
  let s = "\u{1b}[1;2;3;4;5;7;8;9;21;53;31;41;53mfoo\u{1b}[22;23;24;25;27;28;29;55;39;49;59mbar\u{1b}[0m"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.check(
    [
      "(+bold +faint +italic +uline +blink +invert +hide +strike +2uline +overline fg:red bg:red +overline)foo(-weight -italic -uline -blink -invert -hide -strike -overline fg:default bg:default ul:default)bar(off)",
      "\u{1b}[2;3;5;7;8;9;21;31;41;53mfoo\u{1b}[22;23;24;25;27;28;29;55;39;49;59mbar\u{1b}[0m",
    ]
  )
}

///|
test "apply turns on and off but doesn't simplify" {
  let str_ = "some \u{1b}[2;48;5;1m\u{1b}[1K text"
  let style = @ansi_text.style_of_sgr_params([
    Some(1),
    Some(2),
    Some(3),
    Some(4),
    Some(38),
    Some(5),
    Some(250),
  ])
  let styled = @ansi_text.apply(style, b(str_))
  let out = Out::new()
  out.println(str(styled))
  out.println(str(minimize(styled)))
  out.check(
    [
      "\u{1b}[1;2;3;4;38;5;250msome \u{1b}[2;48;5;1m\u{1b}[1K text\u{1b}[22;23;24;39m",
      "\u{1b}[2;3;4;38;5;250msome \u{1b}[41m\u{1b}[1K text\u{1b}[22;23;24;39m",
    ]
  )
}

///|
test "handle a patdiff header" {
  let s = "\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;45;37m--\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[0m \u{1b}[31m/home/username/sbs/da_ob\u{1b}[39m \u{1b}[1m&\u{1b}[22m \u{1b}[32m/home/us\u{1b}[0m│\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;46;37m++\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31m/home/username/sbs/da_nb\u{1b}[39m \u{1b}[1m&\u{1b}[22m \u{1b}[32m/home/us\u{1b}[0m"
  let m = minimize(b(s))
  let out = Out::new()
  out.println(str(strip(b(s))))
  out.println(str(strip(m)))
  out.println(str(visualize(b(s))))
  out.println(str(visualize(m)))
  out.println(s)
  out.println(str(m))
  out.check(
    [
      "@@@@@@@@ -- diff of /home/username/sbs/da_ob & /home/us│@@@@@@@@ ++ diff of /home/username/sbs/da_nb & /home/us",
      "@@@@@@@@ -- diff of /home/username/sbs/da_ob & /home/us│@@@@@@@@ ++ diff of /home/username/sbs/da_nb & /home/us",
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:magenta fg:white)--(-weight bg:default fg:default) (+bold)diff of(off) (fg:red)/home/username/sbs/da_ob(fg:default) (+bold)&(-weight) (fg:green)/home/us(off)│(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:cyan fg:white)++(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)/home/username/sbs/da_nb(fg:default) (+bold)&(-weight) (fg:green)/home/us(off)",
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:magenta fg:white)--(-weight bg:default fg:default) (+bold)diff of(off) (fg:red)/home/username/sbs/da_ob(fg:default) (+bold)&(-weight) (fg:green)/home/us(off)│(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:cyan fg:white)++(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)/home/username/sbs/da_nb(fg:default) (+bold)&(-weight) (fg:green)/home/us(off)",
      "\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;45;37m--\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[0m \u{1b}[31m/home/username/sbs/da_ob\u{1b}[39m \u{1b}[1m&\u{1b}[22m \u{1b}[32m/home/us\u{1b}[0m│\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;46;37m++\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31m/home/username/sbs/da_nb\u{1b}[39m \u{1b}[1m&\u{1b}[22m \u{1b}[32m/home/us\u{1b}[0m",
      "\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;45;37m--\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[0m \u{1b}[31m/home/username/sbs/da_ob\u{1b}[39m \u{1b}[1m&\u{1b}[22m \u{1b}[32m/home/us\u{1b}[0m│\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;46;37m++\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31m/home/username/sbs/da_nb\u{1b}[39m \u{1b}[1m&\u{1b}[22m \u{1b}[32m/home/us\u{1b}[0m",
    ]
  )
}

///|
test "center a patdiff header" {
  let header = parse(
    b(
      " \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31mold base\u{1b}[39m and \u{1b}[32mold tip\u{1b}[39m ",
    ),
  )
  let style : Array[Attr] = [Bold, Fg(Bright(Blue))]
  let centered = @ansi_text.center(header, char=b'@', style~, width=80)
  let out = Out::new()
  out.println(str(to_bytes(centered)))
  out.println(str(to_bytes_hum(centered)))
  out.check(
    [
      "\u{1b}[1;94m@@@@@@@@@@@@@@@@@@@@@@@@@\u{1b}[22;39m \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31mold base\u{1b}[39m and \u{1b}[32mold tip\u{1b}[39m \u{1b}[1;94m@@@@@@@@@@@@@@@@@@@@@@@@@\u{1b}[22;39m",
      "(+bold fg:bright-blue)@@@@@@@@@@@@@@@@@@@@@@@@@(-weight fg:default) (+bold)diff of(-weight) (fg:red)old base(fg:default) and (fg:green)old tip(fg:default) (+bold fg:bright-blue)@@@@@@@@@@@@@@@@@@@@@@@@@(-weight fg:default)",
    ]
  )
}

///|
test "a line that was wonky in a patdiff test" {
  let s = "    \u{1b}[0;41;30m-|\u{1b}[0;2m    let per_date_by_date,\u{1b}[0;2m error_by_date =\u{1b}[0m"
  let out = Out::new()
  out.println(vis(mini(s)))
  out.check(
    [
      "(off bg:red fg:black)-|(off +faint)    let per_date_by_date, error_by_date =(off)",
    ]
  )
}

///|
test "another line that was wonky in a patdiff test" {
  let s = "    │2 \u{1b}[0;41;30m-|\u{1b}[0m\u{1b}[0;31m\u{1b}[0m\u{1b}[0;31m_\u{1b}[0m    "
  let out = Out::new()
  out.println(mini(s))
  out.println(vis(mini(s)))
  out.check(
    [
      "│2 \u{1b}[0;41;30m-|\u{1b}[0;31m_\u{1b}[0m",
      "│2 (off bg:red fg:black)-|(off fg:red)_(off)",
    ]
  )
}

///|
test "split handles unicode" {
  let s = "\u{1b}[1;41m0123\u{1b}[2;32m4👋👋5\u{1b}[4;64m6789\u{1b}[0m"
  let (before, after) = @ansi_text.split(parse(b(s)), pos=7)
  let before = to_bytes(before)
  let after = to_bytes(after)
  let out = Out::new()
  out.println(str(before))
  out.println(str(after))
  out.println(str(visualize(before)))
  out.println(str(visualize(after)))
  out.println(str(strip(before)))
  out.println(str(strip(after)))
  out.check(
    [
      "\u{1b}[1;41m0123\u{1b}[2;32m4👋\u{1b}[49;22;39m",
      "\u{1b}[41;2;32m👋5\u{1b}[4;64m6789\u{1b}[0m",
      "(+bold bg:red)0123(+faint fg:green)4👋(bg:default -weight fg:default)",
      "(bg:red +faint fg:green)👋5(+uline +ideogram:4)6789(off)",
      "01234👋",
      "👋56789",
    ]
  )
}

///|
test "OSC 8 hyperlinks" {
  let s = "\u{1b}]8;;https://example.com\u{1b}\\clickable text\u{1b}]8;;\u{1b}\\"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(stripped(s))
  out.check(
    [
      "(HREF:https://example.com)clickable text(/HREF)",
      "\u{1b}]8;;https://example.com\u{1b}\\clickable text\u{1b}]8;;\u{1b}\\",
      "clickable text",
    ]
  )
}

///|
test "OSC 8 hyperlink with bold text" {
  let s = "\u{1b}]8;;https://example.com\u{1b}\\\u{1b}[1mbold link\u{1b}[0m\u{1b}]8;;\u{1b}\\"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(stripped(s))
  out.check(
    [
      "(HREF:https://example.com)(+bold)bold link(off)(/HREF)",
      "\u{1b}]8;;https://example.com\u{1b}\\\u{1b}[1mbold link\u{1b}[0m\u{1b}]8;;\u{1b}\\",
      "bold link",
    ]
  )
}

///|
test "OSC 8 hyperlink with colored text" {
  let s = "\u{1b}]8;;https://example.com\u{1b}\\\u{1b}[31mred link\u{1b}[0m\u{1b}]8;;\u{1b}\\ and \u{1b}]8;;https://other.com\u{1b}\\\u{1b}[42mgreen link\u{1b}[49m\u{1b}]8;;\u{1b}\\"
  let out = Out::new()
  out.println(vis(s))
  out.println(mini(s))
  out.println(stripped(s))
  out.check(
    [
      "(HREF:https://example.com)(fg:red)red link(off)(/HREF) and (HREF:https://other.com)(bg:green)green link(bg:default)(/HREF)",
      "\u{1b}]8;;https://example.com\u{1b}\\\u{1b}[31mred link\u{1b}[0m\u{1b}]8;;\u{1b}\\ and \u{1b}]8;;https://other.com\u{1b}\\\u{1b}[42mgreen link\u{1b}[49m\u{1b}]8;;\u{1b}\\",
      "red link and green link",
    ]
  )
}

///|
test "parse |> to_string appropriately preserves input" {
  let out = Out::new()
  out.println(round_trip("plain text"))
  out.check(
    [
      "plain text",
    ]
  )
  out.println(round_trip("\u{1b}[31mred\u{1b}[0m"))
  out.check(
    [
      "\\027[31mred\\027[0m",
    ]
  )
  out.println(round_trip("\u{1b}[1;38;5;196mbold bright red\u{1b}[0m"))
  out.check(
    [
      "\\027[1;38;5;196mbold bright red\\027[0m",
    ]
  )
  out.println(
    round_trip("\u{1b}]8;;https://example.com\u{1b}\\link\u{1b}]8;;\u{1b}\\"),
  )
  out.check(
    [
      "\\027]8;;https://example.com\\027\\\\link\\027]8;;\\027\\\\",
    ]
  )
  out.println(round_trip("\u{1b}[0;32~;42m"))
  out.check(
    [
      "\\027[0;32~;42m",
    ]
  )
  out.println(round_trip("before\u{1b}[1mbold\u{1b}[0mafter"))
  out.check(
    [
      "before\\027[1mbold\\027[0mafter",
    ]
  )
  out.println(round_trip("\u{1b}[1m\u{1b}[31m\u{1b}[42m"))
  out.check(
    [
      "\\027[1m\\027[31m\\027[42m",
    ]
  )
  out.println(round_trip("text\u{1b}"))
  out.check(
    [
      "text\\027",
    ]
  )
  out.println(round_trip("\u{1b}c"))
  out.check(
    [
      "\\027c",
    ]
  )
}

///|
test "ESC handling: structure and roundtripping" {
  let out = Out::new()
  fn test_(s : String) -> Unit {
    let parsed = parse(b(s))
    let serialized = to_bytes(parsed)
    out.println("input:      " + escaped(b(s)))
    out.println("serialized: " + escaped(serialized))
    if serialized != b(s) {
      out.print("not equivalent!")
    }
    out.println(vis(s))
    out.println("")
  }

  // ESC at end of input
  test_("text\u{1b}")
  out.check(
    [
      "input:      text\\027",
      "serialized: text\\027",
      "text(ESC)",
    ]
  )
  // ESC followed by ESC: each preserved separately
  test_("\u{1b}\u{1b}")
  out.check(
    [
      "input:      \\027\\027",
      "serialized: \\027\\027",
      "(ESC)(ESC)",
    ]
  )
  // ESC-CSI-ESC: two incomplete ESCs surrounding valid CSI
  test_("\u{1b}\u{1b}[31m\u{1b}")
  out.check(
    [
      "input:      \\027\\027[31m\\027",
      "serialized: \\027\\027[31m\\027",
      "(ESC)(fg:red)(ESC)",
    ]
  )
  // Simple Fe escape sequence
  test_("\u{1b}c")
  out.check(
    [
      "input:      \\027c",
      "serialized: \\027c",
      "(ANSI-Fp:c)",
    ]
  )
  // Multiple Fe escapes followed by text
  test_("\u{1b}some\u{1b}text")
  out.check(
    [
      "input:      \\027some\\027text",
      "serialized: \\027some\\027text",
      "(ANSI-Fp:s)ome(ANSI-Fp:t)ext",
    ]
  )
  // nF escape sequences roundtrip correctly.
  test_("before\u{1b} Fbetween\u{1b}(Bafter")
  out.check(
    [
      "input:      before\\027 Fbetween\\027(Bafter",
      "serialized: before\\027 Fbetween\\027(Bafter",
      "before(ANSI-nF: F)between(ANSI-nF:(B)after",
    ]
  )
}

///|
test "CSI with non-alpha final bytes" {
  let out = Out::new()
  fn test_(s : String) -> Unit {
    out.println(vis(s))
    out.println(round_trip(s))
  }

  // @ is 0x40, the start of the final byte range
  test_("\u{1b}[1@")
  out.check(
    [
      "(ANSI-CSI:1@)",
      "\\027[1@",
    ]
  )
  // ~ is 0x7E, the end of the final byte range
  test_("\u{1b}[1~")
  out.check(
    [
      "(ANSI-CSI:1~)",
      "\\027[1~",
    ]
  )
  // ` is 0x60
  test_("\u{1b}[5`")
  out.check(
    [
      "(ANSI-CSI:5`)",
      "\\027[5`",
    ]
  )
}

///|
test "CSI with out-of-range parameters becomes Unknown" {
  let out = Out::new()
  fn test_(s : String) -> Unit {
    out.println(vis(s))
    out.println(round_trip(s))
  }

  // Valid EraseDisplay
  test_("\u{1b}[2J")
  out.check(
    [
      "(EraseScreen)",
      "\\027[2J",
    ]
  )
  // Invalid EraseDisplay parameter (5 is out of range)
  test_("\u{1b}[5J")
  out.check(
    [
      "(ANSI-CSI:5J)",
      "\\027[5J",
    ]
  )
  // Valid EraseLine
  test_("\u{1b}[2K")
  out.check(
    [
      "(EraseLine)",
      "\\027[2K",
    ]
  )
  // Invalid EraseLine parameter (5 is out of range)
  test_("\u{1b}[5K")
  out.check(
    [
      "(ANSI-CSI:5K)",
      "\\027[5K",
    ]
  )
}

///|
/// vis + round trip, as printed by most of the remaining tests.
fn show_both(out : Out, s : String) -> Unit {
  out.println(vis(s))
  out.println(round_trip(s))
}

///|
test "SGR with out-of-range 256-color code" {
  let out = Out::new()
  show_both(out, "\u{1b}[38;5;300mtext\u{1b}[0m")
  out.check(
    [
      "(ANSI-SGR:38;5;300)text(off)",
      "\\027[38;5;300mtext\\027[0m",
    ]
  )
}

///|
test "SGR with unknown color type" {
  let out = Out::new()
  show_both(out, "\u{1b}[38;3;1;2;3mtext\u{1b}[0m")
  out.check(
    [
      "(ANSI-SGR:38 +italic +bold +faint +italic)text(off)",
      "\\027[38;3;1;2;3mtext\\027[0m",
    ]
  )
}

///|
test "multiple valid codes interleaved with unknown codes" {
  let out = Out::new()
  show_both(out, "\u{1b}[1;110;31;38;5;300;4mtext\u{1b}[0m")
  out.check(
    [
      "(+bold ANSI-SGR:110 fg:red ANSI-SGR:38;5;300 +uline)text(off)",
      "\\027[1;110;31;38;5;300;4mtext\\027[0m",
    ]
  )
}

///|
test "complex SGR: many RGB colors" {
  let out = Out::new()
  show_both(out, "\u{1b}[38;2;255;0;0;48;2;0;255;0;58;2;0;0;255mtext\u{1b}[0m")
  out.check(
    [
      "(fg:rgb256-255-0-0 bg:rgb256-0-255-0 ul:rgb256-0-0-255)text(off)",
      "\\027[38;2;255;0;0;48;2;0;255;0;58;2;0;0;255mtext\\027[0m",
    ]
  )
}

///|
test "unterminated OSC followed by CSI" {
  let out = Out::new()
  show_both(out, "\u{1b}]8;;url\u{1b}[31mred\u{1b}[0m")
  out.check(
    [
      "(ANSI-Fe:])8;;url(fg:red)red(off)",
      "\\027]8;;url\\027[31mred\\027[0m",
    ]
  )
}

///|
test "private mode sequences - show/hide cursor" {
  let out = Out::new()
  show_both(out, "\u{1b}[?25hvisible\u{1b}[?25l")
  out.check(
    [
      "(PrivateMode:set:25)visible(PrivateMode:reset:25)",
      "\\027[?25hvisible\\027[?25l",
    ]
  )
}

///|
test "private mode sequences - alternate screen" {
  let out = Out::new()
  show_both(out, "\u{1b}[?1049hALT\u{1b}[?1049l")
  out.check(
    [
      "(PrivateMode:set:1049)ALT(PrivateMode:reset:1049)",
      "\\027[?1049hALT\\027[?1049l",
    ]
  )
}

///|
test "private mode sequences - old alternate screen" {
  let out = Out::new()
  show_both(out, "\u{1b}[?47hALT\u{1b}[?47l")
  out.check(
    [
      "(PrivateMode:set:47)ALT(PrivateMode:reset:47)",
      "\\027[?47hALT\\027[?47l",
    ]
  )
}

///|
test "private mode sequences - bracketed paste" {
  let out = Out::new()
  show_both(out, "\u{1b}[?2004htext\u{1b}[?2004l")
  out.check(
    [
      "(PrivateMode:set:2004)text(PrivateMode:reset:2004)",
      "\\027[?2004htext\\027[?2004l",
    ]
  )
}

///|
test "private mode sequences - multiple modes" {
  let out = Out::new()
  show_both(out, "\u{1b}[?25;47htext\u{1b}[?25;47l")
  out.check(
    [
      "(PrivateMode:set:25;47)text(PrivateMode:reset:25;47)",
      "\\027[?25;47htext\\027[?25;47l",
    ]
  )
}

///|
test "private mode - is_alternate_screen helper" {
  let out = Out::new()
  fn test_(s : String) -> Unit {
    for element in parse(b(s)) {
      if element is PrivateMode(pm) {
        let modes = pm.modes.map(m => m.to_string()).join(",")
        out.println("modes=\{modes} is_alt=\{pm.is_alternate_screen()}")
      }
    }
  }

  test_("\u{1b}[?25h")
  test_("\u{1b}[?47h")
  test_("\u{1b}[?1049h")
  test_("\u{1b}[?25;1049h")
  out.check(
    [
      "modes=25 is_alt=false",
      "modes=47 is_alt=true",
      "modes=1049 is_alt=true",
      "modes=25,1049 is_alt=true",
    ]
  )
}

///|
test "DSR sequences - cursor position query" {
  let out = Out::new()
  show_both(out, "\u{1b}[6n")
  out.check(
    [
      "(DSR:cursor-position)",
      "\\027[6n",
    ]
  )
}

///|
test "DSR sequences - device status query" {
  let out = Out::new()
  show_both(out, "\u{1b}[5n")
  out.check(
    [
      "(DSR:device-status)",
      "\\027[5n",
    ]
  )
}

///|
test "DSR sequences - other numeric query" {
  let out = Out::new()
  show_both(out, "\u{1b}[0n")
  out.check(
    [
      "(DSR:0)",
      "\\027[0n",
    ]
  )
}

///|
test "OSC sequences - window title with BEL" {
  let out = Out::new()
  show_both(out, "\u{1b}]0;my window title\u{7}")
  out.check(
    [
      "(OSC:title:my window title)",
      "\\027]0;my window title\\027\\\\",
    ]
  )
}

///|
test "OSC sequences - window title with ST" {
  let out = Out::new()
  show_both(out, "\u{1b}]2;another title\u{1b}\\")
  out.check(
    [
      "(OSC:title:another title)",
      "\\027]0;another title\\027\\\\",
    ]
  )
}

///|
test "OSC sequences - icon name" {
  let out = Out::new()
  show_both(out, "\u{1b}]1;my icon\u{7}")
  out.check(
    [
      "(OSC:icon:my icon)",
      "\\027]1;my icon\\027\\\\",
    ]
  )
}

///|
test "OSC sequences - working directory" {
  let out = Out::new()
  show_both(out, "\u{1b}]7;file:///home/user\u{7}")
  out.check(
    [
      "(OSC:cwd:file:///home/user)",
      "\\027]7;file:///home/user\\027\\\\",
    ]
  )
}

///|
test "OSC sequences - other/unknown" {
  let out = Out::new()
  show_both(out, "\u{1b}]99;some payload\u{7}")
  out.check(
    [
      "(OSC:99;some payload)",
      "\\027]99;some payload\\027\\\\",
    ]
  )
}

///|
/// Deterministic pseudo-random numbers, standing in for Quickcheck.
struct Rng {
  mut state : Int
}

///|
fn Rng::next(self : Rng, bound : Int) -> Int {
  self.state = self.state * 1103515245 + 12345
  ((self.state >> 8) & 0x7fffff) % bound
}

///|
/// Like Quickcheck's `weighted_union` of char generators: pick a group by
/// weight, then a char uniformly within the group.
fn Rng::random_string(
  self : Rng,
  weighted : Array[(Int, Array[Char])],
) -> String {
  let total = weighted.fold(init=0, (acc, e) => acc + e.0)
  let len = self.next(51)
  let buf = StringBuilder()
  for _ in 0..<len {
    let mut r = self.next(total)
    for entry in weighted {
      if r < entry.0 {
        buf.write_char(entry.1[self.next(entry.1.length())])
        break
      }
      r -= entry.0
    }
  }
  buf.to_string()
}

///|
fn digits() -> Array[Char] {
  ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
}

///|
fn alphas() -> Array[Char] {
  let out = []
  for n in 97..=122 {
    out.push(Int::unsafe_to_char(n))
    out.push(Int::unsafe_to_char(n - 32))
  }
  out
}

///|
fn printables() -> Array[Char] {
  let out = []
  for n in 32..=126 {
    out.push(Int::unsafe_to_char(n))
  }
  out
}

// Quickcheck tests for parsing. The upstream tests use random generators; here
// the same properties are checked over a fixed number of deterministic
// pseudo-random samples drawn from the same alphabets.
//
// Note: We do NOT guarantee exact byte-for-byte roundtripping for all inputs.
// Some escape sequences normalize during parsing: semantically equivalent
// sequences may serialize to a canonical form. Instead, we test that parsing is
// idempotent: once a string has been parsed and serialized, parsing it again
// produces the same result.

///|
test "quickcheck: parsing is idempotent (parse . to_string . parse = parse)" {
  let rng = Rng::{ state: 12345 }
  // weights are doubled relative to upstream so that 0.5 becomes 1
  let weighted = [
    (2, ['\u{1b}']),
    (2, ['[']),
    (2, [']']),
    (2, ['\\']),
    (2, ['m']),
    (1, [';']),
    (6, digits()),
    (4, alphas()),
    (2, printables()),
  ]
  for _ in 0..<5000 {
    let s = b(rng.random_string(weighted))
    let once = parse(s)
    let twice = parse(to_bytes(once))
    if once != twice {
      fail(
        "Parsing not idempotent: s=\{escaped(s)} once=\{escaped(to_bytes_hum(once))} serialized=\{escaped(to_bytes(once))} twice=\{escaped(to_bytes_hum(twice))}",
      )
    }
  }
}

///|
test "quickcheck: to_string output always parses cleanly" {
  // Any Text_with_ansi.t, when serialized, should parse without becoming
  // malformed text (i.e., all escape sequences should be valid).
  let has_malformed_text = (t : Array[Element]) => t.any(e => match e {
      Text(text) =>
        @bstr.contains(text.str, b"\x1b[") || @bstr.contains(text.str, b"\x1b]")
      _ => false
    })
  let pool : Array[Element] = []
  for snippet in [
    "plain", " ", "é👋", "\u{1b}[31m", "\u{1b}[0m", "\u{1b}[1;38;5;196m", "\u{1b}[38;2;1;2;3;4m",
    "\u{1b}]8;;https://x.com\u{1b}\\", "\u{1b}]8;;\u{1b}\\", "\u{1b}[A", "\u{1b}[;2H", "\u{1b}[3;4H",
    "\u{1b}[2J", "\u{1b}[5J", "\u{1b}[K", "\u{1b}[?25h", "\u{1b}[?1049l", "\u{1b}[6n", "\u{1b}[0n",
    "\u{1b}]0;title\u{7}", "\u{1b}]7;file:///x\u{7}", "\u{1b}]99;p\u{7}", "\u{1b}[1@", "\u{1b}c",
    "\u{1b}(B", "\u{1b}", "\u{1b}[38;5;300m", "\u{1b}[110m",
  ] {
    pool.push_iter(parse(b(snippet)).iter())
  }
  let rng = Rng::{ state: 777 }
  for _ in 0..<5000 {
    let t = []
    for _ in 0..<rng.next(9) {
      t.push(pool[rng.next(pool.length())])
    }
    let serialized = to_bytes(t)
    let reparsed = parse(serialized)
    if has_malformed_text(reparsed) {
      fail(
        "Serialization produced malformed escape sequences: t=\{escaped(to_bytes_hum(t))} serialized=\{escaped(serialized)} reparsed=\{escaped(to_bytes_hum(reparsed))}",
      )
    }
  }
}

///|
test "quickcheck: parsing never puts ESC in text" {
  // Every ESC (0x1B) in the input should be captured by an escape sequence
  // type, never left as raw text.
  let has_esc_in_text = (t : Array[Element]) => t.any(e => match e {
      Text(text) => text.str.iter().any(c => c == b'\x1b')
      _ => false
    })
  let rng = Rng::{ state: 4242 }
  let weighted = [
    (4, ['\u{1b}']),
    (2, ['[']),
    (2, [']']),
    (2, ['\\']),
    (2, ['m']),
    (1, [';']),
    (4, digits()),
    (4, alphas()),
  ]
  for _ in 0..<5000 {
    let s = b(rng.random_string(weighted))
    let parsed = parse(s)
    if has_esc_in_text(parsed) {
      fail("ESC found in text element: s=\{escaped(s)} parsed=\{escaped(to_bytes_hum(parsed))}")
    }
  }
}
