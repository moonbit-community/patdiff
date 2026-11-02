///|
/// S-expressions, as used by patdiff's configuration files. Atoms are bytes
/// because the text of a prefix or suffix can be anything.
pub(all) enum Sexp {
  Atom(Bytes)
  List(Array[Sexp])
} derive(Debug, Eq)

///|
pub(all) suberror SexpError {
  SexpError(String)
}

///|
pub impl Show for SexpError with output(self, logger) {
  let SexpError(msg) = self
  logger.write_string(msg)
}

///|
pub fn Sexp::atom(s : StringView) -> Sexp {
  Atom(@bstr.of_string(s))
}

///|
priv struct Reader {
  input : Bytes
  mut pos : Int
}

///|
fn Reader::fail(self : Reader, msg : String) -> SexpError {
  SexpError("\{msg} at offset \{self.pos}")
}

///|
fn Reader::peek(self : Reader) -> Byte? {
  self.input.get(self.pos)
}

///|
fn Reader::skip_block_comment(self : Reader) -> Unit raise SexpError {
  // At the `#|` which opens the comment. Block comments nest.
  self.pos += 2
  let mut depth = 1
  while depth > 0 {
    guard self.peek() is Some(c) else { raise self.fail("unterminated block comment") }
    let next = self.input.get(self.pos + 1)
    if c == b'|' && next is Some(b'#') {
      depth -= 1
      self.pos += 2
    } else if c == b'#' && next is Some(b'|') {
      depth += 1
      self.pos += 2
    } else {
      self.pos += 1
    }
  }
}

///|
/// Skip whitespace and all three forms of comment.
fn Reader::skip_blanks(self : Reader) -> Unit raise SexpError {
  while self.peek() is Some(c) {
    if @bstr.is_whitespace(c) {
      self.pos += 1
    } else if c == b';' {
      while self.peek() is Some(c) && c != b'\n' {
        self.pos += 1
      }
    } else if c == b'#' && self.input.get(self.pos + 1) is Some(b'|') {
      self.skip_block_comment()
    } else if c == b'#' && self.input.get(self.pos + 1) is Some(b';') {
      self.pos += 2
      let _ = self.read()
    } else {
      break
    }
  }
}

///|
fn hex_value(c : Byte) -> Int? {
  match c {
    b if b >= b'0' && b <= b'9' => Some(b.to_int() - 48)
    b if b >= b'a' && b <= b'f' => Some(b.to_int() - 87)
    b if b >= b'A' && b <= b'F' => Some(b.to_int() - 55)
    _ => None
  }
}

///|
/// Reads the body of a quoted string, with the opening `"` consumed.
fn Reader::read_string(self : Reader) -> Bytes raise SexpError {
  let buf = Buffer()
  while true {
    guard self.peek() is Some(c) else { raise self.fail("unterminated string") }
    self.pos += 1
    match c {
      b'"' => return buf.contents()
      b'\\' => {
        guard self.peek() is Some(e) else { raise self.fail("unterminated string") }
        self.pos += 1
        match e {
          b'n' => buf.write_byte(b'\n')
          b't' => buf.write_byte(b'\t')
          b'r' => buf.write_byte(b'\r')
          b'b' => buf.write_byte(8)
          b'\\' | b'"' | b'\'' | b' ' => buf.write_byte(e)
          b'\n' =>
            // A line continuation: skip the leading blanks of the next line.
            while self.peek() is Some(b' ' | b'\t') {
              self.pos += 1
            }
          b'x' => {
            let hi = self.input.get(self.pos).bind(hex_value)
            let lo = self.input.get(self.pos + 1).bind(hex_value)
            guard hi is Some(hi) && lo is Some(lo) else {
              raise self.fail("bad hex escape")
            }
            self.pos += 2
            buf.write_byte((hi * 16 + lo).to_byte())
          }
          d if d >= b'0' && d <= b'9' => {
            let mut code = d.to_int() - 48
            for _ in 0..<2 {
              guard self.peek() is Some(n) && n >= b'0' && n <= b'9' else {
                raise self.fail("bad decimal escape")
              }
              code = code * 10 + n.to_int() - 48
              self.pos += 1
            }
            buf.write_byte(code.to_byte())
          }
          other => {
            // Unknown escapes are kept literally.
            buf.write_byte(b'\\')
            buf.write_byte(other)
          }
        }
      }
      c => buf.write_byte(c)
    }
  }
  abort("unreachable")
}

