///|
/// A subset of the ANSI select-graphic-rendition attributes, grouped into
/// related attributes that override one another; see
/// https://en.wikipedia.org/wiki/ANSI_escape_code#Select_Graphic_Rendition_parameters.
pub(all) enum Attr {
  Reset
  Bold
  Faint
  NormalWeight
  Italic
  Fraktur
  NotEmphasis
  Underline
  DoubleUl
  NotUnderline
  Blink
  FastBlink
  NotBlink
  Framed
  Encircled
  NotFramed
  Superscript
  Subscript
  NotScript
  Invert
  NotInvert
  Hide
  NotHide
  Strike
  NotStrike
  Overline
  NotOverline
  VariableWidth
  FixedWidth
  Fg(Color)
  Bg(Color)
  UlColor(Color)
  Font(Int32)
  Ideogram(Int32)
  Other(Array[Int32])
} derive(Debug, Eq)

///|
/// An attribute that turns off `self`, if applicable.
pub fn Attr::turn_off(self : Attr) -> Attr? {
  match self {
    Reset => None
    Fg(Default) | Bg(Default) | UlColor(Default) | Font(0) | Ideogram(5) => None
    Fg(_) => Some(Fg(Default))
    Bg(_) => Some(Bg(Default))
    UlColor(_) => Some(UlColor(Default))
    Font(_) => Some(Font(0))
    Ideogram(_) => Some(Ideogram(5))
    Bold | Faint => Some(NormalWeight)
    Italic | Fraktur => Some(NotEmphasis)
    Underline | DoubleUl => Some(NotUnderline)
    Blink | FastBlink => Some(NotBlink)
    Framed | Encircled => Some(NotFramed)
    Superscript | Subscript => Some(NotScript)
    Invert => Some(NotInvert)
    Hide => Some(NotHide)
    Strike => Some(NotStrike)
    Overline => Some(NotOverline)
    VariableWidth => Some(FixedWidth)
    NormalWeight
    | NotEmphasis
    | NotUnderline
    | NotBlink
    | NotInvert
    | NotHide
    | NotStrike
    | NotOverline
    | NotFramed
    | NotScript
    | FixedWidth
    | Other(_) => None
  }
}

///|
/// Whether `new_attr` would completely override the effects of `old_attr`. For
/// example, in `"\x1b[1;2m"` we have `Bold` followed by `Faint`, and afterwards
/// the text is faint. `Reset` overrides everything; other attributes mostly come
/// in pairs or groups of three that mutually override.
pub fn overrides(new_attr~ : Attr, old_attr~ : Attr) -> Bool {
  match (new_attr, old_attr) {
    (Reset, _) => true
    (Bold | Faint | NormalWeight, Bold | Faint | NormalWeight) => true
    (Italic | NotEmphasis | Fraktur, Italic | NotEmphasis | Fraktur) => true
    (Underline | DoubleUl | NotUnderline, Underline | DoubleUl | NotUnderline) =>
      true
    (Blink | FastBlink | NotBlink, Blink | FastBlink | NotBlink) => true
    (Invert | NotInvert, Invert | NotInvert) => true
    (Hide | NotHide, Hide | NotHide) => true
    (Strike | NotStrike, Strike | NotStrike) => true
    (Overline | NotOverline, Overline | NotOverline) => true
    (Framed | Encircled | NotFramed, Framed | Encircled | NotFramed) => true
    (Superscript | Subscript | NotScript, Superscript | Subscript | NotScript) =>
      true
    (VariableWidth | FixedWidth, VariableWidth | FixedWidth) => true
    (Fg(_), Fg(_)) => true
    (Bg(_), Bg(_)) => true
    (UlColor(_), UlColor(_)) => true
    (Font(_), Font(_)) => true
    (Ideogram(_), Ideogram(_)) => true
    _ => false
  }
}

///|
fn of_color_code(code : ArrayView[Int32]) -> Color? {
  match code {
    [5, c] if c >= 0 && c <= 7 => Some(sgr8(c))
    [5, c] if c >= 8 && c <= 15 => Some(sgr8(c - 8, bright=true))
    [5, c] if c >= 16 && c <= 231 => Some(Rgb6(Rgb6::of_code(c)))
    [5, c] if c >= 232 && c <= 255 => Some(Gray24(Gray24::of_code(c)))
    [2, r, g, b] if r >= 0 &&
      r <= 255 &&
      g >= 0 &&
      g <= 255 &&
      b >= 0 &&
      b <= 255 => Some(Rgb256(Rgb256::of_rgb(r, g, b)))
    _ => None
  }
}

