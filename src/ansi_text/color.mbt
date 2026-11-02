///|
/// The basic colors of the SGR ranges 30-37, 40-47, 90-97 and 100-107.
#derive(Debug, Eq, Compare)
pub(all) enum Sgr8 {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
}

///|
pub fn Sgr8::of_code(code : Int32) -> Sgr8 {
  match code {
    0 => Black
    1 => Red
    2 => Green
    3 => Yellow
    4 => Blue
    5 => Magenta
    6 => Cyan
    7 => White
    _ => abort("Sgr8 code -- expected (0 <= code < 8)")
  }
}

///|
pub fn Sgr8::to_code(self : Sgr8) -> Int32 {
  match self {
    Black => 0
    Red => 1
    Green => 2
    Yellow => 3
    Blue => 4
    Magenta => 5
    Cyan => 6
    White => 7
  }
}

///|
pub fn Sgr8::to_string_hum(self : Sgr8) -> String {
  match self {
    Black => "black"
    Red => "red"
    Green => "green"
    Yellow => "yellow"
    Blue => "blue"
    Magenta => "magenta"
    Cyan => "cyan"
    White => "white"
  }
}

///|
/// The rgb subset of the codes under `38;5` and `48;5`, each channel in 0-5.
#derive(Debug, Eq, Compare)
pub(all) struct Rgb6 {
  r : Int32
  g : Int32
  b : Int32
}

///|
pub fn Rgb6::of_rgb(r : Int32, g : Int32, b : Int32) -> Rgb6 {
  let check = c => 0 <= c && c < 6
  if !(check(r) && check(g) && check(b)) {
    abort("Rgb6 (r, g, b) -- expected (0 <= r, g, b < 6)")
  }
  { r, g, b, }
}

///|
pub fn Rgb6::of_code(code : Int32) -> Rgb6 {
  if !(16 <= code && code < 232) {
    abort("Rgb6 code -- expected (16 <= code < 232)")
  }
  let rgb = code - 16
  { r: rgb / 36, g: rgb / 6 % 6, b: rgb % 6, }
}

///|
pub fn Rgb6::to_code(self : Rgb6) -> Int32 {
  16 + 36 * self.r + 6 * self.g + self.b
}

///|
/// The grayscale subset of the codes under `38;5` and `48;5`, level in 0-23.
#derive(Debug, Eq, Compare)
pub(all) struct Gray24 {
  level : Int32
}

///|
pub fn Gray24::of_level(level : Int32) -> Gray24 {
  if !(0 <= level && level < 24) {
    abort("Gray24 level -- expected (0 <= level < 24)")
  }
  { level, }
}

///|
pub fn Gray24::of_code(code : Int32) -> Gray24 {
  if !(232 <= code && code < 256) {
    abort("Gray24 code -- expected (232 <= code < 256)")
  }
  { level: code - 232, }
}

///|
pub fn Gray24::to_code(self : Gray24) -> Int32 {
  232 + self.level
}

///|
/// True color, each channel in 0-255.
#derive(Debug, Eq, Compare)
pub(all) struct Rgb256 {
  r : Int32
  g : Int32
  b : Int32
}

///|
pub fn Rgb256::of_rgb(r : Int32, g : Int32, b : Int32) -> Rgb256 {
  let check = c => 0 <= c && c < 256
  if !(check(r) && check(g) && check(b)) {
    abort("Rgb6 (r, g, b) -- expected (0 <= r, g, b < 256)")
  }
  { r, g, b, }
}

///|
#derive(Debug, Eq, Compare)
pub(all) enum Color {
  Default
  Standard(Sgr8)
  Bright(Sgr8)
  Rgb6(Rgb6)
  Gray24(Gray24)
  Rgb256(Rgb256)
}

///|
fn sgr8(code : Int32, bright~ : Bool = false) -> Color {
  if bright {
    Bright(Sgr8::of_code(code))
  } else {
    Standard(Sgr8::of_code(code))
  }
}

///|
pub fn Color::to_string_hum(self : Color) -> String {
  match self {
    Default => "default"
    Standard(c) => c.to_string_hum()
    Bright(Black) => "gray"
    Bright(c) => "bright-\{c.to_string_hum()}"
    Rgb6(c) => "rgb6-\{c.r}-\{c.g}-\{c.b}"
    Gray24(c) => "gray-\{c.level}"
    Rgb256(c) => "rgb256-\{c.r}-\{c.g}-\{c.b}"
  }
}

///|
pub fn Color::to_fg_code(self : Color) -> Array[Int32] {
  match self {
    Default => [39]
    Standard(c) => [30 + c.to_code()]
    Bright(c) => [90 + c.to_code()]
    Rgb6(c) => [38, 5, c.to_code()]
    Gray24(c) => [38, 5, c.to_code()]
    Rgb256(c) => [38, 2, c.r, c.g, c.b]
  }
}

///|
pub fn Color::to_bg_code(self : Color) -> Array[Int32] {
  match self {
    Default => [49]
    Standard(c) => [40 + c.to_code()]
    Bright(c) => [100 + c.to_code()]
    Rgb6(c) => [48, 5, c.to_code()]
    Gray24(c) => [48, 5, c.to_code()]
    Rgb256(c) => [48, 2, c.r, c.g, c.b]
  }
}

///|
pub fn Color::to_ul_code(self : Color) -> Array[Int32] {
  match self {
    Default => [59]
    Standard(c) => [58, 5, c.to_code()]
    Bright(c) => [58, 5, 8 + c.to_code()]
    Rgb6(c) => [58, 5, c.to_code()]
    Gray24(c) => [58, 5, c.to_code()]
    Rgb256(c) => [58, 2, c.r, c.g, c.b]
  }
}

///|
/// `Color::White`, `black` or `Default`, to be used as the fg color for `bg`:
/// white for dark backgrounds, black for light backgrounds, and default in
/// between.
pub fn default_text_color_for(bg : Color) -> Color {
  let white = Standard(White)
  let black = Standard(Black)
  match bg {
    Standard(White | Yellow) => black
    Standard(_) => white
    Bright(White | Yellow | Green | Cyan) => black
    Bright(Black | Red | Blue | Magenta) => white
    Rgb6({ r, g, b, }) =>
      if r + g + b < 6 {
        white
      } else if r + g + b < 12 {
        Default
      } else {
        black
      }
    Gray24({ level, }) =>
      if level < 8 {
        white
      } else if level < 16 {
        Default
      } else {
        black
      }
    Rgb256({ r, g, b, }) =>
      if r + g + b < 256 {
        white
      } else if r + g + b < 512 {
        Default
      } else {
        black
      }
    Default => Default
  }
}
