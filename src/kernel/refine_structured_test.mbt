// Helpers rendering hunks as the s-expressions upstream's tests print. The
// expectations below are upstream's, verbatim; they are compared as parsed
// s-expressions, so the layout of upstream's pretty-printer doesn't matter.

///|
fn sx_atom(s : String) -> @sexp.Sexp {
  @sexp.Sexp::Atom(b(s))
}

///|
fn sx_bytes(s : Bytes) -> @sexp.Sexp {
  @sexp.Sexp::Atom(s)
}

///|
fn sx_list(xs : Array[@sexp.Sexp]) -> @sexp.Sexp {
  @sexp.Sexp::List(xs)
}

///|
fn sx_int(n : Int32) -> @sexp.Sexp {
  sx_atom(n.to_string())
}

///|
/// OCaml's option sexp: `()` or `(x)`.
fn[A] sx_option(x : A?, f : (A) -> @sexp.Sexp) -> @sexp.Sexp {
  match x {
    None => sx_list([])
    Some(x) => sx_list([f(x)])
  }
}

///|
fn sx_move_kind(m : @pd.MoveKind) -> @sexp.Sexp {
  match m {
    Move(id) => sx_list([sx_atom("Move"), sx_int(id)])
    WithinMove(id) => sx_list([sx_atom("Within_move"), sx_int(id)])
  }
}

///|
fn[A] sx_array(xs : ArrayView[A], f : (A) -> @sexp.Sexp) -> @sexp.Sexp {
  sx_list([ for x in xs => f(x) ])
}

///|
fn[A] sx_range(r : @pd.Range[A], f : (A) -> @sexp.Sexp) -> @sexp.Sexp {
  match r {
    Same(pairs) =>
      sx_list([sx_atom("Same"), sx_array(pairs, p => sx_list([f(p.0), f(p.1)]))])
    Prev(xs, mk) =>
      sx_list([sx_atom("Prev"), sx_array(xs, f), sx_option(mk, sx_move_kind)])
    Next(xs, mk) =>
      sx_list([sx_atom("Next"), sx_array(xs, f), sx_option(mk, sx_move_kind)])
    Replace(xs, ys, id) =>
      sx_list([
        sx_atom("Replace"),
        sx_array(xs, f),
        sx_array(ys, f),
        sx_option(id, sx_int),
      ])
    Unified(xs, id) =>
      sx_list([sx_atom("Unified"), sx_array(xs, f), sx_option(id, sx_int)])
  }
}

///|
fn[A] sx_hunk(h : @pd.Hunk[A], f : (A) -> @sexp.Sexp) -> @sexp.Sexp {
  sx_list([
    sx_list([sx_atom("prev_start"), sx_int(h.prev_start)]),
    sx_list([sx_atom("prev_size"), sx_int(h.prev_size)]),
    sx_list([sx_atom("next_start"), sx_int(h.next_start)]),
    sx_list([sx_atom("next_size"), sx_int(h.next_size)]),
    sx_list([sx_atom("ranges"), sx_array(h.ranges, r => sx_range(r, f))]),
  ])
}

///|
fn[A] sx_hunks(
  hunks : ArrayView[@pd.Hunk[A]],
  f : (A) -> @sexp.Sexp,
) -> @sexp.Sexp {
  sx_array(hunks, h => sx_hunk(h, f))
}

///|
/// A line of a structured hunk: a list of `(Tag text)`.
fn sx_tagged_line(line : Array[(@kernel.Tag, Bytes)]) -> @sexp.Sexp {
  sx_array(line, p => {
    let tag = match p.0 {
      Prev => "Prev"
      Same => "Same"
      Next => "Next"
    }
    sx_list([sx_atom(tag), sx_bytes(p.1)])
  })
}

///|
fn sx_expect(actual : @sexp.Sexp, expected : String) -> Unit raise {
  let parsed = @sexp.Sexp::parse(b(expected))
  if actual != parsed {
    fail(
      "expected:\n\{shown(parsed.to_bytes_hum())}\n---- actual:\n\{shown(actual.to_bytes_hum())}\n----",
    )
  }
}

