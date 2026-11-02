///|
/// Output formats. `Ascii` is `Ansi` with no styles.
pub(all) enum Output {
  Ansi
  Ascii
  Html
} derive(Debug, Eq)

///|
pub fn Output::implies_unrefined(self : Output) -> Bool {
  self is Ascii
}

///|
/// What the diffing code needs from its environment. This stands in for the
/// `Output_impls` functor argument of the OCaml version.
pub(all) struct Platform {
  /// Modification time of a file in seconds since the epoch, for HTML headers.
  mtime : (FileName) -> Double?
  /// Width of the terminal, when known.
  console_width : () -> Int?
  /// Tests render to the full console width. Otherwise a column is reserved,
  /// because diffs are often printed indented by one.
  am_running_test : Bool
}

///|
pub fn Platform::without_unix() -> Platform {
  {
    mtime: _ => None,
    console_width: () => Some(default_double_column_width),
    am_running_test: false,
  }
}

///|
fn apply_rule(
  text : Bytes,
  rule~ : Rule,
  output~ : Output,
  refined~ : Bool,
) -> Bytes {
  match output {
    Ansi => ansi_rule_apply(text, rule~, refined~)
    Ascii => ansi_rule_apply(text, rule=rule.strip_styles(), refined=false)
    Html => html_rule_apply(text, rule~, refined~)
  }
}

///|
fn ansi_rule_apply(text : Bytes, rule~ : Rule, refined~ : Bool) -> Bytes {
  let only_whitespace = !text.is_empty() && @bstr.for_all(text, @bstr.is_whitespace)
  let text_style : Array[@ansi_text.Attr] = if rule.styles.is_empty() {
    []
  } else if refined {
    [Reset]
  } else if only_whitespace {
    let style : Array[@ansi_text.Attr] = [Invert]
    style.push_iter(rule.styles.iter())
    style
  } else {
    rule.styles
  }
  @ansi_text.apply(rule.pre.styles, rule.pre.text) +
  @ansi_text.apply(text_style, text) +
  @ansi_text.apply(rule.suf.styles, rule.suf.text)
}

