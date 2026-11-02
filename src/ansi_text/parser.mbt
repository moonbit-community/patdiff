// This parser implements a subset of ECMA-48 (also known as ANSI X3.64 or
// ISO/IEC 6429). Key sections referenced:
// - Section 5.4: Control sequences (CSI)
// - Section 8.3.143: ST (String Terminator)
// - Section 8.3.89: OSC (Operating System Command)
//
// For OSC 8 hyperlinks specifically, see
// https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
//
// When CSI or OSC parsing fails, we emit `Unknown(Fe('[' or ']'))` followed by
// whatever was scanned as text, so nothing is lost.

///|
const ESC : Byte = 0x1B

///|
const BEL : Byte = 0x07

///|
fn is_between(c : Byte, lo : Byte, hi : Byte) -> Bool {
  lo <= c && c <= hi
}

///|
/// Parameter bytes (ECMA-48 section 5.4.2a) include digits and semicolons.
fn is_csi_param_byte(c : Byte) -> Bool {
  is_between(c, 0x30, 0x3F)
}

///|
/// Intermediate bytes (ECMA-48 section 5.4.2b) are rarely used in practice, and
/// ignored here.
fn is_csi_intermediate_byte(c : Byte) -> Bool {
  is_between(c, 0x20, 0x2F)
}

///|
/// Final bytes per ECMA-48 section 5.4.2c.
fn is_csi_final_byte(c : Byte) -> Bool {
  is_between(c, 0x40, 0x7E)
}

///|
/// Final bytes that correspond to `Control` sequences we understand.
fn is_control_final_byte(c : Byte) -> Bool {
  match c {
    b'A'
    | b'B'
    | b'C'
    | b'D'
    | b'E'
    | b'F'
    | b'G'
    | b'H'
    | b'J'
    | b'K'
    | b'S'
    | b'T' => true
    _ => false
  }
}

///|
fn parse_int_opt(s : Bytes) -> Int32? {
  if s.is_empty() || !@bstr.for_all(s, c => is_between(c, b'0', b'9')) {
    return None
  }
  Some(@string.parse_int(@bstr.to_string(s))) catch {
    _ => None
  }
}

///|
fn parse_params(params : Bytes) -> Array[Int32?] {
  if params.is_empty() {
    []
  } else {
    [
      for s in @bstr.split_on(params, b';') => parse_int_opt(s)
    ]
  }
}

///|
fn of_csi(private_prefix : Byte?, params : Bytes, terminal~ : Byte) -> Element {
  let unknown = () => {
    Element::Unknown(UnknownEsc::of_csi(private_prefix, params, terminal~))
  }
  let terminal_char = terminal.to_int().unsafe_to_char()
  match private_prefix {
    Some(b'?') =>
      match
        PrivateMode::of_csi_params(parse_params(params), terminal=terminal_char) {
        Some(pm) => PrivateMode(pm)
        None => unknown()
      }
    Some(_) => unknown()
    None =>
      match terminal {
        b'm' => Style(style_of_sgr_params(parse_params(params)))
        b'n' =>
          match Dsr::of_params(parse_params(params)) {
            Some(dsr) => Dsr(dsr)
            None => unknown()
          }
        c if is_control_final_byte(c) =>
          Control(
            Control::of_csi_params(parse_params(params), terminal=terminal_char),
          )
        _ => unknown()
      }
  }
}

///|
fn text_of_trailing(str : Bytes) -> Array[Element] {
  if str.is_empty() {
    []
  } else {
    [Text(Text::of_bytes(str))]
  }
}

///|
/// A cursor over the input.
priv struct Parser {
  input : Bytes
  mut pos : Int32
  out : Array[Element]
}

///|
fn Parser::peek(self : Parser) -> Byte? {
  self.input.get(self.pos)
}

///|
fn Parser::take_while(self : Parser, f : (Byte) -> Bool) -> Bytes {
  let start = self.pos
  while self.pos < self.input.length() && f(self.input[self.pos]) {
    self.pos += 1
  }
  @bstr.sub(self.input, start, self.pos)
}

///|
fn Parser::emit_all(self : Parser, elements : Array[Element]) -> Unit {
  self.out.push_iter(elements.iter())
}

///|
/// ECMA-48 section 5.4: `CSI P...P I...I F`, where P are parameter bytes, I are
/// intermediate bytes and F is the final byte. Starts after the `[`.
fn Parser::csi(self : Parser) -> Unit {
  // DEC private mode sequences use '?' as a prefix to the parameters.
  let private_prefix = if self.peek() is Some(b'?') {
    self.pos += 1
    Some(b'?')
  } else {
    None
  }
  let params = self.take_while(is_csi_param_byte)
  let intermediate = self.take_while(is_csi_intermediate_byte)
  match self.peek() {
    Some(terminal) if is_csi_final_byte(terminal) => {
      self.pos += 1
      self.out.push(of_csi(private_prefix, params, terminal~))
    }
    _ => {
      // Malformed CSI: emit Fe '[' followed by prefix, params, and intermediate
      // as text, so nothing is lost.
      let params = match private_prefix {
        Some(c) => Bytes::make(1, c) + params
        None => params
      }
      self.out.push(Unknown(Fe(b'[')))
      self.emit_all(text_of_trailing(params + intermediate))
    }
  }
}