///|
fn rs_test(
  mark_newline_changes~ : Bool = false,
  produce_unified_lines~ : Bool,
  prev~ : String,
  next~ : String,
) -> @sexp.Sexp {
  let prev = @bstr.split_lines(b(prev))
  let next = @bstr.split_lines(b(next))
  let hunks = @kernel.diff(
    context=@kernel.DEFAULT_CONTEXT,
    line_big_enough=@kernel.DEFAULT_LINE_BIG_ENOUGH,
    keep_ws=false,
    find_moves=true,
    prev~,
    next~,
  )
  let refined_hunks = @kernel.refine_structured(
    mark_newline_changes~,
    produce_unified_lines~,
    keep_ws=false,
    split_long_lines=true,
    interleave=true,
    word_big_enough=@kernel.DEFAULT_WORD_BIG_ENOUGH,
    hunks,
  )
  sx_hunks(refined_hunks, sx_tagged_line)
}

///|
test "refine_structured: a changed word" {
  let prev =
    #|
    #|a
    #|b
    #|cats
    #|dogs are the best pets to have
    #|elephant
    #|f
    #|g
    #|h
    #|i
    #|j
    #|k
    #|
  let next =
    #|
    #|a
    #|b
    #|cats
    #|dogs are the cutest pets to have
    #|elephant
    #|f
    #|g
    #|h
    #|i
    #|j
    #|k
    #|
  let expected =
    #|((
    #|  (prev_start 1)
    #|  (prev_size  12)
    #|  (next_start 1)
    #|  (next_size  12)
    #|  (ranges (
    #|    (Same (
    #|      (((Same ""))   ((Same "")))
    #|      (((Same a))    ((Same a)))
    #|      (((Same b))    ((Same b)))
    #|      (((Same cats)) ((Same cats)))))
    #|    (Replace
    #|      ((
    #|        (Same "")
    #|        (Same "dogs are the")
    #|        (Prev " best")
    #|        (Same " pets to have")))
    #|      ((
    #|        (Same "")
    #|        (Same "dogs are the")
    #|        (Next " cutest")
    #|        (Same " pets to have")))
    #|      ())
    #|    (Same (
    #|      (((Same elephant)) ((Same elephant)))
    #|      (((Same f))        ((Same f)))
    #|      (((Same g))        ((Same g)))
    #|      (((Same h))        ((Same h)))
    #|      (((Same i))        ((Same i)))
    #|      (((Same j))        ((Same j)))
    #|      (((Same k))        ((Same k)))))))))
  sx_expect(rs_test(produce_unified_lines=true, prev~, next~), expected)
}

