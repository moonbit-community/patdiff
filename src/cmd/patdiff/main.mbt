///|
const VERSION = "0.1.0"

///|
const SUMMARY =
  #|Compare two files (or process a diff read in on stdin) using the
  #|patience diff algorithm.
  #|
  #|If you don't supply any arguments to patdiff, it will read diff-like
  #|text from stdin and color it in the normal patdiff way.
  #|
  #|The file ~/.patdiff is used as a config file if it exists.  You can
  #|write a sample config with the -make-config flag.

///|
priv enum FlagKind {
  NoArg
  WithArg(String)
}

///|
priv struct Flag {
  name : String
  aliases : Array[String]
  kind : FlagKind
  doc : String
}

///|
fn no_arg(name : String, doc : String) -> Flag {
  { name, aliases: [], kind: NoArg, doc, }
}

///|
fn with_arg(
  name : String,
  arg : String,
  doc : String,
  aliases~ : Array[String] = [],
) -> Flag {
  { name, aliases, kind: WithArg(arg), doc, }
}

///|
fn flags() -> Array[Flag] {
  let styles = @kernel.LocationStyle::all().map(s => s.to_string()).join("|")
  [
    with_arg("alt-next", "NAME", "Mask next filename with NAME", aliases=[
      "alt-new",
    ]),
    with_arg("alt-prev", "NAME", "Mask prev filename with NAME", aliases=[
      "alt-old",
    ]),
    no_arg("ansi", "Output in ASCII with ANSI escape codes"),
    no_arg(
      "ascii", "Output in ASCII with no ANSI escape codes (implies unrefined diff)",
    ),
    with_arg(
      "context", "NUM", "Show lines of unchanged context before and after changes",
    ),
    no_arg("default", "Use the default configuration instead of ~/.patdiff"),
    no_arg(
      "dont-produce-unified-lines", "Don't produce unified lines (this makes the diff unambiguous even if color is stripped)",
    ),
    no_arg("double-check", "If files seem identical, double check with cmp"),
    with_arg(
      "exclude", "REGEXP", "exclude files matching this pattern when comparing two directories (overrides include patterns)",
    ),
    with_arg(
      "file", "FILE", "Use FILE as configuration file instead of ~/.patdiff",
    ),
    no_arg(
      "find-moves", "Try to find and render moves. If -dont-produce-unified-lines is set moves will not be found.",
    ),
    with_arg(
      "float-tolerance", "PERCENT", "Consider strings equal if only difference is floats changing within PERCENT",
    ),
    no_arg(
      "html", "Output in HTML format instead of default (ASCII with ANSI escape codes)",
    ),
    with_arg(
      "include", "REGEXP", "include files matching this pattern when comparing two directories",
    ),
    no_arg("keep-whitespace", "Consider whitespace when comparing lines"),
    with_arg(
      "line-big-enough", "NUM", "Limit line-level semantic cleanup to the matches of length less than NUM lines",
    ),
    with_arg(
      "location-style",
      "<\{styles}>",
      "how to format location information in hunk headers",
    ),
    with_arg("make-config", "FILE", "Write default configuration file"),
    no_arg(
      "mask-uniques", "When comparing directories, don't compare against /dev/null",
    ),
    no_arg(
      "no-interleave", "Don't attempt to split up large hunks near equalities",
    ),
    no_arg(
      "no-semantic-cleanup", "Don't do any semantic cleanup; let small, spurious matches survive",
    ),
    no_arg("quiet", "Report only whether files differ, not the details"),
    no_arg("reverse", "produce a diff that undoes the changes"),
    no_arg("shallow", "When comparing directories, don't recurse into subdirs"),
    with_arg("side-by-side", "<wrap|truncate>", "Render a diff side by side"),
    no_arg("split-long-lines", "Split long lines into multiple displayed lines"),
    no_arg(
      "text", "Treat all files as text (i.e. display diffs of binary file contents)",
    ),
    no_arg("unrefined", "Don't highlight word differences between lines"),
    with_arg(
      "warn-if-no-trailing-newline-in-both", "BOOL", "warn when neither file ends in a newline, even though this does not constitute a diff (default: read from config, or true)",
    ),
    with_arg(
      "width", "INT", "number of columns to use for side by side diff. If not provided defaults to current terminal width.",
    ),
    with_arg(
      "word-big-enough", "NUM", "Limit word-level semantic cleanup to the matches of length less than NUM words",
    ),
    no_arg("help", "print this help text and exit"),
    no_arg("version", "print the version of this build and exit"),
  ]
}