///|
fn is_atom_end(c : Byte) -> Bool {
  @bstr.is_whitespace(c) || c == b'(' || c == b')' || c == b'"' || c == b';'
}

///|
fn Reader::read(self : Reader) -> Sexp raise SexpError {
  self.skip_blanks()
  match self.peek() {
    None => raise self.fail("unexpected end of input")
    Some(b')') => raise self.fail("unexpected )")
    Some(b'(') => {
      self.pos += 1
      let items = []
      while true {
        self.skip_blanks()
        match self.peek() {
          None => raise self.fail("unterminated list")
          Some(b')') => {
            self.pos += 1
            return List(items)
          }
          Some(_) => items.push(self.read())
        }
      }
      abort("unreachable")
    }
    Some(b'"') => {
      self.pos += 1
      Atom(self.read_string())
    }
    Some(_) => {
      let start = self.pos
      while self.peek() is Some(c) && !is_atom_end(c) {
        self.pos += 1
      }
      Atom(@bstr.sub(self.input, start, self.pos))
    }
  }
}

///|
/// Parses exactly one s-expression.
pub fn Sexp::parse(input : Bytes) -> Sexp raise SexpError {
  let reader = Reader::{ input, pos: 0 }
  let sexp = reader.read()
  reader.skip_blanks()
  if reader.peek() is Some(_) {
    raise reader.fail("trailing input after s-expression")
  }
  sexp
}

///|
fn must_escape(s : Bytes) -> Bool {
  if s.is_empty() {
    return true
  }
  for i, c in s {
    let next = s.get(i + 1)
    match c {
      b'(' | b')' | b'"' | b';' | b'\\' => return true
      b'|' if i == 0 && next is Some(b'#') => return true
      b'#' if next is Some(b'|' | b';') => return true
      c if c <= 0x20 || c >= 0x7F => return true
      _ => ()
    }
  }
  false
}

///|
fn escape(s : Bytes) -> Bytes {
  let buf = Buffer()
  buf.write_byte(b'"')
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
  buf.write_byte(b'"')
  buf.contents()
}

///|
fn atom_to_bytes(s : Bytes) -> Bytes {
  if must_escape(s) {
    escape(s)
  } else {
    s
  }
}

///|
/// The compact form, with only the spaces needed to tell atoms apart.
pub fn Sexp::to_bytes_mach(self : Sexp) -> Bytes {
  let buf = Buffer()
  fn write(sexp : Sexp, may_need_space : Bool) -> Bool {
    match sexp {
      Atom(s) => {
        let plain = !must_escape(s)
        if may_need_space && plain {
          buf.write_byte(b' ')
        }
        buf.write_bytes(atom_to_bytes(s))
        plain
      }
      List(items) => {
        buf.write_byte(b'(')
        let mut space = false
        for item in items {
          space = write(item, space)
        }
        buf.write_byte(b')')
        false
      }
    }
  }

  let _ = write(self, false)
  buf.contents()
}

///|
/// An indented form, for files that people read.
pub fn Sexp::to_bytes_hum(self : Sexp) -> Bytes {
  let buf = Buffer()
  fn write(sexp : Sexp, indent : Int) -> Unit {
    match sexp {
      Atom(s) => buf.write_bytes(atom_to_bytes(s))
      List(items) => {
        let flat = sexp.to_bytes_mach()
        if flat.length() + indent <= 78 {
          buf.write_bytes(flat_hum(items))
        } else {
          buf.write_byte(b'(')
          for i, item in items {
            if i > 0 {
              buf.write_byte(b'\n')
              buf.write_bytes(@bstr.spaces(indent + 1))
            }
            write(item, indent + 1)
          }
          buf.write_byte(b')')
        }
      }
    }
  }

  write(self, 0)
  buf.contents()
}

///|
fn flat_hum(items : ArrayView[Sexp]) -> Bytes {
  let parts = [
    for item in items => {
      match item {
        Atom(s) => atom_to_bytes(s)
        List(sub) => flat_hum(sub)
      }
    }
  ]
  b"(" + @bstr.concat(parts, sep=b" ") + b")"
}
