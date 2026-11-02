///|
/// Port of `ansi_text/test/test_style_ranges.ml`.
fn diff1() -> String {
  "\u{1b}[41;30m-\u{1b}[49;39m\u{1b}[0m\u{1b}[90m(** The wire\u{1b}[39m\u{1b}[1;31m kind\u{1b}[22;39m\u{1b}[90m of a bricks log *)\u{1b}[39m\n\u{1b}[41;30m-\u{1b}[49;39m\u{1b}[0m\u{1b}[90mval\u{1b}[39m\u{1b}[1;31m kind\u{1b}[22;39m\u{1b}[90m : Log_wire.wire_\u{1b}[39m\u{1b}[1;31mkind\u{1b}[22;39m\n\u{1b}[42;30m+\u{1b}[49;39m\u{1b}[0m(** The wire\u{1b}[32m class\u{1b}[39m of a bricks log *)\n\u{1b}[42;30m+\u{1b}[49;39m\u{1b}[0mval\u{1b}[32m wire_class\u{1b}[39m : Log_wire.wire_\u{1b}[32mclass\u{1b}[39m"
}

///|
fn header() -> String {
  "\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m      \u{1b}[35mView 1/1 : feature-ddiff\u{1b}[39m      \u{1b}[1;94m@@@@@@@@\u{1b}[22;39m\n\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;48;2;80;40;80;37m--\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31mold base\u{1b}[39m \u{1b}[1m/\u{1b}[22m \u{1b}[32mold tip\u{1b}[39m \u{1b}[1m1,44\u{1b}[22m \u{1b}[1;94m@@@@@@@@\u{1b}[22;39m\n\u{1b}[1;94m@@@@@@@@\u{1b}[22;39m \u{1b}[1;48;2;20;60;120;37m++\u{1b}[22;49;39m \u{1b}[1mdiff of\u{1b}[22m \u{1b}[31mnew base\u{1b}[39m \u{1b}[1m/\u{1b}[22m \u{1b}[32mnew tip\u{1b}[39m \u{1b}[1m1,31\u{1b}[22m \u{1b}[1;94m@@@@@@@@\u{1b}[22;39m"
}

///|
fn diff2() -> String {
  "\u{1b}[1;48;2;200;100;0;37m!!\u{1b}[22;49;39m\u{1b}[41;30m-\u{1b}[49;39m\u{1b}[0m\u{1b}[90mval\u{1b}[39m\u{1b}[1;31m kind\u{1b}[22;39m\u{1b}[90m :\u{1b}[48;2;80;40;80m B.Log\u{1b}[49m.wire_\u{1b}[39m\u{1b}[1;31mkind\u{1b}[22;39m               │\u{1b}[1;48;2;200;100;0;37m!!\u{1b}[22;49;39m\u{1b}[41;30m-\u{1b}[49;39m\u{1b}[0m\u{1b}[90mval\u{1b}[39m\u{1b}[1;31m kind\u{1b}[22;39m\u{1b}[90m :\u{1b}[48;2;20;60;120m Log_wire\u{1b}[49m.wire_\u{1b}[39m\u{1b}[1;31mkind\u{1b}[22;39m\n\u{1b}[1;48;2;200;100;0;37m!!\u{1b}[22;49;39m\u{1b}[42;30m+\u{1b}[49;39m\u{1b}[0mval\u{1b}[32m wire_class\u{1b}[39m :\u{1b}[48;2;80;40;80m B.Log\u{1b}[49m.wire_\u{1b}[32mclass\u{1b}[39m        │\u{1b}[1;48;2;200;100;0;37m!!\u{1b}[22;49;39m\u{1b}[42;30m+\u{1b}[49;39m\u{1b}[0mval\u{1b}[32m wire_class\u{1b}[39m :\u{1b}[48;2;20;60;120m Log_wire\u{1b}[49m.wire_\u{1b}[32mclass\u{1b}[39m"
}

///|
fn with_ranges_of(s : String) -> TextWithStyleRanges {
  TextWithStyleRanges::of_text_with_ansi(@ansi_text.parse(b(s))).unwrap()
}