///|
fn usage() -> String {
  let lines = [
    "File Diff using the Patience Diff algorithm\n\n  patdiff [FILE1 FILE2]\n\n\{SUMMARY}\n\n=== flags ===\n",
  ]
  for flag in flags() {
    let head = match flag.kind {
      NoArg => "  -\{flag.name}"
      WithArg(arg) => "  [-\{flag.name} \{arg}]"
    }
    let aliases = flag.aliases.map(a => "-\{a}").join(", ")
    let doc = if aliases.is_empty() {
      flag.doc
    } else {
      "\{flag.doc} (alias: \{aliases})"
    }
    lines.push("\{head}\n      \{doc}")
  }
  lines.join("\n") + "\n"
}

///|
/// A bad command line, reported the way Core's `Command` does it.
priv suberror UsageError {
  UsageError(String)
}

///|
/// Resolves a flag as `Command` does: `_` and `-` are interchangeable, and any
/// unique prefix of a name will do.
fn find_flag(all : Array[Flag], arg : String) -> Flag raise UsageError {
  let wanted = arg.replace_all(old="_", new="-")
  let candidates = []
  for flag in all {
    if flag.name == wanted || flag.aliases.contains(wanted) {
      return flag
    }
    let names = [flag.name]
    names.push_iter(flag.aliases.iter())
    if names.iter().any(name => name.has_prefix(wanted)) {
      candidates.push(flag)
    }
  }
  match candidates {
    [flag] => flag
    [] => raise UsageError("unknown flag -\{arg}")
    _ => {
      let names = candidates.map(flag => "-\{flag.name}").join(", ")
      raise UsageError("flag -\{arg} is an ambiguous prefix: \{names}")
    }
  }
}

///|
priv struct ParsedArgs {
  /// Value of each flag given, in order, under its canonical name.
  values : Map[String, Array[String]]
  anons : Array[String]
}

///|
fn parse_args(args : ArrayView[String]) -> ParsedArgs raise UsageError {
  let all = flags()
  let values : Map[String, Array[String]] = Map([])
  let anons = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if arg == "--" {
      anons.push_iter(args[i:].iter())
      break
    }
    if arg == "-" || !arg.has_prefix("-") {
      anons.push(arg)
      continue
    }
    let name = arg.trim_start(chars="-").to_owned()
    let flag = if name == "?" {
      find_flag(all, "help")
    } else {
      find_flag(all, name)
    }
    match flag.kind {
      NoArg => values.get_or_init(flag.name, () => []).push("")
      WithArg(_) => {
        if i >= args.length() {
          raise UsageError("missing argument for flag -\{flag.name}")
        }
        values.get_or_init(flag.name, () => []).push(args[i])
        i += 1
      }
    }
  }
  { values, anons, }
}

///|
fn ParsedArgs::has(self : ParsedArgs, name : String) -> Bool {
  self.values.contains(name)
}

///|
/// The value of a flag which may be given once.
fn ParsedArgs::get(
  self : ParsedArgs,
  name : String,
) -> String? raise UsageError {
  match self.values.get(name) {
    None => None
    Some([value]) => Some(value)
    Some(_) => raise UsageError("flag -\{name} passed more than once")
  }
}

