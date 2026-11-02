///|
/// A failure to report to the user, as `failwith` is used in the OCaml version.
pub(all) suberror Failure {
  Failure(String)
}

///|
pub impl Show for Failure with output(self, logger) {
  let Failure(msg) = self
  logger.write_string(msg)
}

///|
/// The platform of the patdiff executable.
pub fn platform() -> @kernel.Platform {
  {
    mtime: file => {
      let path = match file {
        Real(real_name~, ..) => real_name
        Fake(_) => return None
      }
      try @sys.stat(path) catch {
        _ => None
      } noraise {
        stat => stat.map(stat => stat.mtime)
      }
    },
    console_width: @sys.console_width,
    am_running_test: false,
  }
}

///|
fn print_line(line : Bytes) -> Unit {
  @sys.print_stdout(line)
  @sys.print_stdout(b"\n")
}

///|
fn print_string(line : Bytes) -> Unit {
  @sys.print_stdout(line)
}

///|
/// Hunks ready to be printed.
pub fn compare_files(
  config : @kernel.Configuration,
  prev_file~ : @kernel.FileName,
  next_file~ : @kernel.FileName,
) -> @kernel.ComparisonResult raise @sys.SysError {
  let prev = @sys.read_file(prev_file.real_name())
  let next = @sys.read_file(next_file.real_name())
  @kernel.ComparisonResult::new(
    config,
    prev={ name: prev_file.display_name(), text: prev },
    next={ name: next_file.display_name(), text: next },
    compare_assuming_text=(config, prev, next) => {
      let (prev_lines, prev_newline) = @kernel.lines_of_contents(prev.text)
      let (next_lines, next_newline) = @kernel.lines_of_contents(next.text)
      @kernel.warn_if_no_trailing_newline(
        warn=file => @sys.print_stderr(b"No newline at the end of " + file + b"\n"),
        prev=(prev_newline, prev.name),
        next=(next_newline, next.name),
        warn_if_no_trailing_newline_in_both=config.warn_if_no_trailing_newline_in_both,
      )
      @kernel.compare_lines(config, prev=prev_lines, next=next_lines)
    },
  )
}

///|
/// Print hunks to stdout.
pub fn print_result(
  hunks : @kernel.ComparisonResult,
  file_names~ : (@kernel.FileName, @kernel.FileName),
  config~ : @kernel.Configuration,
) -> Unit raise @sys.SysError {
  let (prev_file, next_file) = file_names
  if hunks.has_no_diff() {
    if config.double_check &&
      @sys.read_file(prev_file.real_name()) != @sys.read_file(next_file.real_name()) {
      print_line(b"There are no differences except those filtered by your settings")
    }
  } else if !config.quiet {
    match hunks {
      BinarySame => abort("unreachable")
      BinaryDifferent(prev_is_binary~, next_is_binary~) =>
        print_line(
          @kernel.binary_different_message(
            config~,
            prev_file~,
            prev_is_binary~,
            next_file~,
            next_is_binary~,
          ),
        )
      Hunks(hunks) =>
        @kernel.print_unified(
          hunks,
          file_names~,
          output=config.output,
          rules=config.rules,
          location_style=config.location_style,
          print=print_line,
          platform=platform(),
        )
      StructuredHunks(hunks) =>
        @kernel.print_side_by_side(
          width_override?=config.width_override,
          hunks,
          file_names~,
          rules=config.rules,
          wrap_or_truncate=config.side_by_side.unwrap_or(Wrap),
          output=config.output,
          print=print_line,
          platform=platform(),
        )
    }
  }
}

///|
fn diff_files_internal(
  config : @kernel.Configuration,
  prev_file~ : @kernel.FileName,
  next_file~ : @kernel.FileName,
) -> Bool raise @sys.SysError {
  let hunks = compare_files(config, prev_file~, next_file~)
  print_result(hunks, file_names=(prev_file, next_file), config~)
  !hunks.has_no_diff()
}

///|
fn with_alt(
  config : @kernel.Configuration,
  prev~ : Bytes,
  next~ : Bytes,
) -> (@kernel.FileName, @kernel.FileName) {
  (
    Real(real_name=prev, alt_name=config.prev_alt),
    Real(real_name=next, alt_name=config.next_alt),
  )
}

///|
/// Compares and prints two files, returning whether they differ.
pub fn diff_files(
  config : @kernel.Configuration,
  prev_file~ : Bytes,
  next_file~ : Bytes,
) -> Bool raise @sys.SysError {
  let (prev_file, next_file) = with_alt(config, prev=prev_file, next=next_file)
  diff_files_internal(config, prev_file~, next_file~)
}

///|
fn has_kind(file : @kernel.FileName, kind : @sys.FileKind) -> Bool raise @sys.SysError {
  @sys.stat(file.real_name()) is Some(stat) && stat.kind == kind
}

///|
/// Sorted entries of `dir` for which `file_filter` holds. A file which
/// disappeared during listing counts as not existing. That matters when the file
/// is excluded, because we don't want to create noise for excluded files.
fn set_of_dir(
  dir : @kernel.FileName,
  file_filter : ((Bytes, @sys.Stat) -> Bool)?,
) -> Array[Bytes] raise @sys.SysError {
  let names = []
  for name in @sys.read_dir(dir.real_name()) {
    let path = @kernel.filename_concat(dir.real_name(), name)
    if @sys.stat(path) is Some(stat) &&
      (
        match file_filter {
          None => true
          Some(file_filter) => file_filter(path, stat)
        }
      ) {
      names.push(name)
    }
  }
  names.sort_by(Bytes::lexical_compare)
  names
}