///|
fn ansi_print(
  print_global_header~ : Bool,
  file_names~ : (FileName, FileName),
  rules~ : Rules,
  print~ : (Bytes) -> Unit,
  location_style~ : LocationStyle,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Unit {
  let (prev_file, next_file) = file_names
  if print_global_header {
    print(
      ansi_rule_apply(prev_file.display_name(), rule=rules.header_prev, refined=false),
    )
    print(
      ansi_rule_apply(next_file.display_name(), rule=rules.header_next, refined=false),
    )
  }
  iter(
    f_hunk_break=hunk => print(
      location_style.sprint(
        hunk,
        prev_filename=prev_file.display_name(),
        rule=text => ansi_rule_apply(text, rule=rules.hunk, refined=false),
      ),
    ),
    f_line=print,
    hunks,
  )
}

///|
fn html_string_of_color(color : @ansi_text.Color) -> String {
  match color {
    Standard(Black) => "#000000"
    Standard(Red) => "#880000"
    Standard(Green) => "#008800"
    Standard(Yellow) => "#888800"
    Standard(Blue) => "#000088"
    Standard(Magenta) => "#880088"
    Standard(Cyan) => "#008888"
    Standard(White) => "#ffffff"
    Default => "#ffffff"
    Bright(Black) => "#c0c0c0"
    Bright(Red) => "#FF0000"
    Bright(Green) => "#00FF00"
    Bright(Yellow) => "#FFFF00"
    Bright(Blue) => "#0000FF"
    Bright(Magenta) => "#FF00FF"
    Bright(Cyan) => "#00FFFF"
    Bright(White) => "#FFFFFF"
    Rgb6({ r, g, b }) => {
      let scaled = x => x * 255 / 5
      "rgb(\{scaled(r)},\{scaled(g)},\{scaled(b)})"
    }
    Gray24({ level }) => {
      let scaled = level * 255 / 23
      "rgb(\{scaled},\{scaled},\{scaled})"
    }
    Rgb256({ r, g, b }) => "rgb(\{r},\{g},\{b})"
  }
}

///|
fn html_style_apply(text : Bytes, styles~ : ArrayView[@ansi_text.Attr]) -> Bytes {
  let start_tags = []
  let end_tags = []
  let tag = (start : String, end : String) => {
    start_tags.push(@bstr.of_string(start))
    end_tags.push(@bstr.of_string(end))
  }
  for style in styles {
    match style {
      Bold => tag("<span style=\"font-weight:bold\">", "</span>")
      Fg(c) => tag("<span style=\"color:\{html_string_of_color(c)}\">", "</span>")
      Bg(c) =>
        tag("<span style=\"background-color:\{html_string_of_color(c)}\">", "</span>")
      Underline | Italic => tag("<u>", "</u>")
      Blink => tag("<span style=\"text-decoration:blink\">", "</span>")
      Hide => tag("<!-- ", " -->")
      Faint =>
        tag(
          "<span style=\"color:\{html_string_of_color(Bright(Black))}\">",
          "</span>",
        )
      _ => ()
    }
  }
  let parts = start_tags.rev()
  parts.push(text)
  parts.push_iter(end_tags.rev_iter())
  @bstr.concat(parts)
}

///|
/// Assuming we only insert text in contents and not in attributes, only
/// escaping these three characters should be enough.
fn html_escape(s : Bytes) -> Bytes {
  let buf = Buffer(size_hint=s.length())
  for c in s {
    match c {
      b'<' => buf.write_bytes(b"&lt;")
      b'>' => buf.write_bytes(b"&gt;")
      b'&' => buf.write_bytes(b"&amp;")
      c => buf.write_byte(c)
    }
  }
  buf.contents()
}

///|
fn html_rule_apply(text : Bytes, rule~ : Rule, refined~ : Bool) -> Bytes {
  html_style_apply(rule.pre.text, styles=rule.pre.styles) +
  (if refined {
    html_style_apply(text, styles=[Reset])
  } else {
    html_style_apply(html_escape(text), styles=rule.styles)
  }) +
  html_style_apply(rule.suf.text, styles=rule.suf.styles)
}

///|
/// `Time_float.to_string_utc`: `YYYY-MM-DD HH:MM:SS.ffffffZ`.
pub fn time_to_string_utc(seconds : Double) -> String {
  let total_micros = (seconds * 1000000.0).round().to_int64()
  let micros_per_day = 86400000000L
  let mut days = total_micros / micros_per_day
  let mut micros_of_day = total_micros % micros_per_day
  if micros_of_day < 0L {
    micros_of_day += micros_per_day
    days -= 1L
  }
  // Howard Hinnant's civil_from_days.
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = doy - (153L * mp + 2L) / 5L + 1L
  let month = if mp < 10L { mp + 3L } else { mp - 9L }
  let year = yoe + era * 400L + (if month <= 2L { 1L } else { 0L })
  let pad = (n : Int64, width : Int) => n
    .to_string()
    .pad_start(width, '0')
    .to_string()
  let second_of_day = micros_of_day / 1000000L
  let date = "\{pad(year, 4)}-\{pad(month, 2)}-\{pad(day, 2)}"
  let time = "\{pad(second_of_day / 3600L, 2)}:\{pad(second_of_day / 60L % 60L, 2)}:\{pad(second_of_day % 60L, 2)}"
  "\{date} \{time}.\{pad(micros_of_day % 1000000L, 6)}Z"
}

///|
fn html_print(
  print_global_header~ : Bool,
  file_names~ : (FileName, FileName),
  rules~ : Rules,
  print~ : (Bytes) -> Unit,
  location_style~ : LocationStyle,
  platform~ : Platform,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Unit {
  let (prev_file, next_file) = file_names
  print(b"<pre style=\"font-family:consolas,monospace\">")
  if print_global_header {
    let print_line = (file : FileName, rule) => {
      let time = match (platform.mtime)(file) {
        Some(time) => @bstr.of_string(time_to_string_utc(time))
        None => b""
      }
      print(
        html_rule_apply(file.display_name() + b" " + time, rule~, refined=false),
      )
    }
    print_line(prev_file, rules.header_prev)
    print_line(next_file, rules.header_next)
  }
  for hunk in hunks {
    print(
      location_style.sprint(
        hunk,
        prev_filename=prev_file.display_name(),
        rule=text => html_rule_apply(text, rule=rules.hunk, refined=false),
      ),
    )
    for range in hunk.ranges {
      match range {
        // Just print the new array elements.
        Same(r) =>
          for pair in r {
            print(pair.1)
          }
        Prev(r, _) | Next(r, _) | Unified(r, _) => r.each(print)
        Replace(ar1, ar2, _) => {
          ar1.each(print)
          ar2.each(print)
        }
      }
    }
  }
  print(b"</pre>")
}

///|
fn print_output(
  output : Output,
  print_global_header~ : Bool,
  file_names~ : (FileName, FileName),
  rules~ : Rules,
  print~ : (Bytes) -> Unit,
  location_style~ : LocationStyle,
  platform~ : Platform,
  hunks : ArrayView[@pd.Hunk[Bytes]],
) -> Unit {
  match output {
    Ansi =>
      ansi_print(print_global_header~, file_names~, rules~, print~, location_style~, hunks)
    Ascii =>
      ansi_print(
        print_global_header~,
        file_names~,
        rules=rules.strip_styles(),
        print~,
        location_style~,
        hunks,
      )
    Html =>
      html_print(
        print_global_header~,
        file_names~,
        rules~,
        print~,
        location_style~,
        platform~,
        hunks,
      )
  }
}