///|
/// OSC 8 is the hyperlink extension (not part of ECMA-48), with the format
/// `OSC 8 ; params ; uri ST`.
fn osc_hyperlink_of_payload(payload : Bytes) -> Hyperlink? {
  guard payload.strip_prefix(b"8;") is Some(rest) else { return None }
  match @bstr.lsplit2(rest.to_owned(), b';') {
    None => None
    // Empty URI means end of hyperlink.
    Some((_, uri)) if uri.is_empty() => Some(End)
    Some((_, uri)) => Some(Start(uri))
  }
}

///|
fn element_of_osc(payload : Bytes) -> Element {
  match osc_hyperlink_of_payload(payload) {
    Some(hyperlink) => Hyperlink(hyperlink)
    None => Osc(Osc::of_payload(payload))
  }
}

///|
/// ECMA-48 section 8.3.89: `OSC <payload> ST`, where ST is `ESC \` or BEL.
/// While ECMA-48 only defines `ESC \`, BEL is widely accepted as an alternative
/// in real-world terminals. Starts after the `]`.
fn Parser::osc(self : Parser) -> Unit {
  let payload = self.take_while(c => c != ESC && c != BEL)
  let unterminated = () => {
    self.out.push(Unknown(Fe(b']')))
    self.emit_all(text_of_trailing(payload))
  }
  match self.peek() {
    Some(BEL) => {
      self.pos += 1
      self.out.push(element_of_osc(payload))
    }
    // Must be ESC; check if it's the two-byte ST. If not, don't consume it.
    Some(_) =>
      if self.input.get(self.pos + 1) is Some(b'\\') {
        self.pos += 2
        self.out.push(element_of_osc(payload))
      } else {
        unterminated()
      }
    None => unterminated()
  }
}

///|
/// Handles ESC followed by any byte that isn't `[` (CSI) or `]` (OSC):
/// - Fe sequences (0x40-0x5F, excluding `[` and `]`)
/// - Fp sequences (0x60-0x7E): private use, such as ESC c (reset)
/// - nF sequences (0x20-0x2F intermediate bytes + 0x30-0x7E final byte)
/// - Incomplete: ESC at end of input, ESC + ESC, or ESC + invalid byte
fn Parser::other_escape(self : Parser, escaped : Byte) -> Unit {
  if escaped == ESC {
    self.out.push(Unknown(Incomplete))
  } else if is_between(escaped, 0x40, 0x5F) {
    self.pos += 1
    self.out.push(Unknown(Fe(escaped)))
  } else if is_between(escaped, 0x60, 0x7E) {
    self.pos += 1
    self.out.push(Unknown(Fp(escaped)))
  } else if is_between(escaped, 0x20, 0x2F) {
    let intermediates = self.take_while(is_csi_intermediate_byte)
    match self.peek() {
      Some(final_byte) if is_between(final_byte, 0x30, 0x7E) => {
        self.pos += 1
        self.out.push(Unknown(Nf(intermediates + Bytes::make(1, final_byte))))
      }
      _ => {
        // Truncated nF: emit Incomplete, leave intermediates as text.
        self.out.push(Unknown(Incomplete))
        self.emit_all(text_of_trailing(intermediates))
      }
    }
  } else {
    // Invalid byte: emit Incomplete, leave the byte for text parsing.
    self.out.push(Unknown(Incomplete))
  }
}

///|
/// Parse a string (possibly) containing ANSI escape sequences into structured
/// form. Malformed sequences are captured as `Unknown`; the result can always be
/// converted back to a semantically equivalent string via `to_bytes`.
pub fn parse(input : Bytes) -> AnsiText {
  let parser = Parser::{ input, pos: 0, out: [], }
  while parser.peek() is Some(c) {
    if c == ESC {
      parser.pos += 1
      match parser.peek() {
        Some(b'[') => {
          parser.pos += 1
          parser.csi()
        }
        Some(b']') => {
          parser.pos += 1
          parser.osc()
        }
        Some(escaped) => parser.other_escape(escaped)
        None => parser.out.push(Unknown(Incomplete))
      }
    } else {
      parser.out.push(Text(Text::of_bytes(parser.take_while(b => b != ESC))))
    }
  }
  parser.out
}