///|
fn ParsedArgs::get_int(
  self : ParsedArgs,
  name : String,
) -> Int32? raise UsageError {
  match self.get(name) {
    None => None
    Some(value) =>
      Some(@string.parse_int(value)) catch {
        _ => raise UsageError("failed to parse -\{name} value \"\{value}\"")
      }
  }
}

///|
/// `Percent.of_string` from Core: a number followed by `x`, `%` or `bp`.
fn parse_percent(value : String) -> Double? {
  let parse = (number : StringView, scale : Double) => {
    Some(@string.parse_double(number) * scale) catch {
      _ => None
    }
  }
  if value.strip_suffix("bp") is Some(number) {
    parse(number, 0.0001)
  } else if value.strip_suffix("%") is Some(number) {
    parse(number, 0.01)
  } else if value.strip_suffix("x") is Some(number) {
    parse(number, 1.0)
  } else {
    None
  }
}

///|
/// Splits diff-like text from stdin into the two files it describes.
fn files_from_stdin() -> (Bytes, Bytes) raise {
  let prev = Buffer()
  let next = Buffer()
  let add_prefixes = [b"+", b">"]
  let remove_prefixes = [b"-", b"<"]
  let process = (
    line : Bytes,
    skip : Array[Bytes],
    blank : Array[Bytes],
    out : Buffer,
  ) => {
    if !skip.iter().any(prefix => line.has_prefix(prefix)) {
      match blank.search_by(prefix => line.has_prefix(prefix)) {
        None => out.write_bytes(line)
        Some(_) => {
          out.write_byte(b' ')
          out.write_bytes(line[1:])
        }
      }
      out.write_byte(b'\n')
    }
  }
  for line in @bstr.split_lines(@sys.read_stdin()) {
    process(line, add_prefixes, remove_prefixes, prev)
    process(line, remove_prefixes, add_prefixes, next)
  }
  let dir = @bstr.of_string(@env.get_env_var("TMPDIR").unwrap_or("/tmp"))
  let dir = if dir.has_suffix(b"/") {
    dir[:dir.length() - 1].to_owned()
  } else {
    dir
  }
  (
    @sys.temp_file(dir, b"patdiff_prev_", b".txt", prev.contents()),
    @sys.temp_file(dir, b"patdiff_next_", b".txt", next.contents()),
  )
}

///|
fn output_flag(args : ParsedArgs) -> @kernel.Output? raise UsageError {
  let chosen = ["html", "ascii", "ansi"].filter(name => args.has(name))
  match chosen {
    [] => None
    ["html"] => Some(Html)
    ["ascii"] => Some(Ascii)
    ["ansi"] => Some(Ansi)
    _ => {
      let names = chosen.map(name => "-\{name}").join(", ")
      raise UsageError("Cannot pass more than one of these: \{names}")
    }
  }
}

///|
fn make_config(file : Bytes) -> Int32 raise {
  let should_write = if @sys.stat(file) is Some(_) {
    @sys.print_stdout(file + b" already exists. Overwrite? (y/n) ")
    @sys.flush_stdout()
    let lines = @bstr.split_lines(@sys.read_stdin())
    let response = @bstr.to_string(lines.get(0).unwrap_or(b"")).to_lower()
    response == "yes" || response == "y"
  } else {
    true
  }
  if should_write {
    @lib.save_default(file)
    @sys.print_stdout(b"Default configuration written to " + file + b"\n")
    0
  } else {
    @sys.print_stdout(b"Configuration file not written!\n")
    1
  }
}

///|
fn regexes(args : ParsedArgs, name : String) -> Array[@string.Regex] raise {
  let out = []
  for pattern in args.values.get(name).unwrap_or([]) {
    out.push(@string.Regex(pattern))
  }
  out
}

