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
fn sys_error(path : Bytes, err : Error) -> SysError {
  let reason = match err {
    @os_error.OSError(code, ..) => @os_error.errno_to_string(code)
    err => err.to_string()
  }
  SysError("\{@bstr.to_string(path)}: \{reason}")
}

///|
/// File names are bytes, but the file system API takes strings, so only file
/// names in UTF-8 can be used.
fn path_string(path : Bytes) -> String raise SysError {
  @utf8.decode(path) catch {
    _ => raise SysError("\{@bstr.to_string(path)}: file name is not UTF-8")
  }
}

///|
/// The contents of a file. Works on anything readable, such as a pipe.
pub async fn read_file(path : Bytes) -> Bytes raise SysError {
  let name = path_string(path)
  @fs.read_file(name).binary() catch {
    err => raise sys_error(path, err)
  }
}

///|
pub async fn read_stdin() -> Bytes raise SysError {
  @stdio.stdin.read_all().binary() catch {
    err => raise sys_error(b"<stdin>", err)
  }
}

///|
pub async fn write_file(path : Bytes, data : Bytes) -> Unit raise SysError {
  let name = path_string(path)
  @fs.write_file(name, data, create_mode=CreateOrTruncate) catch {
    err => raise sys_error(path, err)
  }
}

///|
/// What has been printed but not yet written, in the order it was printed.
priv enum Pending {
  Stdout(Bytes)
  Stderr(Bytes)
}

///|
let pending : Array[Pending] = []

///|
/// Kept until `flush`.
pub fn print_stdout(data : Bytes) -> Unit {
  pending.push(Stdout(data))
}

///|
/// Kept until `flush`, but then written before anything for stdout, as it would
/// be if stderr were unbuffered and stdout buffered.
pub fn print_stderr(data : Bytes) -> Unit {
  pending.push(Stderr(data))
}

///|
pub async fn flush() -> Unit noraise {
  let stdout = Buffer()
  let stderr = Buffer()
  for chunk in pending {
    match chunk {
      Stdout(data) => stdout.write_bytes(data)
      Stderr(data) => stderr.write_bytes(data)
    }
  }
  pending.clear()
  // Output that can't be written, as into a closed pipe, is dropped.
  if stderr.length() > 0 {
    @stdio.stderr.write(stderr.contents()) catch {
      _ => ()
    }
  }
  if stdout.length() > 0 {
    @stdio.stdout.write(stdout.contents()) catch {
      _ => ()
    }
  }
}

///|
/// Flushes the output and ends the process.
pub async fn exit(code : Int32) -> Unit noraise {
  flush()
  process_exit(code)
}

///|
#derive(Debug, Eq)
pub(all) enum FileKind {
  Regular
  Directory
  OtherKind
}

///|
pub(all) struct Stat {
  kind : FileKind
  /// Seconds since the epoch.
  mtime : Double
}

///|
fn is_missing(err : Error) -> Bool {
  match err {
    @os_error.OSError(_) as err => err.is_ENOENT() || err.is_ENOTDIR()
    _ => false
  }
}

///|
/// Follows symlinks. `None` when the path doesn't exist.
pub async fn stat(path : Bytes) -> Stat? raise SysError {
  let name = path_string(path)
  let (kind, (seconds, nanoseconds)) = (
    @fs.kind(name, follow_symlink=true),
    @fs.mtime(name, follow_symlink=true),
  ) catch {
    err if is_missing(err) => return None
    err => raise sys_error(path, err)
  }
  let kind : FileKind = match kind {
    Regular => Regular
    Directory => Directory
    _ => OtherKind
  }
  Some({ kind, mtime: seconds.to_double() + nanoseconds.to_double() / 1.0e9, })
}

///|
/// The entries of a directory, except `.` and `..`.
pub async fn read_dir(path : Bytes) -> Array[Bytes] raise SysError {
  let name = path_string(path)
  let names = @fs.readdir(name, include_hidden=true) catch {
    err => raise sys_error(path, err)
  }
  names.map(name => @utf8.encode(name))
}

///|
/// The width of the terminal, when there is one.
pub fn console_width() -> Int32? {
  let width = terminal_width()
  if width < 0 {
    None
  } else {
    Some(width)
  }
}

///|
let temp_names : Ref[UInt32] = Ref::{ val: 0, }

///|
/// Six characters for the name of a temporary file, different on each call.
fn temp_name() -> Bytes {
  let chars = b"abcdefghijklmnopqrstuvwxyz0123456789"
  temp_names.val += 1
  // A linear congruential step from the clock and a counter.
  let mut state = @async.now().reinterpret_as_uint64().to_uint() * 2654435761U +
    temp_names.val * 40503
  Bytes::makei(6, _ => {
    state = state * 1664525U + 1013904223U
    chars[((state >> 16) % chars.length().reinterpret_as_uint()).reinterpret_as_int()]
  })
}

///|
/// Creates a new file holding `data`, with a generated name.
pub async fn temp_file(
  dir : Bytes,
  prefix : Bytes,
  suffix : Bytes,
  data : Bytes,
) -> Bytes raise SysError {
  for attempt = 0; ; attempt = attempt + 1 {
    let path = dir + b"/" + prefix + temp_name() + suffix
    let name = path_string(path)
    let file = @fs.create(name, permission=0o600) catch {
      @os_error.OSError(_) as err if attempt < 100 && err.is_EEXIST() =>
        continue
      err => raise sys_error(path, err)
    }
    defer file.close()
    file.write(data) catch {
      err => raise sys_error(path, err)
    }
    return path
  }
}

///|
/// Removes a file, ignoring any failure.
pub async fn unlink(path : Bytes) -> Unit noraise {
  let name = path_string(path) catch { _ => return }
  @fs.remove(name) catch {
    _ => ()
  }
}