///|
test "find ranges in a patdiff body" {
  let with_ranges = with_ranges_of(diff1())
  let out = Out::new()
  out.println(str(with_ranges.to_unstyled()))
  out.println(str(with_ranges.to_bytes_hum()))
  out.check(
    [
      "-(** The wire kind of a bricks log *)",
      "-val kind : Log_wire.wire_kind",
      "+(** The wire class of a bricks log *)",
      "+val wire_class : Log_wire.wire_class",
      "(bg:red fg:black)-(bg:default fg:default)(fg:gray)(off)(** The wire(fg:default)(+bold fg:red) kind(-weight fg:default)(fg:gray) of a bricks log *)",
      "(fg:default)(bg:red fg:black)-(bg:default fg:default)(fg:gray)val(fg:default)(+bold fg:red) kind(-weight fg:default)(fg:gray) : Log_wire.wire_(fg:default)(+bold fg:red)kind",
      "(-weight fg:default)(bg:green fg:black)+(bg:default fg:default)(off)(** The wire(fg:green) class(fg:default) of a bricks log *)",
      "(bg:green fg:black)+(bg:default fg:default)val(fg:green) wire_class(fg:default) : Log_wire.wire_(fg:green)class(fg:default)",
    ]
  )
}

///|
test "find ranges in a patdiff4 header" {
  let with_ranges = with_ranges_of(header())
  let out = Out::new()
  out.println(str(with_ranges.to_unstyled()))
  out.println(str(with_ranges.to_bytes_hum()))
  out.check(
    [
      "@@@@@@@@      View 1/1 : feature-ddiff      @@@@@@@@",
      "@@@@@@@@ -- diff of old base / old tip 1,44 @@@@@@@@",
      "@@@@@@@@ ++ diff of new base / new tip 1,31 @@@@@@@@",
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default)      (fg:magenta)View 1/1 : feature-ddiff(fg:default)      (+bold fg:bright-blue)@@@@@@@@",
      "(-weight fg:default)(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:rgb256-80-40-80 fg:white)--(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)old base(fg:default) (+bold)/(-weight) (fg:green)old tip(fg:default) (+bold)1,44(-weight) (+bold fg:bright-blue)@@@@@@@@",
      "(-weight fg:default)(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:rgb256-20-60-120 fg:white)++(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)new base(fg:default) (+bold)/(-weight) (fg:green)new tip(fg:default) (+bold)1,31(-weight) (+bold fg:bright-blue)@@@@@@@@(-weight fg:default)",
    ]
  )
}

///|
test "find ranges in side-by-side patdiff4 output" {
  let with_ranges = with_ranges_of(diff2())
  let out = Out::new()
  out.println(str(with_ranges.to_unstyled()))
  out.check(
    [
      "!!-val kind : B.Log.wire_kind               │!!-val kind : Log_wire.wire_kind",
      "!!+val wire_class : B.Log.wire_class        │!!+val wire_class : Log_wire.wire_class",
    ],
  )
  // The upstream test prints the sexp of the ranges; the same ranges are
  // asserted structurally here.
  let expected : Array[StyleRange] = [
    { start: 0, end: 2, style: [Bold, Bg(Rgb256({ r: 200, g: 100, b: 0 })), Fg(Standard(White))] },
    { start: 2, end: 3, style: [Bg(Standard(Red)), Fg(Standard(Black))] },
    { start: 3, end: 6, style: [Fg(Bright(Black))] },
    { start: 3, end: 48, style: [Reset] },
    { start: 6, end: 11, style: [Bold, Fg(Standard(Red))] },
    { start: 11, end: 25, style: [Fg(Bright(Black))] },
    { start: 13, end: 19, style: [Bg(Rgb256({ r: 80, g: 40, b: 80 }))] },
    { start: 25, end: 29, style: [Bold, Fg(Standard(Red))] },
    { start: 45, end: 47, style: [Bold, Bg(Rgb256({ r: 200, g: 100, b: 0 })), Fg(Standard(White))] },
    { start: 47, end: 48, style: [Bg(Standard(Red)), Fg(Standard(Black))] },
    { start: 48, end: 51, style: [Fg(Bright(Black))] },
    { start: 51, end: 56, style: [Bold, Fg(Standard(Red))] },
    { start: 56, end: 73, style: [Fg(Bright(Black))] },
    { start: 58, end: 67, style: [Bg(Rgb256({ r: 20, g: 60, b: 120 }))] },
    { start: 73, end: 77, style: [Bold, Fg(Standard(Red))] },
    { start: 77, end: 79, style: [Bold, Bg(Rgb256({ r: 200, g: 100, b: 0 })), Fg(Standard(White))] },
    { start: 79, end: 80, style: [Bg(Standard(Green)), Fg(Standard(Black))] },
    { start: 80, end: 125, style: [Reset] },
    { start: 83, end: 94, style: [Fg(Standard(Green))] },
    { start: 96, end: 102, style: [Bg(Rgb256({ r: 80, g: 40, b: 80 }))] },
    { start: 108, end: 113, style: [Fg(Standard(Green))] },
    { start: 122, end: 124, style: [Bold, Bg(Rgb256({ r: 200, g: 100, b: 0 })), Fg(Standard(White))] },
    { start: 124, end: 125, style: [Bg(Standard(Green)), Fg(Standard(Black))] },
    { start: 128, end: 139, style: [Fg(Standard(Green))] },
    { start: 141, end: 150, style: [Bg(Rgb256({ r: 20, g: 60, b: 120 }))] },
    { start: 156, end: 161, style: [Fg(Standard(Green))] },
  ]
  @test.assert_eq(with_ranges.ranges, expected)
}