///|
fn diff_dirs_internal(
  config : @kernel.Configuration,
  prev_dir~ : @kernel.FileName,
  next_dir~ : @kernel.FileName,
  file_filter~ : ((Bytes, @sys.Stat) -> Bool)?,
) -> Bool raise @sys.SysError {
  let prev_set = set_of_dir(prev_dir, file_filter)
  let next_set = set_of_dir(next_dir, file_filter)
  let prev_uniques = prev_set.filter(name => !next_set.contains(name))
  let next_uniques = next_set.filter(name => !prev_set.contains(name))
  let handle_unique = fn(
    file : Bytes,
    dir : @kernel.FileName,
    is_prev : Bool,
  ) raise @sys.SysError {
    print_string(b"Only in " + dir.display_name() + b": " + file + b"\n")
    // Diff unique files against /dev/null, if desired.
    if !config.mask_uniques {
      let file = dir.append(file)
      if has_kind(file, Regular) {
        let null = @kernel.FileName::dev_null()
        let (prev_file, next_file) = if is_prev { (file, null) } else { (null, file) }
        let _ = diff_files_internal(config, prev_file~, next_file~)
      }
    }
  }
  for file in prev_uniques {
    handle_unique(file, prev_dir, true)
  }
  for file in next_uniques {
    handle_unique(file, next_dir, false)
  }
  // Get differences.
  let mut different = false
  for file in prev_set {
    if !next_set.contains(file) {
      continue
    }
    let prev_file = prev_dir.append(file)
    let next_file = next_dir.append(file)
    let names = prev_file.display_name() + b" and " + next_file.display_name()
    if has_kind(prev_file, Regular) && has_kind(next_file, Regular) {
      let hunks = compare_files(config, prev_file~, next_file~)
      if !hunks.has_no_diff() {
        different = true
        // Print the diff if not -quiet.
        if config.quiet {
          print_string(b"Files " + names + b" differ\n")
        } else {
          print_result(hunks, file_names=(prev_file, next_file), config~)
        }
      }
    } else if has_kind(prev_file, Directory) && has_kind(next_file, Directory) {
      if config.shallow {
        print_string(b"Common subdirectories: " + names + b"\n")
      } else if diff_dirs_internal(
          config,
          prev_dir=prev_file,
          next_dir=next_file,
          file_filter~,
        ) {
        different = true
      }
    } else {
      different = true
      print_string(b"Files " + names + b" are not the same type\n")
    }
  }
  different || !prev_uniques.is_empty() || !next_uniques.is_empty()
}

///|
/// Compares and prints two directories, returning whether they differ.
/// `file_filter` is given the path and stat of each entry.
pub fn diff_dirs(
  config : @kernel.Configuration,
  prev_dir~ : Bytes,
  next_dir~ : Bytes,
  file_filter~ : ((Bytes, @sys.Stat) -> Bool)?,
) -> Bool raise {
  let (prev_dir, next_dir) = with_alt(config, prev=prev_dir, next=next_dir)
  if !has_kind(prev_dir, Directory) {
    raise Failure(
      "diff_dirs: prev_dir '\{@bstr.to_string(prev_dir.display_name())}' is not a directory",
    )
  }
  if !has_kind(next_dir, Directory) {
    raise Failure(
      "diff_dirs: next_dir '\{@bstr.to_string(next_dir.display_name())}' is not a directory",
    )
  }
  diff_dirs_internal(config, prev_dir~, next_dir~, file_filter~)
}

///|
fn load_exn(
  config_file : Bytes,
  seen~ : Array[Bytes],
) -> @kernel.Configuration raise {
  let sexp = @sexp.Sexp::parse(@sys.read_file(config_file))
  let (config, version) = @kernel.OnDisk::of_sexp_versioned(sexp)
  // Offer an upgraded copy of a configuration in an old format.
  if version is Outdated {
    let new_file = config_file + b".new"
    try {
      if @sys.stat(new_file) is None {
        @sys.write_file(new_file, config.to_sexp().to_bytes_hum())
      }
    } catch {
      _ => ()
    }
  }
  match config.config_path {
    Some(config_path) => {
      if seen.contains(config_path) {
        raise Failure("Cycle detected! file redirects to itself")
      }
      seen.push(config_path)
      load_exn(config_path, seen~)
    }
    None => config.to_configuration()
  }
}

///|
/// Loads a configuration file, reporting problems on stderr.
pub fn load_config(config_file : Bytes) -> @kernel.Configuration? {
  try load_exn(config_file, seen=[]) catch {
    err => {
      @sys.print_stderr(
        b"Note: error loading \"" +
        config_file +
        b"\": " +
        @bstr.of_string(err.to_string()) +
        b"\n",
      )
      None
    }
  } noraise {
    config => Some(config)
  }
}

///|
/// The configuration in the given file, or in `~/.patdiff` if that exists, or the
/// default one. An empty `filename` means to use the default.
pub fn get_config(filename? : Bytes) -> @kernel.Configuration {
  let file = match filename {
    Some(file) if file.is_empty() => None
    Some(file) => Some(file)
    None =>
      match @env.get_env_var("HOME") {
        None => None
        Some(home) => {
          let file = @kernel.filename_concat(
            @bstr.of_string(home),
            b".patdiff",
          )
          try @sys.stat(file) catch {
            _ => None
          } noraise {
            stat => if stat is Some(_) { Some(file) } else { None }
          }
        }
      }
  }
  file.bind(load_config).unwrap_or(@kernel.Configuration::default())
}

///|
/// Writes the default configuration file.
pub fn save_default(filename : Bytes) -> Unit raise @sys.SysError {
  @sys.write_file(filename, @kernel.default_config_string())
}
