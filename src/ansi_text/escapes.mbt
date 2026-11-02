///|
fn esc_string(body : String) -> Bytes {
  @bstr.of_string("\u{1b}" + body)
}

///|
fn opt_int(n : Int32?) -> String {
  match n {
    Some(n) => n.to_string()
    None => ""
  }
}

///|
fn params_to_string(params : ArrayView[Int32?]) -> String {
  let parts = [ for p in params => opt_int(p) ]
  parts.join(";")
}

///|
#derive(Debug, Eq)
pub(all) enum ClearLine {
  ToLineEnd
  ToLineStart
  WholeLine
}

///|
#derive(Debug, Eq)
pub(all) enum ClearScreen {
  ToScreenEnd
  ToScreenStart
  WholeScreen
  ScreenAndScrollback
}

///|
/// The Control Sequence Introducer commands recognized by this library.
#derive(Debug, Eq)
pub(all) enum Control {
  CursorUp(Int32?)
  CursorDown(Int32?)
  CursorForward(Int32?)
  CursorBackward(Int32?)
  CursorNextLine(Int32?)
  CursorPrevLine(Int32?)
  CursorToCol(Int32?)
  CursorToPos(Int32?, Int32?)
  EraseDisplay(ClearScreen?)
  EraseLine(ClearLine?)
  ScrollUp(Int32?)
  ScrollDown(Int32?)
  Unknown(params~ : Array[Int32?], terminal~ : Char)
}

///|
fn Control::of_csi_params(params : Array[Int32?], terminal~ : Char) -> Control {
  let param = i => params.get(i).unwrap_or(None)
  let n = param(0)
  let unknown = () => Control::Unknown(params~, terminal~)
  match terminal {
    'A' => CursorUp(n)
    'B' => CursorDown(n)
    'C' => CursorForward(n)
    'D' => CursorBackward(n)
    'E' => CursorNextLine(n)
    'F' => CursorPrevLine(n)
    'G' => CursorToCol(n)
    'H' => CursorToPos(n, param(1))
    'J' =>
      match n {
        None => EraseDisplay(None)
        Some(0) => EraseDisplay(Some(ToScreenEnd))
        Some(1) => EraseDisplay(Some(ToScreenStart))
        Some(2) => EraseDisplay(Some(WholeScreen))
        Some(3) => EraseDisplay(Some(ScreenAndScrollback))
        Some(_) => unknown()
      }
    'K' =>
      match n {
        None => EraseLine(None)
        Some(0) => EraseLine(Some(ToLineEnd))
        Some(1) => EraseLine(Some(ToLineStart))
        Some(2) => EraseLine(Some(WholeLine))
        Some(_) => unknown()
      }
    'S' => ScrollUp(n)
    'T' => ScrollDown(n)
    _ => unknown()
  }
}

///|
pub fn Control::to_bytes(self : Control) -> Bytes {
  let csi = fn(n : Int32?, terminal : String) {
    esc_string("[\{opt_int(n)}\{terminal}")
  }
  match self {
    CursorUp(n) => csi(n, "A")
    CursorDown(n) => csi(n, "B")
    CursorForward(n) => csi(n, "C")
    CursorBackward(n) => csi(n, "D")
    CursorNextLine(n) => csi(n, "E")
    CursorPrevLine(n) => csi(n, "F")
    CursorToCol(n) => csi(n, "G")
    CursorToPos(None, None) => esc_string("[H")
    CursorToPos(Some(n), None) => esc_string("[\{n}H")
    CursorToPos(None, Some(m)) => esc_string("[;\{m}H")
    CursorToPos(Some(n), Some(m)) => esc_string("[\{n};\{m}H")
    EraseDisplay(None) => esc_string("[J")
    EraseDisplay(Some(ToScreenEnd)) => esc_string("[0J")
    EraseDisplay(Some(ToScreenStart)) => esc_string("[1J")
    EraseDisplay(Some(WholeScreen)) => esc_string("[2J")
    EraseDisplay(Some(ScreenAndScrollback)) => esc_string("[3J")
    EraseLine(None) => esc_string("[K")
    EraseLine(Some(ToLineEnd)) => esc_string("[0K")
    EraseLine(Some(ToLineStart)) => esc_string("[1K")
    EraseLine(Some(WholeLine)) => esc_string("[2K")
    ScrollUp(n) => csi(n, "S")
    ScrollDown(n) => csi(n, "T")
    Unknown(params~, terminal~) =>
      esc_string("[\{params_to_string(params)}\{terminal}")
  }
}