///|
fn override_config(
  config : @kernel.Configuration,
  args : ParsedArgs,
  output~ : @kernel.Output?,
) -> @kernel.Configuration raise {
  let flag_set = (name : String, value : Bool) => {
    if args.has(name) {
      Some(value)
    } else {
      None
    }
  }
  let no_semantic_cleanup = args.has("no-semantic-cleanup")
  let big_enough = fn(name : String) raise {
    let value = args.get_int(name)
    if no_semantic_cleanup {
      if value is Some(_) {
        raise @lib.Failure(
          "Cannot pass both [-\{name}] and [-no-semantic-cleanup]",
        )
      }
      Some(1)
    } else {
      value
    }
  }
  let side_by_side : @kernel.WrapOrTruncate? = match args.get("side-by-side") {
    None => None
    Some("wrap") => Some(Wrap)
    Some("truncate") => Some(Truncate)
    Some(other) =>
      raise UsageError("failed to parse -side-by-side value \"\{other}\"")
  }
  let float_tolerance : Double?? = match args.get("float-tolerance") {
    None => None
    Some(value) =>
      match parse_percent(value) {
        Some(tolerance) => Some(Some(tolerance))
        None =>
          raise UsageError(
            "failed to parse -float-tolerance value \"\{value}\"",
          )
      }
  }
  let location_style = match args.get("location-style") {
    None => None
    Some(value) =>
      match @kernel.LocationStyle::of_string(value) {
        Some(style) => Some(style)
        None =>
          raise UsageError("failed to parse -location-style value \"\{value}\"")
      }
  }
  let warn_in_both = match args.get("warn-if-no-trailing-newline-in-both") {
    None => None
    Some("true") => Some(true)
    Some("false") => Some(false)
    Some(other) =>
      raise UsageError(
        "failed to parse -warn-if-no-trailing-newline-in-both value \"\{other}\"",
      )
  }
  let produce_unified_lines = flag_set("dont-produce-unified-lines", false)
  let alt = (name : String) => args.get(name).map(s => Some(@bstr.of_string(s)))
  config.override_with(
    output?,
    unrefined?=flag_set("unrefined", true),
    produce_unified_lines?,
    float_tolerance?,
    keep_ws?=flag_set("keep-whitespace", true),
    find_moves?=if produce_unified_lines is Some(false) {
      Some(false)
    } else {
      flag_set("find-moves", true)
    },
    split_long_lines?=flag_set("split-long-lines", true),
    interleave?=flag_set("no-interleave", false),
    assume_text?=flag_set("text", true),
    context?=args.get_int("context"),
    line_big_enough?=big_enough("line-big-enough"),
    word_big_enough?=big_enough("word-big-enough"),
    shallow?=flag_set("shallow", true),
    quiet?=flag_set("quiet", true),
    double_check?=flag_set("double-check", true),
    mask_uniques?=flag_set("mask-uniques", true),
    prev_alt?=alt("alt-prev"),
    next_alt?=alt("alt-next"),
    location_style?,
    warn_if_no_trailing_newline_in_both?=warn_in_both,
    // Unlike the other flags, these always replace what the config file says.
    side_by_side~,
    width_override=args.get_int("width"),
  )
}