///|
test "refine_structured: moved paragraph" {
  let prev =
    #|
    #|Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce sit amet
    #|malesuada leo. Vivamus vitae orci quis justo ornare molestie. Donec fringilla
    #|tempus magna, ut semper lacus tincidunt at. Suspendisse et rutrum arcu. Aliquam
    #|erat volutpat. Pellentesque pretium pellentesque elit, a consequat metus
    #|placerat a. Praesent hendrerit euismod sem nec facilisis. Curabitur finibus ex
    #|sagittis massa blandit, et dictum lectus lobortis. Sed fringilla fringilla
    #|tortor vel finibus. Sed vel tortor pulvinar, fermentum quam non, blandit lorem.
    #|
    #|Maecenas ac elit turpis. Nam ex turpis, ullamcorper et ultricies eu, pretium et
    #|elit. Duis bibendum aliquet quam et tempor. Donec quis dapibus justo. Praesent
    #|eget pellentesque nisi. Nulla vestibulum orci quis dui laoreet, eget posuere sem
    #|interdum. Morbi ac sodales ligula. Proin arcu ipsum, venenatis id cursus et,
    #|blandit eu mi. Sed iaculis egestas ligula, lacinia condimentum velit commodo
    #|non. In eu elit convallis, tempus sapien sed, maximus purus. Sed vitae enim et
    #|tellus accumsan bibendum eu vel turpis. Phasellus massa leo, eleifend vel
    #|tincidunt ut, consequat et est. Duis quis condimentum ex. Etiam nec faucibus
    #|lorem. Aliquam vehicula porta sapien, ut aliquam purus cursus vitae. Nullam at
    #|ex vehicula, egestas sapien vitae, molestie ipsum.
    #|
    #|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo
    #|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|Cras non semper ante. Vivamus non nulla scelerisque, fermentum sem at, laoreet
    #|est. Sed convallis, magna sit amet maximus sollicitudin, nulla metus sodales
    #|eros, eu molestie arcu urna ut nunc. Pellentesque habitant morbi tristique
    #|senectus et netus et malesuada fames ac turpis egestas. Morbi sollicitudin,
    #|turpis sit amet ultricies interdum, urna nisl rhoncus tellus, id consectetur
    #|urna risus ut arcu. Aliquam hendrerit eros id ex tempor vehicula. Nunc a pretium
    #|risus. Nulla tincidunt, mauris eu pellentesque hendrerit, nisi nibh volutpat
    #|sapien, vitae vehicula lacus tellus dictum augue. Pellentesque malesuada vitae
    #|tellus lobortis laoreet. Donec fringilla lacinia nulla sit amet eleifend.
    #|Suspendisse iaculis metus sed massa bibendum, quis consequat metus lacinia.
    #|Etiam scelerisque odio nec pulvinar dapibus. Duis interdum interdum quam vel
    #|dapibus. Quisque dapibus nisl quis magna accumsan, et lobortis magna eleifend.
    #|Ut venenatis cursus diam, vel dictum augue interdum vitae. Ut scelerisque
    #|condimentum augue, eget bibendum augue lacinia in.
    #|
    #|Aenean porta elit vitae pharetra dapibus. Duis a odio neque. Curabitur
    #|ullamcorper enim ut metus luctus, eu blandit augue consectetur. Vestibulum
    #|blandit lorem eget blandit fringilla. In et libero non lacus elementum pulvinar
    #|id a orci. Maecenas porta urna mollis, egestas lacus id, feugiat nisi. Vivamus
    #|imperdiet ornare dui eleifend semper. Integer erat ipsum, vestibulum a lobortis
    #|eu, posuere in orci. Pellentesque gravida in purus eu ullamcorper. Nunc urna
    #|tortor, hendrerit nec eleifend et, dapibus sed dolor.
    #|
  let next =
    #|
    #|Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce sit amet
    #|malesuada leo. Vivamus vitae orci quis justo ornare molestie. Donec fringilla
    #|tempus magna, ut semper lacus tincidunt at. Suspendisse et rutrum arcu. Aliquam
    #|erat volutpat. Pellentesque pretium pellentesque elit, a consequat metus
    #|placerat a. Praesent hendrerit euismod sem nec facilisis. Curabitur finibus ex
    #|sagittis massa blandit, et dictum lectus lobortis. Sed fringilla fringilla
    #|tortor vel finibus. Sed vel tortor pulvinar, fermentum quam non, blandit lorem.
    #|
    #|Cras non semper ante. Vivamus non nulla scelerisque, fermentum sem at, laoreet
    #|est. Sed convallis, magna sit amet maximus sollicitudin, nulla metus sodales
    #|eros, eu molestie arcu urna ut nunc. Pellentesque habitant morbi tristique
    #|senectus et netus et malesuada fames ac turpis egestas. Morbi sollicitudin,
    #|turpis sit amet ultricies interdum, urna nisl rhoncus tellus, id consectetur
    #|tellus lobortis laoreet. Donec fringilla lacinia nulla sit amet eleifend.
    #|Suspendisse iaculis metus sed massa bibendum, quis consequat metus lacinia.
    #|Etiam scelerisque odio nec pulvinar dapibus. Duis interdum interdum quam vel
    #|dapibus. Quisque dapibus nisl quis magna accumsan, et lobortis magna eleifend.
    #|Ut venenatis cursus diam, vel dictum augue interdum vitae. Ut scelerisque
    #|condimentum augue, eget bibendum augue lacinia in.
    #|
    #|
    #|Maecenas ac elit turpis. Nam ex turpis, ullamcorper et ultricies eu, pretium et
    #|elit. Duis bibendum aliquet quam et tempor. Donec quis dapibus justo. Praesent
    #|eget pellentesque nisi. Nulla vestibulum orci quis dui laoreet, eget posuere sem
    #|interdum. Morbi ac sodales ligula. Proin arcu ipsum, venenatis id cursus et,
    #|blandit eu mi. Sed iaculis egestas ligula, lacinia condimentum velit commodo
    #|non. In eu elit convallis, tempus sapien sed, maximus purus. Sed vitae enim et
    #|tellus accumsan bibendum eu vel turpis. Phasellus massa leo, eleifend vel
    #|tincidunt ut, consequat et est. Duis quis condimentum ex. Etiam nec faucibus
    #|lorem. Aliquam vehicula porta sapien, ut aliquam purus cursus vitae. Nullam at
    #|ex vehicula, egestas sapien vitae, molestie ipsum.
    #|
    #|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo
    #|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|Aenean porta elit vitae pharetra dapibus. Duis a odio neque. Curabitur
    #|ullamcorper enim ut metus luctus, eu blandit augue consectetur. Vestibulum
    #|blandit lorem eget blandit fringilla. In et libero non lacus elementum pulvinar
    #|id a orci. Maecenas porta urna mollis, egestas lacus id, feugiat nisi. Vivamus
    #|imperdiet ornare dui eleifend semper. Integer erat ipsum, vestibulum a lobortis
    #|eu, posuere in orci. Pellentesque gravida in purus eu ullamcorper. Nunc urna
    #|tortor, hendrerit nec eleifend et, dapibus sed dolor.
    #|
  let expected =
    #|((
    #|  (prev_start 1)
    #|  (prev_size  49)
    #|  (next_start 1)
    #|  (next_size  47)
    #|  (ranges (
    #|    (Same (
    #|      (((Same ""))
    #|       ((Same "")))
    #|      (((
    #|         Same
    #|         "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce sit amet"))
    #|       ((
    #|         Same
    #|         "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce sit amet")))
    #|      (((
    #|         Same
    #|         "malesuada leo. Vivamus vitae orci quis justo ornare molestie. Donec fringilla"))
    #|       ((
    #|         Same
    #|         "malesuada leo. Vivamus vitae orci quis justo ornare molestie. Donec fringilla")))
    #|      (((
    #|         Same
    #|         "tempus magna, ut semper lacus tincidunt at. Suspendisse et rutrum arcu. Aliquam"))
    #|       ((
    #|         Same
    #|         "tempus magna, ut semper lacus tincidunt at. Suspendisse et rutrum arcu. Aliquam")))
    #|      (((
    #|         Same
    #|         "erat volutpat. Pellentesque pretium pellentesque elit, a consequat metus"))
    #|       ((
    #|         Same
    #|         "erat volutpat. Pellentesque pretium pellentesque elit, a consequat metus")))
    #|      (((
    #|         Same
    #|         "placerat a. Praesent hendrerit euismod sem nec facilisis. Curabitur finibus ex"))
    #|       ((
    #|         Same
    #|         "placerat a. Praesent hendrerit euismod sem nec facilisis. Curabitur finibus ex")))
    #|      (((
    #|         Same
    #|         "sagittis massa blandit, et dictum lectus lobortis. Sed fringilla fringilla"))
    #|       ((
    #|         Same
    #|         "sagittis massa blandit, et dictum lectus lobortis. Sed fringilla fringilla")))
    #|      (((
    #|         Same
    #|         "tortor vel finibus. Sed vel tortor pulvinar, fermentum quam non, blandit lorem."))
    #|       ((
    #|         Same
    #|         "tortor vel finibus. Sed vel tortor pulvinar, fermentum quam non, blandit lorem.")))))
    #|    (Next
    #|      (((Same ""))
    #|       ((
    #|         Same
    #|         "Cras non semper ante. Vivamus non nulla scelerisque, fermentum sem at, laoreet"))
    #|       ((
    #|         Same
    #|         "est. Sed convallis, magna sit amet maximus sollicitudin, nulla metus sodales"))
    #|       ((
    #|         Same
    #|         "eros, eu molestie arcu urna ut nunc. Pellentesque habitant morbi tristique"))
    #|       ((
    #|         Same
    #|         "senectus et netus et malesuada fames ac turpis egestas. Morbi sollicitudin,"))
    #|       ((
    #|         Same
    #|         "turpis sit amet ultricies interdum, urna nisl rhoncus tellus, id consectetur")))
    #|      ((Move 0)))
    #|    (Prev
    #|      (((
    #|         Same
    #|         "urna risus ut arcu. Aliquam hendrerit eros id ex tempor vehicula. Nunc a pretium"))
    #|       ((
    #|         Same
    #|         "risus. Nulla tincidunt, mauris eu pellentesque hendrerit, nisi nibh volutpat"))
    #|       ((
    #|         Same
    #|         "sapien, vitae vehicula lacus tellus dictum augue. Pellentesque malesuada vitae")))
    #|      ((Within_move 0)))
    #|    (Next
    #|      (((
    #|         Same
    #|         "tellus lobortis laoreet. Donec fringilla lacinia nulla sit amet eleifend."))
    #|       ((
    #|         Same
    #|         "Suspendisse iaculis metus sed massa bibendum, quis consequat metus lacinia."))
    #|       ((
    #|         Same
    #|         "Etiam scelerisque odio nec pulvinar dapibus. Duis interdum interdum quam vel"))
    #|       ((
    #|         Same
    #|         "dapibus. Quisque dapibus nisl quis magna accumsan, et lobortis magna eleifend."))
    #|       ((
    #|         Same
    #|         "Ut venenatis cursus diam, vel dictum augue interdum vitae. Ut scelerisque"))
    #|       ((Same "condimentum augue, eget bibendum augue lacinia in.")))
    #|      ((Move 0)))
    #|    (Same ((
    #|      ((Same ""))
    #|      ((Same "")))))
    #|    (Same (
    #|      (((Same ""))
    #|       ((Same "")))
    #|      (((
    #|         Same
    #|         "Maecenas ac elit turpis. Nam ex turpis, ullamcorper et ultricies eu, pretium et"))
    #|       ((
    #|         Same
    #|         "Maecenas ac elit turpis. Nam ex turpis, ullamcorper et ultricies eu, pretium et")))
    #|      (((
    #|         Same
    #|         "elit. Duis bibendum aliquet quam et tempor. Donec quis dapibus justo. Praesent"))
    #|       ((
    #|         Same
    #|         "elit. Duis bibendum aliquet quam et tempor. Donec quis dapibus justo. Praesent")))
    #|      (((
    #|         Same
    #|         "eget pellentesque nisi. Nulla vestibulum orci quis dui laoreet, eget posuere sem"))
    #|       ((
    #|         Same
    #|         "eget pellentesque nisi. Nulla vestibulum orci quis dui laoreet, eget posuere sem")))
    #|      (((
    #|         Same
    #|         "interdum. Morbi ac sodales ligula. Proin arcu ipsum, venenatis id cursus et,"))
    #|       ((
    #|         Same
    #|         "interdum. Morbi ac sodales ligula. Proin arcu ipsum, venenatis id cursus et,")))
    #|      (((
    #|         Same
    #|         "blandit eu mi. Sed iaculis egestas ligula, lacinia condimentum velit commodo"))
    #|       ((
    #|         Same
    #|         "blandit eu mi. Sed iaculis egestas ligula, lacinia condimentum velit commodo")))
    #|      (((
    #|         Same
    #|         "non. In eu elit convallis, tempus sapien sed, maximus purus. Sed vitae enim et"))
    #|       ((
    #|         Same
    #|         "non. In eu elit convallis, tempus sapien sed, maximus purus. Sed vitae enim et")))
    #|      (((
    #|         Same
    #|         "tellus accumsan bibendum eu vel turpis. Phasellus massa leo, eleifend vel"))
    #|       ((
    #|         Same
    #|         "tellus accumsan bibendum eu vel turpis. Phasellus massa leo, eleifend vel")))
    #|      (((
    #|         Same
    #|         "tincidunt ut, consequat et est. Duis quis condimentum ex. Etiam nec faucibus"))
    #|       ((
    #|         Same
    #|         "tincidunt ut, consequat et est. Duis quis condimentum ex. Etiam nec faucibus")))
    #|      (((
    #|         Same
    #|         "lorem. Aliquam vehicula porta sapien, ut aliquam purus cursus vitae. Nullam at"))
    #|       ((
    #|         Same
    #|         "lorem. Aliquam vehicula porta sapien, ut aliquam purus cursus vitae. Nullam at")))
    #|      (((Same "ex vehicula, egestas sapien vitae, molestie ipsum."))
    #|       ((Same "ex vehicula, egestas sapien vitae, molestie ipsum.")))
    #|      (((Same ""))
    #|       ((Same "")))
    #|      (((
    #|         Same
    #|         "Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis."))
    #|       ((
    #|         Same
    #|         "Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.")))
    #|      (((
    #|         Same
    #|         "Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac"))
    #|       ((
    #|         Same
    #|         "Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac")))
    #|      (((
    #|         Same
    #|         "tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo"))
    #|       ((
    #|         Same
    #|         "tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo")))
    #|      (((
    #|         Same
    #|         "lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis"))
    #|       ((
    #|         Same
    #|         "lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis")))
    #|      (((
    #|         Same
    #|         "vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at"))
    #|       ((
    #|         Same
    #|         "vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at")))
    #|      (((Same "tortor posuere convallis sed sed risus. Quisque sed ipsum ex."))
    #|       ((Same "tortor posuere convallis sed sed risus. Quisque sed ipsum ex.")))))
    #|    (Prev
    #|      (((Same ""))
    #|       ((
    #|         Same
    #|         "Cras non semper ante. Vivamus non nulla scelerisque, fermentum sem at, laoreet"))
    #|       ((
    #|         Same
    #|         "est. Sed convallis, magna sit amet maximus sollicitudin, nulla metus sodales"))
    #|       ((
    #|         Same
    #|         "eros, eu molestie arcu urna ut nunc. Pellentesque habitant morbi tristique"))
    #|       ((
    #|         Same
    #|         "senectus et netus et malesuada fames ac turpis egestas. Morbi sollicitudin,"))
    #|       ((
    #|         Same
    #|         "turpis sit amet ultricies interdum, urna nisl rhoncus tellus, id consectetur"))
    #|       ((
    #|         Same
    #|         "urna risus ut arcu. Aliquam hendrerit eros id ex tempor vehicula. Nunc a pretium"))
    #|       ((
    #|         Same
    #|         "risus. Nulla tincidunt, mauris eu pellentesque hendrerit, nisi nibh volutpat"))
    #|       ((
    #|         Same
    #|         "sapien, vitae vehicula lacus tellus dictum augue. Pellentesque malesuada vitae"))
    #|       ((
    #|         Same
    #|         "tellus lobortis laoreet. Donec fringilla lacinia nulla sit amet eleifend."))
    #|       ((
    #|         Same
    #|         "Suspendisse iaculis metus sed massa bibendum, quis consequat metus lacinia."))
    #|       ((
    #|         Same
    #|         "Etiam scelerisque odio nec pulvinar dapibus. Duis interdum interdum quam vel"))
    #|       ((
    #|         Same
    #|         "dapibus. Quisque dapibus nisl quis magna accumsan, et lobortis magna eleifend."))
    #|       ((
    #|         Same
    #|         "Ut venenatis cursus diam, vel dictum augue interdum vitae. Ut scelerisque"))
    #|       ((Same "condimentum augue, eget bibendum augue lacinia in.")))
    #|      ((Move 0)))
    #|    (Same (
    #|      (((Same ""))
    #|       ((Same "")))
    #|      (((
    #|         Same
    #|         "Aenean porta elit vitae pharetra dapibus. Duis a odio neque. Curabitur"))
    #|       ((
    #|         Same
    #|         "Aenean porta elit vitae pharetra dapibus. Duis a odio neque. Curabitur")))
    #|      (((
    #|         Same
    #|         "ullamcorper enim ut metus luctus, eu blandit augue consectetur. Vestibulum"))
    #|       ((
    #|         Same
    #|         "ullamcorper enim ut metus luctus, eu blandit augue consectetur. Vestibulum")))
    #|      (((
    #|         Same
    #|         "blandit lorem eget blandit fringilla. In et libero non lacus elementum pulvinar"))
    #|       ((
    #|         Same
    #|         "blandit lorem eget blandit fringilla. In et libero non lacus elementum pulvinar")))
    #|      (((
    #|         Same
    #|         "id a orci. Maecenas porta urna mollis, egestas lacus id, feugiat nisi. Vivamus"))
    #|       ((
    #|         Same
    #|         "id a orci. Maecenas porta urna mollis, egestas lacus id, feugiat nisi. Vivamus")))
    #|      (((
    #|         Same
    #|         "imperdiet ornare dui eleifend semper. Integer erat ipsum, vestibulum a lobortis"))
    #|       ((
    #|         Same
    #|         "imperdiet ornare dui eleifend semper. Integer erat ipsum, vestibulum a lobortis")))
    #|      (((
    #|         Same
    #|         "eu, posuere in orci. Pellentesque gravida in purus eu ullamcorper. Nunc urna"))
    #|       ((
    #|         Same
    #|         "eu, posuere in orci. Pellentesque gravida in purus eu ullamcorper. Nunc urna")))
    #|      (((Same "tortor, hendrerit nec eleifend et, dapibus sed dolor."))
    #|       ((Same "tortor, hendrerit nec eleifend et, dapibus sed dolor.")))))))))
  sx_expect(rs_test(produce_unified_lines=true, prev~, next~), expected)
}