///|
pub fn Control::to_string_hum(self : Control) -> String {
  let named = fn(name : String, n : Int32?) {
    match n {
      None => "(\{name})"
      Some(n) => "(\{name}:\{n})"
    }
  }
  match self {
    CursorUp(n) => named("CursorUp", n)
    CursorDown(n) => named("CursorDown", n)
    CursorForward(n) => named("CursorForward", n)
    CursorBackward(n) => named("CursorBackward", n)
    CursorNextLine(n) => named("CursorNextLine", n)
    CursorPrevLine(n) => named("CursorPrevLine", n)
    CursorToCol(None) => "(CursorToCol:1)"
    CursorToCol(Some(n)) => "(CursorToCol:\{n})"
    CursorToPos(None, None) => "(CursorToPos:1;1)"
    CursorToPos(Some(n), None) => "(CursorToPos:\{n};1)"
    CursorToPos(None, Some(m)) => "(CursorToPos:1;\{m})"
    CursorToPos(Some(n), Some(m)) => "(CursorToPos:\{n};\{m})"
    EraseDisplay(None) | EraseDisplay(Some(ToScreenEnd)) =>
      "(EraseScreen:ToEnd)"
    EraseDisplay(Some(ToScreenStart)) => "(EraseScreen:ToStart)"
    EraseDisplay(Some(WholeScreen)) => "(EraseScreen)"
    EraseDisplay(Some(ScreenAndScrollback)) => "(EraseScreen:AndScrollback)"
    EraseLine(None) | EraseLine(Some(ToLineEnd)) => "(EraseLine:ToEnd)"
    EraseLine(Some(ToLineStart)) => "(EraseLine:ToStart)"
    EraseLine(Some(WholeLine)) => "(EraseLine)"
    ScrollUp(n) => named("ScrollUp", n)
    ScrollDown(n) => named("ScrollDown", n)
    Unknown(params~, terminal~) =>
      "(ANSI-CSI:\{params_to_string(params)}\{terminal})"
  }
}

///|
/// An OSC 8 terminal hyperlink marker.
#derive(Debug, Eq)
pub(all) enum Hyperlink {
  Start(Bytes)
  End
}

///|
pub fn Hyperlink::to_bytes(self : Hyperlink) -> Bytes {
  match self {
    End => b"\x1b]8;;\x1b\\"
    Start(url) => b"\x1b]8;;" + url + b"\x1b\\"
  }
}

///|
pub fn Hyperlink::to_bytes_hum(self : Hyperlink) -> Bytes {
  match self {
    Start(url) => b"(HREF:" + url + b")"
    End => b"(/HREF)"
  }
}

///|
#derive(Debug, Eq)
pub(all) enum PrivateModeAction {
  Set
  Reset
}

///|
/// A DEC private mode sequence such as `ESC [ ? 25 h`.
#derive(Debug, Eq)
pub(all) struct PrivateMode {
  modes : Array[Int32]
  action : PrivateModeAction
}

///|
fn PrivateMode::of_csi_params(
  params : ArrayView[Int32?],
  terminal~ : Char,
) -> PrivateMode? {
  let action = match terminal {
    'h' => Some(PrivateModeAction::Set)
    'l' => Some(Reset)
    _ => None
  }
  let modes = []
  for param in params {
    if param is Some(mode) {
      modes.push(mode)
    }
  }
  match action {
    Some(action) if !modes.is_empty() => Some({ modes, action, })
    _ => None
  }
}

///|
pub fn PrivateMode::is_alternate_screen(self : PrivateMode) -> Bool {
  self.modes.contains(47) || self.modes.contains(1049)
}

///|
pub fn PrivateMode::to_bytes(self : PrivateMode) -> Bytes {
  let action = match self.action {
    Set => "h"
    Reset => "l"
  }
  esc_string("[?\{ints_to_string(self.modes)}\{action}")
}

///|
pub fn PrivateMode::to_string_hum(self : PrivateMode) -> String {
  let action = match self.action {
    Set => "set"
    Reset => "reset"
  }
  "(PrivateMode:\{action}:\{ints_to_string(self.modes)})"
}

///|
#derive(Debug, Eq)
pub(all) enum OscCommand {
  SetTitle(Bytes)
  SetIconName(Bytes)
  SetWorkingDirectory(Bytes)
  Other(Bytes)
}

///|
/// An Operating System Command other than a hyperlink.
#derive(Debug, Eq)
pub(all) struct Osc {
  command : OscCommand
}

