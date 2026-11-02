///|
/// The outcome of comparing two inputs.
pub(all) enum ComparisonResult {
  BinarySame
  BinaryDifferent(prev_is_binary~ : Bool, next_is_binary~ : Bool)
  Hunks(Array[@pd.Hunk[Bytes]])
  StructuredHunks(Array[StructuredHunk])
}

///|
/// Compares two inputs. `compare_assuming_text` is given a configuration which
/// may differ from `config`, depending on heuristics that consider `prev` and
/// `next`.
pub fn ComparisonResult::new(
  config : Configuration,
  prev~ : DiffInput,
  next~ : DiffInput,
  compare_assuming_text~ : (Configuration, DiffInput, DiffInput) -> ComparisonResult,
) -> ComparisonResult {
  let prev_is_binary = !config.assume_text && is_binary(prev.text)
  let next_is_binary = !config.assume_text && is_binary(next.text)
  if prev_is_binary || next_is_binary {
    if prev.text == next.text {
      BinarySame
    } else {
      BinaryDifferent(prev_is_binary~, next_is_binary~)
    }
  } else {
    let keep_ws = config.keep_ws || should_keep_whitespace(prev~, next~)
    compare_assuming_text(config.override_with(keep_ws~), prev, next)
  }
}

///|
pub fn ComparisonResult::has_no_diff(self : ComparisonResult) -> Bool {
  match self {
    BinarySame => true
    BinaryDifferent(..) => false
    Hunks(hunks) => hunks.iter().all(hunk => hunk.all_same())
    StructuredHunks(hunks) => hunks.iter().all(hunk => hunk.all_same())
  }
}

///|
/// The lines of `contents`, and whether it ends in a newline (an empty file
/// counts as doing so).
pub fn lines_of_contents(contents : Bytes) -> (Array[Bytes], Bool) {
  let n = contents.length()
  (@bstr.split_lines(contents), n == 0 || contents[n - 1] == b'\n')
}

///|
pub fn warn_if_no_trailing_newline(
  warn_if_no_trailing_newline_in_both~ : Bool,
  warn~ : (Bytes) -> Unit,
  prev~ : (Bool, Bytes),
  next~ : (Bool, Bytes),
) -> Unit {
  match (prev.0, next.0) {
    (true, true) => ()
    (true, false) => warn(next.1)
    (false, true) => warn(prev.1)
    (false, false) =>
      if warn_if_no_trailing_newline_in_both {
        warn(prev.1)
        warn(next.1)
      }
  }
}

///|
pub fn binary_different_message(
  config~ : Configuration,
  prev_file~ : FileName,
  prev_is_binary~ : Bool,
  next_file~ : FileName,
  next_is_binary~ : Bool,
) -> Bytes {
  match config.location_style {
    Diff | NoLocation | Separator =>
      b"Files " +
      prev_file.display_name() +
      (if prev_is_binary { b" (binary)" } else { b"" }) +
      b" and " +
      next_file.display_name() +
      (if next_is_binary { b" (binary)" } else { b"" }) +
      b" differ"
    Omake =>
      omake_style_error_message_start(file=prev_file.display_name(), line=1) +
      b"\n  File \"" +
      next_file.display_name() +
      b"\"\n  binary files differ\n"
  }
}

///|
/// Hunks ready to be printed.
pub fn compare_lines(
  config : Configuration,
  prev~ : ArrayView[Bytes],
  next~ : ArrayView[Bytes],
) -> ComparisonResult {
  let context = config.context
  let keep_ws = config.keep_ws
  let hunks = diff(
    context~,
    line_big_enough=config.line_big_enough,
    keep_ws~,
    find_moves=config.find_moves,
    prev~,
    next~,
  )
  let hunks = match config.float_tolerance {
    None => hunks
    Some(tolerance) => float_tolerance_apply(hunks, tolerance, context~)
  }
  if config.unrefined {
    // Turn `Replace` ranges into `Prev` and `Next` ranges. `Replace`s would
    // otherwise be later interpreted as refined output.
    let hunks = @pd.unified(hunks)
    if config.side_by_side is Some(_) {
      StructuredHunks(unrefined_structured(hunks))
    } else {
      Hunks(hunks)
    }
  } else if config.side_by_side is Some(_) {
    StructuredHunks(
      refine_structured(
        mark_newline_changes=true,
        keep_ws~,
        produce_unified_lines=false,
        split_long_lines=config.split_long_lines,
        interleave=config.interleave,
        word_big_enough=config.word_big_enough,
        hunks,
      ),
    )
  } else {
    Hunks(
      refine(
        rules=config.rules,
        output=config.output,
        keep_ws~,
        produce_unified_lines=config.produce_unified_lines,
        split_long_lines=config.split_long_lines,
        interleave=config.interleave,
        word_big_enough=config.word_big_enough,
        hunks,
      ),
    )
  }
}

///|
/// Compares two in-memory inputs, giving `None` when there's no difference and
/// otherwise the rendered diff.
pub fn diff_strings(
  print_global_header? : Bool = false,
  platform? : Platform = Platform::without_unix(),
  config : Configuration,
  prev~ : DiffInput,
  next~ : DiffInput,
) -> Bytes? {
  let result = ComparisonResult::new(
    config,
    prev~,
    next~,
    compare_assuming_text=(config, prev, next) => compare_lines(
      config,
      prev=@bstr.split_lines(prev.text),
      next=@bstr.split_lines(next.text),
    ),
  )
  if result.has_no_diff() {
    return None
  }
  let file_names : (FileName, FileName) = (Fake(prev.name), Fake(next.name))
  match result {
    BinarySame => abort("unreachable")
    BinaryDifferent(prev_is_binary~, next_is_binary~) =>
      Some(
        binary_different_message(
          config~,
          prev_file=file_names.0,
          prev_is_binary~,
          next_file=file_names.1,
          next_is_binary~,
        ),
      )
    Hunks(hunks) =>
      Some(
        output_to_string(
          hunks,
          print_global_header~,
          file_names~,
          output=config.output,
          rules=config.rules,
          location_style=config.location_style,
          platform~,
        ),
      )
    StructuredHunks(hunks) =>
      Some(
        output_to_string_side_by_side(
          hunks,
          file_names~,
          output=config.output,
          rules=config.rules,
          wrap_or_truncate=config.side_by_side.unwrap_or(Wrap),
          platform~,
        ),
      )
  }
}