///|
/// An `Attr` from a list of SGR parameter codes: known codes such as `1` for
/// bold or `38;5;196` for 256-color red foreground are parsed into specific
/// variants, and unrecognized codes are returned as `Other`.
pub fn Attr::of_codes(codes : ArrayView[Int32]) -> Attr {
  let other = () => Attr::Other(codes.to_owned())
  match codes {
    [0] => Reset
    [1] => Bold
    [2] => Faint
    [3] => Italic
    [4] => Underline
    [5] => Blink
    [6] => FastBlink
    [7] => Invert
    [8] => Hide
    [9] => Strike
    [f] if f >= 10 && f <= 19 => Font(f - 10)
    [20] => Fraktur
    [21] => DoubleUl
    [22] => NormalWeight
    [23] => NotEmphasis
    [24] => NotUnderline
    [25] => NotBlink
    [26] => VariableWidth
    [27] => NotInvert
    [28] => NotHide
    [29] => NotStrike
    [c] if c >= 30 && c <= 37 => Fg(sgr8(c - 30))
    [38, .. rest] =>
      match of_color_code(rest) {
        Some(color) => Fg(color)
        None => other()
      }
    [39] => Fg(Default)
    [c] if c >= 40 && c <= 47 => Bg(sgr8(c - 40))
    [48, .. rest] =>
      match of_color_code(rest) {
        Some(color) => Bg(color)
        None => other()
      }
    [49] => Bg(Default)
    [50] => FixedWidth
    [51] => Framed
    [52] => Encircled
    [53] => Overline
    [54] => NotFramed
    [55] => NotOverline
    [58, .. rest] =>
      match of_color_code(rest) {
        Some(color) => UlColor(color)
        None => other()
      }
    [59] => UlColor(Default)
    [i] if i >= 60 && i <= 65 => Ideogram(i - 60)
    [73] => Superscript
    [74] => Subscript
    [75] => NotScript
    [c] if c >= 90 && c <= 97 => Fg(sgr8(c - 90, bright=true))
    [c] if c >= 100 && c <= 107 => Bg(sgr8(c - 100, bright=true))
    _ => other()
  }
}

///|
fn ints_to_string(codes : ArrayView[Int32], sep~ : String = ";") -> String {
  let parts = [ for c in codes => c.to_string() ]
  parts.join(sep)
}

///|
/// A somewhat human-readable name for what the attribute is changing.
pub fn Attr::to_string_hum(self : Attr) -> String {
  match self {
    Reset => "off"
    Bold => "+bold"
    Faint => "+faint"
    Italic => "+italic"
    Underline => "+uline"
    Blink => "+blink"
    FastBlink => "+fastblink"
    Invert => "+invert"
    Hide => "+hide"
    Strike => "+strike"
    DoubleUl => "+2uline"
    Overline => "+overline"
    NormalWeight => "-weight"
    // Since `Fraktur` isn't widely supported, this is clearer.
    NotEmphasis => "-italic"
    NotUnderline => "-uline"
    NotBlink => "-blink"
    NotInvert => "-invert"
    NotHide => "-hide"
    NotStrike => "-strike"
    NotOverline => "-overline"
    Fg(c) => "fg:" + c.to_string_hum()
    Bg(c) => "bg:" + c.to_string_hum()
    UlColor(c) => "ul:" + c.to_string_hum()
    Other(codes) => "ANSI-SGR:" + ints_to_string(codes)
    Framed => "+framed"
    Encircled => "+encircled"
    Superscript => "+superscript"
    Subscript => "+subscript"
    VariableWidth => "+proportional_spacing"
    Fraktur => "+fraktur"
    NotFramed => "-framed"
    NotScript => "-script"
    FixedWidth => "-proportional_spacing"
    Font(0) => "-font"
    Font(f) => "+font:\{f}"
    Ideogram(5) => "-ideogram"
    Ideogram(i) => "+ideogram:\{i}"
  }
}

///|
/// The SGR parameters of the attribute, for example `"31"` for red text.
pub fn Attr::to_string(self : Attr) -> String {
  match self {
    Reset => "0"
    Bold => "1"
    Faint => "2"
    Italic => "3"
    Underline => "4"
    Blink => "5"
    FastBlink => "6"
    Invert => "7"
    Hide => "8"
    Strike => "9"
    DoubleUl => "21"
    Overline => "53"
    NormalWeight => "22"
    NotEmphasis => "23"
    NotUnderline => "24"
    NotBlink => "25"
    NotInvert => "27"
    NotHide => "28"
    NotStrike => "29"
    NotOverline => "55"
    Fg(c) => ints_to_string(c.to_fg_code())
    Bg(c) => ints_to_string(c.to_bg_code())
    UlColor(c) => ints_to_string(c.to_ul_code())
    Other(codes) => ints_to_string(codes)
    Framed => "51"
    Encircled => "52"
    Superscript => "73"
    Subscript => "74"
    VariableWidth => "26"
    Fraktur => "20"
    NotFramed => "54"
    NotScript => "75"
    FixedWidth => "50"
    Font(f) => (f + 10).to_string()
    Ideogram(i) => (i + 60).to_string()
  }
}