///|
fn Osc::of_payload(payload : Bytes) -> Osc {
  // Parse the OSC command number and payload.
  let command = match @bstr.lsplit2(payload, b';') {
    Some((number, title)) if number == b"0" || number == b"2" => SetTitle(title)
    Some((number, name)) if number == b"1" => SetIconName(name)
    Some((number, uri)) if number == b"7" => SetWorkingDirectory(uri)
    _ => Other(payload)
  }
  { command, }
}

///|
pub fn Osc::to_bytes(self : Osc) -> Bytes {
  let payload = match self.command {
    SetTitle(title) => b"0;" + title
    SetIconName(name) => b"1;" + name
    SetWorkingDirectory(uri) => b"7;" + uri
    Other(payload) => payload
  }
  // Use ESC \ as the terminator for consistency.
  b"\x1b]" + payload + b"\x1b\\"
}

///|
pub fn Osc::to_bytes_hum(self : Osc) -> Bytes {
  match self.command {
    SetTitle(title) => b"(OSC:title:" + title + b")"
    SetIconName(name) => b"(OSC:icon:" + name + b")"
    SetWorkingDirectory(uri) => b"(OSC:cwd:" + uri + b")"
    Other(payload) => b"(OSC:" + payload + b")"
  }
}

///|
#derive(Debug, Eq)
pub(all) enum DsrQuery {
  DeviceStatus
  CursorPosition
  Other(Int32)
}

///|
/// A Device Status Report request.
#derive(Debug, Eq)
pub(all) struct Dsr {
  query : DsrQuery
}

///|
fn Dsr::of_params(params : ArrayView[Int32?]) -> Dsr? {
  match params {
    [Some(5)] => Some({ query: DeviceStatus, })
    [Some(6)] => Some({ query: CursorPosition, })
    [Some(n)] => Some({ query: Other(n), })
    _ => None
  }
}

///|
pub fn Dsr::to_bytes(self : Dsr) -> Bytes {
  let param = match self.query {
    DeviceStatus => 5
    CursorPosition => 6
    Other(n) => n
  }
  esc_string("[\{param}n")
}

///|
pub fn Dsr::to_string_hum(self : Dsr) -> String {
  match self.query {
    DeviceStatus => "(DSR:device-status)"
    CursorPosition => "(DSR:cursor-position)"
    Other(n) => "(DSR:\{n})"
  }
}

///|
/// An escape sequence that isn't otherwise understood. `Csi` holds everything
/// after `ESC [`.
#derive(Debug, Eq)
pub(all) enum UnknownEsc {
  Csi(Bytes)
  Fe(Byte)
  Fp(Byte)
  Nf(Bytes)
  Incomplete
}

///|
fn UnknownEsc::of_csi(
  private_prefix : Byte?,
  params : Bytes,
  terminal~ : Byte,
) -> UnknownEsc {
  let tail = Bytes::make(1, terminal)
  match private_prefix {
    None => Csi(params + tail)
    Some(prefix) => Csi(Bytes::make(1, prefix) + params + tail)
  }
}

///|
pub fn UnknownEsc::to_bytes(self : UnknownEsc) -> Bytes {
  match self {
    Csi(params) => b"\x1b[" + params
    Fe(c) | Fp(c) => b"\x1b" + Bytes::make(1, c)
    Nf(s) => b"\x1b" + s
    Incomplete => b"\x1b"
  }
}

///|
/// `Char.escaped`/`String.escaped` from OCaml.
fn escaped(s : BytesView) -> Bytes {
  let buf = Buffer()
  for c in s {
    match c {
      b'"' => buf.write_bytes(b"\\\"")
      b'\\' => buf.write_bytes(b"\\\\")
      b'\n' => buf.write_bytes(b"\\n")
      b'\t' => buf.write_bytes(b"\\t")
      b'\r' => buf.write_bytes(b"\\r")
      8 => buf.write_bytes(b"\\b")
      c if c >= 0x20 && c < 0x7F => buf.write_byte(c)
      c => {
        let code = c.to_int()
        buf.write_bytes(
          @bstr.of_string("\\\{code / 100}\{code / 10 % 10}\{code % 10}"),
        )
      }
    }
  }
  buf.contents()
}

///|
pub fn UnknownEsc::to_bytes_hum(self : UnknownEsc) -> Bytes {
  match self {
    Csi(params) => b"(ANSI-CSI:" + params + b")"
    Fe(c) => b"(ANSI-Fe:" + escaped(Bytes::make(1, c)) + b")"
    Fp(c) => b"(ANSI-Fp:" + escaped(Bytes::make(1, c)) + b")"
    Nf(s) => b"(ANSI-nF:" + escaped(s) + b")"
    Incomplete => b"(ESC)"
  }
}