///|
fn compare_main(
  args : ParsedArgs,
  prev_file : Bytes,
  next_file : Bytes,
  output~ : @kernel.Output?,
) -> Int32 raise {
  let filename = if args.has("default") {
    if args.has("file") {
      raise @lib.Failure("Cannot pass both [-default] and [-file]")
    }
    Some(b"")
  } else {
    args.get("file").map(s => @bstr.of_string(s))
  }
  let config = @lib.get_config(filename?)
  let config = override_config(config, args, output~)
  let exists = fn(file : Bytes) raise { @sys.stat(file) is Some(_) }
  let is_dir = fn(file : Bytes) raise {
    @sys.stat(file) is Some({ kind: Directory, .. })
  }
  let shown = (file : Bytes) => @bstr.to_string(file)
  let prev_exists = exists(prev_file)
  let next_exists = exists(next_file)
  if !prev_exists && !next_exists {
    raise @lib.Failure(
      "Both files, \{shown(prev_file)} and \{shown(next_file)}, do not exist",
    )
  }
  let include_ = regexes(args, "include")
  let exclude = regexes(args, "exclude")
  let different = match (is_dir(prev_file), is_dir(next_file)) {
    (true, false) | (false, true) => {
      // One is a directory, the other is a file or missing.
      let (dir, file) = if is_dir(prev_file) {
        (prev_file, next_file)
      } else {
        (next_file, prev_file)
      }
      if exists(file) {
        raise @lib.Failure(
          "\{shown(dir)} is a directory, while \{shown(file)} is a file",
        )
      }
      raise @lib.Failure(
        "\{shown(dir)} is a directory, while \{shown(file)} does not exist",
      )
    }
    (true, true) => {
      let file_filter = if include_.is_empty() && exclude.is_empty() {
        None
      } else {
        Some(fn(path : Bytes, stat : @sys.Stat) {
          let matches = (rex : @string.Regex) => {
            rex.execute(@bstr.to_string(path)) is Some(_)
          }
          !(stat.kind is Regular) ||
          (
            !exclude.iter().any(matches) &&
            (include_.is_empty() || include_.iter().any(matches))
          )
        })
      }
      @lib.diff_dirs(
        config,
        prev_dir=prev_file,
        next_dir=next_file,
        file_filter~,
      )
    }
    (false, false) => {
      if !include_.is_empty() || !exclude.is_empty() {
        raise @lib.Failure(
          "Can only specify -include or -exclude when diffing two dirs",
        )
      }
      @lib.diff_files(
        config,
        prev_file=if prev_exists { prev_file } else { b"/dev/null" },
        next_file=if next_exists { next_file } else { b"/dev/null" },
      )
    }
  }
  if different {
    1
  } else {
    0
  }
}

///|
fn run(argv : ArrayView[String]) -> Int32 raise {
  let args = parse_args(argv)
  if args.has("help") {
    @sys.print_stdout(@bstr.of_string(usage()))
    return 0
  }
  if args.has("version") {
    @sys.print_stdout(@bstr.of_string(VERSION + "\n"))
    return 0
  }
  let output = output_flag(args)
  if args.get("make-config") is Some(file) {
    return make_config(@bstr.of_string(file))
  }
  let (prev_file, next_file, temporary) = match args.anons {
    [prev, next] => (@bstr.of_string(prev), @bstr.of_string(next), false)
    [] => {
      let (prev, next) = files_from_stdin()
      (prev, next, true)
    }
    [_] => raise UsageError("missing anonymous argument: FILE2")
    _ => raise UsageError("too many anonymous arguments")
  }
  let (first, second) = if args.has("reverse") {
    (next_file, prev_file)
  } else {
    (prev_file, next_file)
  }
  let cleanup = () => {
    if temporary {
      @sys.unlink(prev_file)
      @sys.unlink(next_file)
    }
  }
  defer cleanup()
  compare_main(args, first, second, output~)
}

///|
/// An error, rendered the way OCaml's `Exn.to_string` would.
fn describe_error(err : Error) -> String {
  match err {
    @lib.Failure(msg) => {
      let quoted = msg
        .replace_all(old="\\", new="\\\\")
        .replace_all(old="\"", new="\\\"")
      "(Failure \"\{quoted}\")"
    }
    err => err.to_string()
  }
}

///|
fn main {
  let argv = @env.args()
  let code = run(argv[1:]) catch {
    UsageError(msg) => {
      @sys.print_stderr(
        @bstr.of_string(
          "Error parsing command line:\n\n  \{msg}\n\nFor usage information, run\n\n  patdiff -help\n\n",
        ),
      )
      1
    }
    err => {
      @sys.print_stderr(
        @bstr.of_string("Uncaught exception:\n  \n  \{describe_error(err)}\n\n"),
      )
      1
    }
  }
  @sys.exit(code)
}