///|
test "apply" {
  let text = Text::of_bytes(b("some uninteresting text"))
  let style : Array[Attr] = [Bold, Italic, Bg(Bright(Magenta)), Fg(Bright(Green))]
  let range = [StyleRange::{ start: 5, end: 18, style }]
  let styled_text = @ansi_text.style_ranges_apply(text~, range)
  let out = Out::new()
  out.println(str(@ansi_text.to_bytes_hum(styled_text)))
  out.check(
    [
      "some (+bold +italic bg:bright-magenta fg:bright-green)uninteresting(-weight -italic bg:default fg:default) text",
    ]
  )
}

///|
test "unstyle_between" {
  let styled = with_ranges_of(header())
  let partially_styled = styled.unstyle_between(start=52, end=104)
  let out = Out::new()
  out.println(str(partially_styled.to_bytes_hum()))
  out.check(
    [
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default)      (fg:magenta)View 1/1 : feature-ddiff(fg:default)      (+bold fg:bright-blue)@@@@@@@@",
      "(-weight fg:default)@@@@@@@@ -- diff of old base / old tip 1,44 @@@@@@@@",
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:rgb256-20-60-120 fg:white)++(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)new base(fg:default) (+bold)/(-weight) (fg:green)new tip(fg:default) (+bold)1,31(-weight) (+bold fg:bright-blue)@@@@@@@@(-weight fg:default)",
    ]
  )
}

///|
test "split" {
  let (first, second) = with_ranges_of(header()).split(pos=52)
  let out = Out::new()
  out.println(str(first.to_bytes_hum()))
  out.println("")
  out.println(str(second.to_bytes_hum()))
  out.check(
    [
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default)      (fg:magenta)View 1/1 : feature-ddiff(fg:default)      (+bold fg:bright-blue)@@@@@@@@",
      "(-weight fg:default)",
      "",
      "(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:rgb256-80-40-80 fg:white)--(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)old base(fg:default) (+bold)/(-weight) (fg:green)old tip(fg:default) (+bold)1,44(-weight) (+bold fg:bright-blue)@@@@@@@@",
      "(-weight fg:default)(+bold fg:bright-blue)@@@@@@@@(-weight fg:default) (+bold bg:rgb256-20-60-120 fg:white)++(-weight bg:default fg:default) (+bold)diff of(-weight) (fg:red)new base(fg:default) (+bold)/(-weight) (fg:green)new tip(fg:default) (+bold)1,31(-weight) (+bold fg:bright-blue)@@@@@@@@(-weight fg:default)",
    ]
  )
}
