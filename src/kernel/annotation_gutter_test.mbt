///|
/// Mirrors upstream's `recording_gutter`: renders a one-letter side tag followed
/// by the line number(s) (`prev/next` when they differ).
fn gutter_recording(width~ : Int32) -> @kernel.AnnotationGutter {
  let render = (side : @kernel.GutterSide) => {
    let (tag, body) = match side {
      Prev(line~) => ("P", line.to_string())
      Next(line~) => ("N", line.to_string())
      Same(prev~, next~) =>
        (
          "S",
          if prev == next {
            prev.to_string()
          } else {
            prev.to_string() + "/" + next.to_string()
          },
        )
      Unified(prev~, next~) =>
        (
          "U",
          if prev == next {
            prev.to_string()
          } else {
            prev.to_string() + "/" + next.to_string()
          },
        )
    }
    b(tag + body)
  }
  @kernel.AnnotationGutter::new(width~, render~)
}

///|
fn gutter_strip_rules() -> @kernel.Rules {
  @kernel.Rules::default().strip_styles()
}

///|
fn gutter_to_array(s : String) -> Array[Bytes] {
  @bstr.split_lines(b(s))
}

///|
/// `ppx_expect` ignores trailing whitespace on each line when matching; mirror
/// that (and nothing else) on the actual output.
fn gutter_rstrip_lines(s : String) -> String {
  let out = StringBuilder()
  let lines = s.split("\n").collect()
  for i, line in lines {
    let mut end = line.length()
    while end > 0 && line[end - 1] == ' ' {
      end -= 1
    }
    out.write_string(line[:end].to_owned())
    if i < lines.length() - 1 {
      out.write_char('\n')
    }
  }
  out.to_string()
}

///|
/// Joins lines the way repeated `print_endline` calls would, minus the final
/// newline (an `[%expect]` block ignores it).
fn gutter_join(lines : Array[String]) -> String {
  gutter_rstrip_lines(lines.join("\n"))
}

///|
fn gutter_pairs(blocks : Array[Array[(Bytes, Bytes)]]) -> Array[String] {
  let rows = []
  for block in blocks {
    for pair in block {
      rows.push(@bstr.to_string(pair.0 + b"|" + pair.1))
    }
  }
  rows
}

///|
test "build_unified threads side+line through annotation_gutter" {
  let prev = gutter_to_array("alpha\nbeta\ngamma\ndelta\n")
  let next = gutter_to_array("alpha\nBETA\ngamma\nDELTA\nepsilon\n")
  let hunks = @kernel.diff(
    context=1,
    line_big_enough=3,
    keep_ws=true,
    find_moves=false,
    prev~,
    next~,
  )
  let lines = []
  for
    hunk_lines in @kernel.build_unified(
      annotation_gutter=gutter_recording(width=4),
      rules=gutter_strip_rules(),
      output=Ascii,
      hunks,
    ) {
    for line in hunk_lines {
      lines.push(@bstr.to_string(line))
    }
  }
  @test.assert_eq(
    gutter_join(lines),
    (
      #|S1    alpha
      #|P2  -|beta
      #|N2  +|BETA
      #|S3    gamma
      #|P4  -|delta
      #|N4  +|DELTA
      #|N5  +|epsilon
    ),
  )
}

///|
test "build_unified emits `Same for context lines and `Prev/`Next for changes" {
  let prev = gutter_to_array("ctx1\nold\nctx2\n")
  let next = gutter_to_array("ctx1\nnew\nctx2\n")
  let hunks = @kernel.diff(
    context=1,
    line_big_enough=3,
    keep_ws=true,
    find_moves=false,
    prev~,
    next~,
  )
  let lines = []
  for
    hunk_lines in @kernel.build_unified(
      annotation_gutter=gutter_recording(width=3),
      rules=gutter_strip_rules(),
      output=Ascii,
      hunks,
    ) {
    for line in hunk_lines {
      lines.push(@bstr.to_string(line))
    }
  }
  @test.assert_eq(
    gutter_join(lines),
    (
      #|S1   ctx1
      #|P2 -|old
      #|N2 +|new
      #|S3   ctx2
    ),
  )
}

///|
test "build_unified across multiple hunks emits each hunk's lines independently" {
  // Two changes far apart with -context 1 -> two separate hunks; line numbers reset to
  // each hunk's [prev_start] / [next_start].
  let prev = gutter_to_array("a1\nA1\na2\na3\na4\na5\na6\na7\nA8\na9\n")
  let next = gutter_to_array("a1\nB1\na2\na3\na4\na5\na6\na7\nB8\na9\n")
  let hunks = @kernel.diff(
    context=1,
    line_big_enough=3,
    keep_ws=true,
    find_moves=false,
    prev~,
    next~,
  )
  let lines = []
  for
    i, hunk_lines in @kernel.build_unified(
      annotation_gutter=gutter_recording(width=3),
      rules=gutter_strip_rules(),
      output=Ascii,
      hunks,
    ) {
    if i > 0 {
      lines.push("---")
    }
    for line in hunk_lines {
      lines.push(@bstr.to_string(line))
    }
  }
  @test.assert_eq(
    gutter_join(lines),
    (
      #|S1   a1
      #|P2 -|A1
      #|N2 +|B1
      #|S3   a2
      #|---
      #|S8   a7
      #|P9 -|A8
      #|N9 +|B8
      #|S10  a9
    ),
  )
}

