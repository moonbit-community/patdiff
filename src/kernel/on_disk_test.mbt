///|
fn parse_config(text : String) -> @kernel.Configuration raise {
  @kernel.OnDisk::of_sexp(@sexp.Sexp::parse(b(text))).to_configuration()
}

///|
test "the default config file gives the default configuration" {
  let on_disk = @kernel.OnDisk::of_sexp(
    @sexp.Sexp::parse(@kernel.default_config_string()),
  )
  @test.assert_eq(
    on_disk.to_configuration() == @kernel.Configuration::default(),
    true,
  )
}

///|
test "built-in color schemes parse" {
  @test.assert_eq(@kernel.dark_bg_configuration().context, 8)
  @test.assert_eq(@kernel.light_bg_configuration().context, 8)
}

///|
test "default config text matches upstream's line rules" {
  let text = shown(@kernel.default_config_string())
  @test.assert_eq(
    text.contains(
      "(line_same ((prefix((text\" |\")(style((Bg(Bright Black))(Fg(Standard Black))))))))",
    ),
    true,
  )
  @test.assert_eq(
    text.contains(
      "(line_old ((prefix((text -|)(style((Bg(Standard Red))(Fg(Standard Black))))))(style((Fg(Standard Red))))(word_same((Fg(Gray24((level 12))))))))",
    ),
    true,
  )
}

///|
test "v1 html and unrefined propagate" {
  let config = parse_config("((html true) (unrefined true))")
  @test.assert_eq(config.output == Html, true)
  @test.assert_eq(config.unrefined, true)
  let config = parse_config("((unrefined false))")
  @test.assert_eq(config.output == Ansi, true)
  @test.assert_eq(config.unrefined, false)
}

///|
test "v2 output field flows into both output and unrefined" {
  let check = fn(text : String, output : @kernel.Output, unrefined : Bool) raise {
    let config = parse_config(text)
    @test.assert_eq(config.output == output, true)
    @test.assert_eq(config.unrefined, unrefined)
  }
  check("((output html))", Html, false)
  check("((output ansi))", Ansi, false)
  check("((output ascii))", Ascii, true)
  check("((output (unrefined html)))", Html, true)
  check("((output (unrefined ansi)))", Ansi, true)
}

///|
test "v3 fields" {
  let config = parse_config(
    "((output (side_by_side truncate)) (find_moves true) (width_override 100))",
  )
  @test.assert_eq(config.side_by_side == Some(Truncate), true)
  @test.assert_eq(config.find_moves, true)
  @test.assert_eq(config.width_override, Some(100))
}

///|
test "v0 configs still work" {
  let config = parse_config(
    "((context 3) (hide_uniques true) (word_same ((style_old ()) (style_new ()))))",
  )
  @test.assert_eq(config.context, 3)
  @test.assert_eq(config.mask_uniques, true)
}

///|
test "prefixes are padded to the same width" {
  let config = parse_config("((line_same ((prefix ((text \"same \"))))))")
  @test.assert_eq(shown(config.rules.line_same.pre.text), "same ")
  @test.assert_eq(shown(config.rules.line_prev.pre.text), "   -|")
}

///|
test "legacy color and style names" {
  let config = parse_config(
    "((line_same ((style (dim inverse emph (Fg bright_blue) (Bg (Gray24 ((level 3)))))))))",
  )
  debug_inspect(
    config.rules.line_same.styles,
    content="[Faint, Invert, Italic, Fg(Bright(Blue)), Bg(Gray24({ level: 3 }))]",
  )
}

///|
test "unknown fields are rejected" {
  let failed = try {
    let _ = parse_config("((no_such_field 1))")
    false
  } catch {
    _ => true
  }
  @test.assert_eq(failed, true)
}

///|
test "round trip through to_sexp" {
  let on_disk = @kernel.OnDisk::of_sexp(
    @sexp.Sexp::parse(@kernel.default_config_string()),
  )
  let again = @kernel.OnDisk::of_sexp(on_disk.to_sexp())
  @test.assert_eq(again == on_disk, true)
}