///|
test "test generating a unified structured range" {
  let prev =
    #|Some really long line that will be unified after I make a small change
  let next =
    #|Some really long line that will be unified after I make small change
  let expected =
    #|((
    #|  (prev_start 1)
    #|  (prev_size  1)
    #|  (next_start 1)
    #|  (next_size  1)
    #|  (ranges ((
    #|    Unified
    #|    ((
    #|      (Same "")
    #|      (Same "Some really long line that will be unified after I make")
    #|      (Prev " a")
    #|      (Same " small change")))
    #|    ())))))
  sx_expect(rs_test(produce_unified_lines=true, prev~, next~), expected)
}

///|
test "test newline changes while ignoring whitespace" {
  let prev =
    #|Line one
    #|Some line that will be broken up over multiple lines
    #|Line two
    #|Line three
    #|
  let next =
    #|Line one
    #|Some line that will be
    #|broken up over
    #|multiple lines
    #|Line two
    #|Line three
    #|
  let expected =
    #|()
  sx_expect(rs_test(produce_unified_lines=false, prev~, next~), expected)
}

///|
test "test newline changes with [mark_newline_changes]" {
  let prev =
    #|Line one
    #|Some line that will be broken up over multiple lines
    #|Line two
    #|Line three
    #|
  let next =
    #|Line one
    #|Some line that will be
    #|broken up over
    #|multiple lines
    #|Line two
    #|Line three
    #|
  // With [mark_newline_changes], the single line that was broken up into multiple
  // lines should now be marked as a [Replace], with the difference being the added
  // [Next ""]s representing the newlines.
  let expected =
    #|((
    #|  (prev_start 1)
    #|  (prev_size  4)
    #|  (next_start 1)
    #|  (next_size  6)
    #|  (ranges (
    #|    (Same ((
    #|      ((Same "Line one"))
    #|      ((Same "Line one")))))
    #|    (Replace
    #|      ((
    #|        (Same "")
    #|        (Same "Some line that will be")
    #|        (Same " broken up over")
    #|        (Same " multiple lines")))
    #|      (((Same "") (Same "Some line that will be") (Next ""))
    #|       ((Next "") (Same "broken up over")         (Next ""))
    #|       ((Next "")
    #|        (Same "multiple lines")))
    #|      ())
    #|    (Same (
    #|      (((Same "Line two"))   ((Same "Line two")))
    #|      (((Same "Line three")) ((Same "Line three")))))))))
  sx_expect(
    rs_test(
      mark_newline_changes=true,
      produce_unified_lines=false,
      prev~,
      next~,
    ),
    expected,
  )
}

///|
test "whitespace only lines preserved with [mark_newline_changes]" {
  // This test checks that when [mark_newline_changes] is true, whitespace only
  // lines are preserved as actual changes rather than being dropped.
  let prev =
    #|line1
    #|line2
  let next =
    #|line1
    #|
    #|line2
  let expected =
    #|()
  sx_expect(rs_test(produce_unified_lines=false, prev~, next~), expected)
  let expected =
    #|((
    #|  (prev_start 1)
    #|  (prev_size  2)
    #|  (next_start 1)
    #|  (next_size  3)
    #|  (ranges (
    #|    (Same ((
    #|      ((Same line1))
    #|      ((Same line1)))))
    #|    (Next (((Same ""))) ())
    #|    (Same ((
    #|      ((Same line2))
    #|      ((Same line2)))))))))
  sx_expect(
    rs_test(
      mark_newline_changes=true,
      produce_unified_lines=false,
      prev~,
      next~,
    ),
    expected,
  )
}