///|
test "build_unified Unified range (produce_unified_lines:true) emits with side:Unified" {
  let prev = gutter_to_array("Foo bar buzz")
  let next = gutter_to_array("Foo buzz")
  let hunks = @kernel.refine(
    rules=@kernel.Rules::default(),
    produce_unified_lines=true,
    output=Ansi,
    keep_ws=true,
    split_long_lines=false,
    interleave=true,
    word_big_enough=3,
    @kernel.diff(
      context=0,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let lines = []
  for
    hunk_lines in @kernel.build_unified(
      annotation_gutter=gutter_recording(width=3),
      rules=@kernel.Rules::default(),
      output=Ansi,
      hunks,
    ) {
    for line in hunk_lines {
      // Strip ANSI escapes so the snapshot is readable.
      lines.push(@bstr.to_string(@ansi_text.strip(line)))
    }
  }
  @test.assert_eq(gutter_join(lines), "U1 !|Foo bar buzz")
}

///|
test "build_unified Unified line carries diverged prev/next line numbers" {
  // A preceding [Prev]-only hunk advances prev_line ahead of next_line, so the next
  // hunk's [Unified] line is rendered with prev <> next.
  let prev = gutter_to_array("extra_line\nctx\nFoo bar buzz")
  let next = gutter_to_array("ctx\nFoo buzz")
  let hunks = @kernel.refine(
    rules=@kernel.Rules::default(),
    produce_unified_lines=true,
    output=Ansi,
    keep_ws=true,
    split_long_lines=false,
    interleave=true,
    word_big_enough=3,
    @kernel.diff(
      context=0,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let lines = []
  for
    hunk_lines in @kernel.build_unified(
      annotation_gutter=gutter_recording(width=4),
      rules=@kernel.Rules::default(),
      output=Ansi,
      hunks,
    ) {
    for line in hunk_lines {
      // Strip ANSI escapes so the snapshot is readable.
      lines.push(@bstr.to_string(@ansi_text.strip(line)))
    }
  }
  @test.assert_eq(
    gutter_join(lines),
    (
      #|P1  -|extra_line
      #|U3/2!|Foo bar buzz
    ),
  )
}

///|
test "build_side_by_side renders gutter on both panes and shrinks panes" {
  let prev = gutter_to_array("a\nb\nc\n")
  let next = gutter_to_array("a\nB\nc\n")
  let hunks = @kernel.unrefined_structured(
    @kernel.diff(
      context=1,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let render_with = (annotation_gutter : @kernel.AnnotationGutter?) => {
    gutter_pairs(
      @kernel.build_side_by_side(
        annotation_gutter?,
        width_override=60,
        rules=gutter_strip_rules(),
        wrap_or_truncate=Neither,
        output=Ascii,
        hunks,
      ),
    )
  }
  let lines = []
  lines.push("without gutter:")
  lines.append(render_with(None))
  lines.push("")
  lines.push("with recording_gutter ~width:3:")
  lines.append(render_with(Some(gutter_recording(width=3))))
  @test.assert_eq(
    gutter_join(lines),
    (
      #|without gutter:
      #|1   a                                                       |1   a
      #|2 -|b                                                       |
      #|                                                            |2 +|B
      #|3   c                                                       |3   c
      #|
      #|with recording_gutter ~width:3:
      #|S1 1   a                                                    |S1 1   a
      #|P2 2 -|b                                                    |
      #|                                                            |N2 2 +|B
      #|S3 3   c                                                    |S3 3   c
    ),
  )
}

///|
test "build_side_by_side wrapping: render is not re-called on continuation rows" {
  // A long line that wraps to multiple display rows. The gutter [render] callback should
  // fire once per source-line emit (not per wrap-row).
  let long = "a".repeat(100)
  let prev = gutter_to_array(long + "\nshort")
  let next = gutter_to_array("short")
  let hunks = @kernel.unrefined_structured(
    @kernel.diff(
      context=0,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let calls : Array[@kernel.GutterSide] = []
  let counting_gutter = @kernel.AnnotationGutter::new(width=3, render=side => {
    calls.push(side)
    b"G"
  })
  let lines = @kernel.build_side_by_side(
    annotation_gutter=counting_gutter,
    width_override=60,
    rules=gutter_strip_rules(),
    wrap_or_truncate=Wrap,
    output=Ascii,
    hunks,
  )
  let mut total_rows = 0
  for block in lines {
    total_rows += block.length()
  }
  // ((render_calls ((Prev (line 1)))) (total_rows 2))
  @test.assert_eq(calls, [Prev(line=1)])
  @test.assert_eq(total_rows, 2)
}

///|
test "build_side_by_side wrapping: gutter renders on the first row only, continuation rows are blank-padded to keep the column aligned" {
  let long = "a".repeat(60)
  let prev = gutter_to_array(long + "\nctx")
  let next = gutter_to_array("ctx")
  let hunks = @kernel.unrefined_structured(
    @kernel.diff(
      context=1,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let lines = gutter_pairs(
    @kernel.build_side_by_side(
      annotation_gutter=gutter_recording(width=3),
      width_override=60,
      rules=gutter_strip_rules(),
      wrap_or_truncate=Wrap,
      output=Ascii,
      hunks,
    ),
  )
  @test.assert_eq(
    gutter_join(lines),
    (
      #|P1 1 -|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|
      #|       aaaaaaa                                              |
      #|S2/2   ctx                                                  |S2/1   ctx
    ),
  )
}

///|
test "build_side_by_side aligned-replace pair: gutter splits to Prev / Next per pane" {
  // [Side_by_side.align_replace_lines] collapses a one-line [Replace] pair into a [Same]
  // line-info with non-`Same segments. The gutter then renders [Prev] on the left pane
  // and [Next] on the right (each with its pane's line number), rather than a single
  // [Same] rendered on both panes.
  let prev = gutter_to_array("abc def ghi")
  let next = gutter_to_array("abc XYZ ghi")
  let hunks = @kernel.refine_structured(
    produce_unified_lines=false,
    keep_ws=true,
    split_long_lines=false,
    interleave=false,
    word_big_enough=3,
    @kernel.diff(
      context=0,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let lines = gutter_pairs(
    @kernel.build_side_by_side(
      annotation_gutter=gutter_recording(width=3),
      width_override=60,
      rules=gutter_strip_rules(),
      wrap_or_truncate=Neither,
      output=Ascii,
      hunks,
    ),
  )
  @test.assert_eq(
    gutter_join(lines),
    "P1 1 !|abc def ghi                                          |N1 1 !|abc XYZ ghi",
  )
}

///|
test "public print_side_by_side forwards annotation_gutter through filename header and body" {
  let prev = gutter_to_array("alpha\nbeta\ngamma\n")
  let next = gutter_to_array("alpha\nBETA\ngamma\n")
  let hunks = @kernel.unrefined_structured(
    @kernel.diff(
      context=1,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let prev_file = @kernel.FileName::Fake(b"prev.txt")
  let next_file = @kernel.FileName::Fake(b"next.txt")
  let lines = []
  @kernel.print_side_by_side(
    annotation_gutter=gutter_recording(width=3),
    width_override=60,
    file_names=(prev_file, next_file),
    rules=gutter_strip_rules(),
    wrap_or_truncate=Truncate,
    output=Ascii,
    print=line => lines.push(@bstr.to_string(line)),
    hunks,
  )
  @test.assert_eq(
    gutter_join(lines),
    (
      #|     -|prev.txt              |     +|next.txt
      #|S1 1   alpha                                                |S1 1   alpha
      #|P2 2 -|beta                                                 |
      #|                                                            |N2 2 +|BETA
      #|S3 3   gamma                                                |S3 3   gamma
    ),
  )
}

///|
test "public output_to_string_side_by_side forwards annotation_gutter" {
  let prev = gutter_to_array("alpha\nbeta\ngamma\n")
  let next = gutter_to_array("alpha\nBETA\ngamma\n")
  let hunks = @kernel.unrefined_structured(
    @kernel.diff(
      context=1,
      line_big_enough=3,
      keep_ws=true,
      find_moves=false,
      prev~,
      next~,
    ),
  )
  let prev_file = @kernel.FileName::Fake(b"prev.txt")
  let next_file = @kernel.FileName::Fake(b"next.txt")
  let s = @kernel.output_to_string_side_by_side(
    annotation_gutter=gutter_recording(width=3),
    width_override=60,
    file_names=(prev_file, next_file),
    rules=gutter_strip_rules(),
    wrap_or_truncate=Truncate,
    output=Ascii,
    hunks,
  )
  @test.assert_eq(
    gutter_rstrip_lines(@bstr.to_string(s)).trim_end(chars="\n").to_owned(),
    (
      #|     -|prev.txt              |     +|next.txt
      #|S1 1   alpha                                                |S1 1   alpha
      #|P2 2 -|beta                                                 |
      #|                                                            |N2 2 +|BETA
      #|S3 3   gamma                                                |S3 3   gamma
    ),
  )
}
