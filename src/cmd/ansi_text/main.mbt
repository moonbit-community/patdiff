///|
const USAGE =
  #|usage: ansi_text <command> [-minimize]
  #|
  #|Transforms text from stdin that contains ANSI escape codes.
  #|
  #|  visualize [-minimize]  show the escape codes in a human-readable form
  #|  minimize               use as few escape codes as possible
  #|  strip                  remove the escape codes
  #|

///|
fn run(args : ArrayView[String]) -> Int raise {
  // Each line is transformed on its own, so a line's styles don't depend on the
  // lines before it.
  let transform : ((Bytes) -> Bytes)? = match args {
    ["visualize"] => Some(@ansi_text.visualize)
    ["visualize", "-minimize"] =>
      Some(input => @ansi_text.visualize(@ansi_text.minimize(input)))
    ["minimize"] => Some(@ansi_text.minimize)
    ["strip"] => Some(@ansi_text.strip)
    _ => None
  }
  match transform {
    Some(transform) => {
      for line in @bstr.split_lines(@sys.read_stdin()) {
        @sys.print_stdout(transform(line) + b"\n")
      }
      0
    }
    None => {
      @sys.print_stderr(@bstr.of_string(USAGE))
      1
    }
  }
}

///|
fn main {
  let argv = @env.args()
  let code = try run(argv[1:]) catch {
    err => {
      @sys.print_stderr(@bstr.of_string("\{err}\n"))
      2
    }
  }
  @sys.exit(code)
}
