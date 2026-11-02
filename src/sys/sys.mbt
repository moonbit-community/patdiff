///|
/// A failed system call, with the message `strerror` gives for it.
pub(all) suberror SysError {
  SysError(String)
}

///|
pub impl Show for SysError with fn output(self, logger) {
  let SysError(msg) = self
  logger.write_string(msg)
}

///|
#borrow(path, err)
extern "C" fn patdiff_read_file(path : Bytes, err : FixedArray[Int32]) -> Bytes = "patdiff_read_file"

///|
#borrow(err)
extern "C" fn patdiff_read_stdin(err : FixedArray[Int32]) -> Bytes = "patdiff_read_stdin"

///|
#borrow(data)
extern "C" fn patdiff_write_fd(fd : Int32, data : Bytes) -> Int32 = "patdiff_write_fd"

///|
#borrow(path, data)
extern "C" fn patdiff_write_file(path : Bytes, data : Bytes) -> Int32 = "patdiff_write_file"

///|
#borrow(path, mtime)
extern "C" fn patdiff_stat(path : Bytes, mtime : FixedArray[Double]) -> Int32 = "patdiff_stat"

///|
#borrow(path, err)
extern "C" fn patdiff_read_dir(path : Bytes, err : FixedArray[Int32]) -> Bytes = "patdiff_read_dir"

///|
extern "C" fn patdiff_console_width() -> Int32 = "patdiff_console_width"

///|
#borrow(template, data)
extern "C" fn patdiff_temp_file(
  template : FixedArray[Byte],
  suffix_len : Int32,
  data : Bytes,
) -> Int32 = "patdiff_temp_file"

///|
#borrow(path)
extern "C" fn patdiff_unlink(path : Bytes) -> Unit = "patdiff_unlink"

///|
extern "C" fn patdiff_exit(code : Int32) -> Unit = "patdiff_exit"

///|
extern "C" fn patdiff_strerror(code : Int32) -> Bytes = "patdiff_strerror"

///|
fn sys_error(path : Bytes, code : Int32) -> SysError {
  SysError(
    "\{@bstr.to_string(path)}: \{@bstr.to_string(patdiff_strerror(code))}",
  )
}

///|
/// The contents of a file. Works on anything readable, such as a pipe.
pub fn read_file(path : Bytes) -> Bytes raise SysError {
  let err : FixedArray[Int32] = [0]
  let contents = patdiff_read_file(path, err)
  if err[0] != 0 {
    raise sys_error(path, err[0])
  }
  contents
}

///|
pub fn read_stdin() -> Bytes raise SysError {
  let err : FixedArray[Int32] = [0]
  let contents = patdiff_read_stdin(err)
  if err[0] != 0 {
    raise sys_error(b"<stdin>", err[0])
  }
  contents
}

///|
pub fn write_file(path : Bytes, data : Bytes) -> Unit raise SysError {
  let code = patdiff_write_file(path, data)
  if code != 0 {
    raise sys_error(path, code)
  }
}

///|
let stdout_buffer : Buffer = Buffer()

///|
/// Buffered until `flush_stdout`.
pub fn print_stdout(data : Bytes) -> Unit {
  stdout_buffer.write_bytes(data)
  if stdout_buffer.length() >= 65536 {
    flush_stdout()
  }
}

///|
pub fn flush_stdout() -> Unit {
  let _ = patdiff_write_fd(1, stdout_buffer.contents())
  stdout_buffer.reset()
}

///|
pub fn print_stderr(data : Bytes) -> Unit {
  let _ = patdiff_write_fd(2, data)
}

///|
/// Flushes stdout and ends the process.
pub fn exit(code : Int32) -> Unit {
  flush_stdout()
  patdiff_exit(code)
}

///|
pub(all) enum FileKind {
  Regular
  Directory
  OtherKind
} derive(Debug, Eq)

///|
pub(all) struct Stat {
  kind : FileKind
  /// Seconds since the epoch.
  mtime : Double
}

///|
/// Follows symlinks. `None` when the path doesn't exist.
pub fn stat(path : Bytes) -> Stat? raise SysError {
  let mtime : FixedArray[Double] = [0.0]
  let code = patdiff_stat(path, mtime)
  if code < 0 {
    raise sys_error(path, -code)
  }
  match code {
    0 => None
    1 => Some({ kind: Regular, mtime: mtime[0], })
    2 => Some({ kind: Directory, mtime: mtime[0], })
    _ => Some({ kind: OtherKind, mtime: mtime[0], })
  }
}

///|
/// The entries of a directory, except `.` and `..`.
pub fn read_dir(path : Bytes) -> Array[Bytes] raise SysError {
  let err : FixedArray[Int32] = [0]
  let listing = patdiff_read_dir(path, err)
  if err[0] != 0 {
    raise sys_error(path, err[0])
  }
  let names = @bstr.split_on(listing, 0)
  // Every name ends with a NUL, so what follows the last one is empty.
  let _ = names.pop()
  names
}

///|
/// The width of the terminal, when there is one.
pub fn console_width() -> Int32? {
  let width = patdiff_console_width()
  if width < 0 {
    None
  } else {
    Some(width)
  }
}

///|
/// Creates a new file holding `data`, with a generated name.
pub fn temp_file(
  dir : Bytes,
  prefix : Bytes,
  suffix : Bytes,
  data : Bytes,
) -> Bytes raise SysError {
  let path = dir + b"/" + prefix + b"XXXXXX" + suffix + b"\x00"
  let template = path.to_fixedarray()
  let code = patdiff_temp_file(template, suffix.length(), data)
  if code != 0 {
    raise sys_error(path[:path.length() - 1].to_owned(), code)
  }
  Bytes::from_array(template[:template.length() - 1])
}

///|
/// Removes a file, ignoring any failure.
pub fn unlink(path : Bytes) -> Unit {
  patdiff_unlink(path)
}
