///|
/// What `[%expect]` compares: the printed output with leading and trailing
/// blank lines dropped, and trailing whitespace on each line ignored.
fn pc_trim_blank_lines(s : String) -> String {
  let lines : Array[String] = []
  for line in s.split("\n") {
    lines.push(@bstr.to_string(@bstr.rstrip(b(line.to_owned()))))
  }
  let is_blank = (line : String) => {
    line.iter().all(c => c == ' ' || c == '\t' || c == '\r')
  }
  let mut lo = 0
  let mut hi = lines.length()
  while lo < hi && is_blank(lines[lo]) {
    lo += 1
  }
  while hi > lo && is_blank(lines[hi - 1]) {
    hi -= 1
  }
  let kept : Array[String] = []
  for i in lo..<hi {
    kept.push(lines[i])
  }
  kept.join("\n")
}

///|
/// What `print_endline` shows for `output`, with ESC displayed as `␛`.
fn pc_print(output : Bytes) -> String {
  shown(output) + "\n"
}

///|
/// The equivalent of `[%expect {| expected |}]` for everything printed so far.
fn pc_expect(printed : String, expected : String) -> Unit raise {
  let actual = pc_trim_blank_lines(printed)
  let expected = pc_trim_blank_lines(expected)
  if actual != expected {
    fail("expected:\n\{expected}\n---- actual:\n\{actual}\n----")
  }
}

///|
fn pc_input(name : String, text : String) -> @kernel.DiffInput {
  @kernel.DiffInput::of_string(name, text)
}

// module%test _ (prev = "Foo bar buzz", next = "Foo buzz")

///|
test "Ansi output generates a single line diff" {
  let prev = pc_input("old", "Foo bar buzz")
  let next = pc_input("old", "Foo buzz")
  let expected =
    #|-1,1 +1,1
    #|␛[1;33m!|␛[22;39mFoo␛[31m bar␛[39m buzz
  pc_expect(
    pc_print(
      @kernel.patdiff(
        split_long_lines=false,
        produce_unified_lines=true,
        output=Ansi,
        prev~,
        next~,
      ),
    ),
    expected,
  )
}

///|
test "Ascii is supported if [produce_unified_lines] is false" {
  let prev = pc_input("old", "Foo bar buzz")
  let next = pc_input("old", "Foo buzz")
  let expected =
    #|-1,1 +1,1
    #|-|Foo bar buzz
    #|+|Foo buzz
  pc_expect(
    pc_print(
      @kernel.patdiff(
        split_long_lines=false,
        produce_unified_lines=false,
        output=Ascii,
        prev~,
        next~,
      ),
    ),
    expected,
  )
}

///|
test "don't highlight empty newlines (ascii)" {
  let expected =
    #|-1,0 +1,3
    #|+|
    #|+|
    #|+|
  pc_expect(
    pc_print(
      @kernel.patdiff(
        keep_ws=true,
        split_long_lines=false,
        produce_unified_lines=false,
        output=Ascii,
        prev=pc_input("old", ""),
        next=pc_input("new", "\n\n\n"),
      ),
    ),
    expected,
  )
}

///|
test "don't highlight empty newlines (ansi)" {
  let expected =
    #|-1,0 +1,3
    #|␛[1;32m+|␛[22;39m␛[32m␛[39m
    #|␛[1;32m+|␛[22;39m␛[32m␛[39m
    #|␛[1;32m+|␛[22;39m␛[32m␛[39m
  pc_expect(
    pc_print(
      @kernel.patdiff(
        keep_ws=true,
        split_long_lines=false,
        produce_unified_lines=false,
        output=Ansi,
        prev=pc_input("old", ""),
        next=pc_input("new", "\n\n\n"),
      ),
    ),
    expected,
  )
}

///|
test "do highlight empty newlines with some spaces (ansi)" {
  let expected =
    #|-1,0 +1,3
    #|␛[1;32m+|␛[22;39m␛[7;32m  ␛[27;39m
    #|␛[1;32m+|␛[22;39m␛[7;32m  ␛[27;39m
    #|␛[1;32m+|␛[22;39m␛[7;32m  ␛[27;39m
  pc_expect(
    pc_print(
      @kernel.patdiff(
        keep_ws=true,
        split_long_lines=false,
        produce_unified_lines=false,
        output=Ansi,
        prev=pc_input("old", ""),
        next=pc_input("new", "  \n  \n  \n"),
      ),
    ),
    expected,
  )
}

///|
test "panic Ascii is not supported if [produce_unified_lines] is true" {
  let prev = pc_input("old", "Foo bar buzz")
  let next = pc_input("old", "Foo buzz")
  ignore(
    @kernel.patdiff(
      split_long_lines=false,
      produce_unified_lines=true,
      output=Ascii,
      prev~,
      next~,
    ),
  )
}

///|
test "float tolerance works as expected" {
  let cases : Array[(Double?, String, String)] = [
    (None, "1.0", "1.00000000000001"),
    (None, "1.0", "1.0"),
    (Some(0.01), "1.0", "1.005"),
    (Some(0.01), "1.0", "1.015"),
  ]
  let printed = StringBuilder()
  for c in cases {
    let (float_tolerance, old_text, new_text) = c
    printed.write_string(
      pc_print(
        @kernel.patdiff(
          float_tolerance?,
          produce_unified_lines=false,
          output=Ascii,
          prev=pc_input("old", old_text),
          next=pc_input("new", new_text),
        ),
      ),
    )
  }
  let expected =
    #|-1,1 +1,1
    #|-|1.0
    #|+|1.00000000000001
    #|
    #|
    #|-1,1 +1,1
    #|-|1.0
    #|+|1.015
  pc_expect(printed.to_string(), expected)
}

///|
test "test single empty line" {
  let original =
    #|Line one
    #|Some line that will be deleted (and replaced with a single newline)
    #|  with some indented content on the next line
    #|Line four
    #|Line five
    #|Line six
    #|
  let modified =
    #|Line one
    #|
    #|Line four
    #|Line five
    #|An added line goes here
    #|Line six
  let expected =
    #|-1,6 +1,6
    #|  Line one
    #|-|Some line that will be deleted (and replaced with a single newline)
    #|-|  with some indented content on the next line
    #|  Line four
    #|  Line five
    #|+|An added line goes here
    #|  Line six
  pc_expect(
    pc_print(
      @kernel.patdiff(
        produce_unified_lines=false,
        output=Ascii,
        prev=pc_input("old", original),
        next=pc_input("new", modified),
      ),
    ),
    expected,
  )
}

// module%test [@name "python"] _

///|
let pc_py_prev : @kernel.DiffInput = pc_input("old.py", "print(5)")

///|
let pc_py_next : @kernel.DiffInput = pc_input(
  "new.py", "if True:\n    print(5)",
)

///|
fn pc_no_ansi_escapes(s : Bytes) -> Bool {
  !@bstr.contains(s, b("\u{1b}"))
}

///|
test "python: Ansi output generates a single line diff" {
  let expected =
    #|-1,1 +1,2
    #|␛[1;33m!|␛[22;39m␛[32mif True:␛[39m
    #|␛[1;33m!|␛[22;39m␛[7;32m    ␛[27;39mprint(5)
  pc_expect(
    pc_print(
      @kernel.patdiff(
        split_long_lines=false,
        produce_unified_lines=true,
        output=Ansi,
        prev=pc_py_prev,
        next=pc_py_next,
      ),
    ),
    expected,
  )
}

///|
test "python: Ascii is supported if [produce_unified_lines] is false" {
  let expected =
    #|-1,1 +1,2
    #|-|print(5)
    #|+|if True:
    #|+|    print(5)
  pc_expect(
    pc_print(
      @kernel.patdiff(
        split_long_lines=false,
        produce_unified_lines=false,
        output=Ascii,
        prev=pc_py_prev,
        next=pc_py_next,
      ),
    ),
    expected,
  )
}

///|
test "python: Ascii output contains no ANSI escapes" {
  assert_true(
    pc_no_ansi_escapes(
      @kernel.patdiff(
        output=Ascii,
        produce_unified_lines=false,
        prev=pc_py_prev,
        next=pc_py_next,
      ),
    ),
  )
}

///|
test "python: Ascii output contains no ANSI escapes (keep_ws false)" {
  assert_true(
    pc_no_ansi_escapes(
      @kernel.patdiff(
        output=Ascii,
        produce_unified_lines=false,
        keep_ws=false,
        prev=pc_py_prev,
        next=pc_py_next,
      ),
    ),
  )
}

///|
test "python: Ascii output contains no ANSI escapes (keep_ws true)" {
  assert_true(
    pc_no_ansi_escapes(
      @kernel.patdiff(
        output=Ascii,
        produce_unified_lines=false,
        keep_ws=true,
        prev=pc_py_prev,
        next=pc_py_next,
      ),
    ),
  )
}

///|
test "python: Ascii output contains no ANSI escapes (stripped rules)" {
  assert_true(
    pc_no_ansi_escapes(
      @kernel.patdiff(
        output=Ascii,
        produce_unified_lines=false,
        rules=@kernel.Rules::default().strip_styles(),
        prev=pc_py_prev,
        next=pc_py_next,
      ),
    ),
  )
}

///|
fn pc_test_moves(prev : String, next : String) -> String {
  let prev = pc_input("old", prev)
  let next = pc_input("new", next)
  // Override the default config to show moves better without colors
  let rules = @kernel.Rules::default()
  let removed_in_move = @kernel.Rule::new(pre=@kernel.Affix::new(b(">-")), [])
  let added_in_move = @kernel.Rule::new(pre=@kernel.Affix::new(b(">+")), [])
  let line_unified_in_move = @kernel.Rule::new(
    pre=@kernel.Affix::new(b(">!")),
    [],
  )
  let rules = { ..rules, removed_in_move, added_in_move, line_unified_in_move, }
  pc_print(
    @kernel.patdiff(
      rules~,
      find_moves=true,
      prev~,
      next~,
      output=Ascii,
      produce_unified_lines=false,
    ),
  )
}

///|
test "test a simple move" {
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
    #|-4,46 +4,46
    #|  tempus magna, ut semper lacus tincidunt at. Suspendisse et rutrum arcu. Aliquam
    #|  erat volutpat. Pellentesque pretium pellentesque elit, a consequat metus
    #|  placerat a. Praesent hendrerit euismod sem nec facilisis. Curabitur finibus ex
    #|  sagittis massa blandit, et dictum lectus lobortis. Sed fringilla fringilla
    #|  tortor vel finibus. Sed vel tortor pulvinar, fermentum quam non, blandit lorem.
    #|
    #|  Maecenas ac elit turpis. Nam ex turpis, ullamcorper et ultricies eu, pretium et
    #|  elit. Duis bibendum aliquet quam et tempor. Donec quis dapibus justo. Praesent
    #|  eget pellentesque nisi. Nulla vestibulum orci quis dui laoreet, eget posuere sem
    #|  interdum. Morbi ac sodales ligula. Proin arcu ipsum, venenatis id cursus et,
    #|  blandit eu mi. Sed iaculis egestas ligula, lacinia condimentum velit commodo
    #|  non. In eu elit convallis, tempus sapien sed, maximus purus. Sed vitae enim et
    #|  tellus accumsan bibendum eu vel turpis. Phasellus massa leo, eleifend vel
    #|  tincidunt ut, consequat et est. Duis quis condimentum ex. Etiam nec faucibus
    #|  lorem. Aliquam vehicula porta sapien, ut aliquam purus cursus vitae. Nullam at
    #|  ex vehicula, egestas sapien vitae, molestie ipsum.
    #|<|
    #|<|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|<|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|<|tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo
    #|<|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|<|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|<|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|  Cras non semper ante. Vivamus non nulla scelerisque, fermentum sem at, laoreet
    #|  est. Sed convallis, magna sit amet maximus sollicitudin, nulla metus sodales
    #|  eros, eu molestie arcu urna ut nunc. Pellentesque habitant morbi tristique
    #|  senectus et netus et malesuada fames ac turpis egestas. Morbi sollicitudin,
    #|  turpis sit amet ultricies interdum, urna nisl rhoncus tellus, id consectetur
    #|  urna risus ut arcu. Aliquam hendrerit eros id ex tempor vehicula. Nunc a pretium
    #|  risus. Nulla tincidunt, mauris eu pellentesque hendrerit, nisi nibh volutpat
    #|  sapien, vitae vehicula lacus tellus dictum augue. Pellentesque malesuada vitae
    #|  tellus lobortis laoreet. Donec fringilla lacinia nulla sit amet eleifend.
    #|  Suspendisse iaculis metus sed massa bibendum, quis consequat metus lacinia.
    #|  Etiam scelerisque odio nec pulvinar dapibus. Duis interdum interdum quam vel
    #|  dapibus. Quisque dapibus nisl quis magna accumsan, et lobortis magna eleifend.
    #|  Ut venenatis cursus diam, vel dictum augue interdum vitae. Ut scelerisque
    #|  condimentum augue, eget bibendum augue lacinia in.
    #|>|
    #|>|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|>|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|>|tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo
    #|>|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|>|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|>|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|  Aenean porta elit vitae pharetra dapibus. Duis a odio neque. Curabitur
    #|  ullamcorper enim ut metus luctus, eu blandit augue consectetur. Vestibulum
    #|  blandit lorem eget blandit fringilla. In et libero non lacus elementum pulvinar
    #|  id a orci. Maecenas porta urna mollis, egestas lacus id, feugiat nisi. Vivamus
    #|  imperdiet ornare dui eleifend semper. Integer erat ipsum, vestibulum a lobortis
    #|  eu, posuere in orci. Pellentesque gravida in purus eu ullamcorper. Nunc urna
    #|  tortor, hendrerit nec eleifend et, dapibus sed dolor.
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "test a move with a slight modification" {
  let prev =
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
    #|Suspendisse convallis justo vitae leo efficitur ultrices. Fusce ullamcorper nisl
    #|accumsan maximus ultricies. Donec eu orci feugiat, lacinia ipsum a, rhoncus
    #|augue. Nullam mollis, dolor in varius auctor, ex tortor dapibus quam, id
    #|consectetur ipsum nunc ac leo. Maecenas condimentum nunc sed convallis ultrices.
    #|Suspendisse semper hendrerit ante, quis convallis dui eleifend et. Duis dui
    #|risus, laoreet eu suscipit eget, pretium vitae risus. Lorem ipsum dolor sit
    #|amet, consectetur adipiscing elit. Proin bibendum consequat pharetra. Morbi
    #|scelerisque vitae tellus sodales mattis.
    #|
    #|Nunc maximus porttitor nulla sit amet porta. Aenean tellus dui, viverra nec
    #|congue vitae, posuere a erat. Vestibulum lectus nibh, gravida et orci at,
    #|gravida eleifend tellus. Vestibulum nec iaculis odio. Donec et dui quis orci
    #|gravida euismod non sed eros. Aliquam ipsum metus, tempus a risus molestie,
    #|maximus vestibulum nibh. Cras sit amet sagittis nunc. Donec bibendum eros
    #|maximus lacus imperdiet, ac mollis quam tristique. Nunc eleifend ullamcorper
    #|tincidunt. Ut ut pulvinar ante. Mauris gravida, arcu vitae suscipit ultrices,
    #|elit metus sagittis odio, at pretium leo leo in odio. Ut dictum mi ac purus
    #|ullamcorper finibus.
    #|
  let next =
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
    #|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|tincidunt lorem diam a nisi. Duis vehicula exe ace tortor sagittis, ac commodo
    #|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|Suspendisse convallis justo vitae leo efficitur ultrices. Fusce ullamcorper nisl
    #|accumsan maximus ultricies. Donec eu orci feugiat, lacinia ipsum a, rhoncus
    #|augue. Nullam mollis, dolor in varius auctor, ex tortor dapibus quam, id
    #|consectetur ipsum nunc ac leo. Maecenas condimentum nunc sed convallis ultrices.
    #|Suspendisse semper hendrerit ante, quis convallis dui eleifend et. Duis dui
    #|risus, laoreet eu suscipit eget, pretium vitae risus. Lorem ipsum dolor sit
    #|amet, consectetur adipiscing elit. Proin bibendum consequat pharetra. Morbi
    #|scelerisque vitae tellus sodales mattis.
    #|
    #|Nunc maximus porttitor nulla sit amet porta. Aenean tellus dui, viverra nec
    #|congue vitae, posuere a erat. Vestibulum lectus nibh, gravida et orci at,
    #|gravida eleifend tellus. Vestibulum nec iaculis odio. Donec et dui quis orci
    #|gravida euismod non sed eros. Aliquam ipsum metus, tempus a risus molestie,
    #|maximus vestibulum nibh. Cras sit amet sagittis nunc. Donec bibendum eros
    #|maximus lacus imperdiet, ac mollis quam tristique. Nunc eleifend ullamcorper
    #|tincidunt. Ut ut pulvinar ante. Mauris gravida, arcu vitae suscipit ultrices,
    #|elit metus sagittis odio, at pretium leo leo in odio. Ut dictum mi ac purus
    #|ullamcorper finibus.
    #|
  let expected =
    #|-1,57 +1,57
    #|
    #|  Maecenas ac elit turpis. Nam ex turpis, ullamcorper et ultricies eu, pretium et
    #|  elit. Duis bibendum aliquet quam et tempor. Donec quis dapibus justo. Praesent
    #|  eget pellentesque nisi. Nulla vestibulum orci quis dui laoreet, eget posuere sem
    #|  interdum. Morbi ac sodales ligula. Proin arcu ipsum, venenatis id cursus et,
    #|  blandit eu mi. Sed iaculis egestas ligula, lacinia condimentum velit commodo
    #|  non. In eu elit convallis, tempus sapien sed, maximus purus. Sed vitae enim et
    #|  tellus accumsan bibendum eu vel turpis. Phasellus massa leo, eleifend vel
    #|  tincidunt ut, consequat et est. Duis quis condimentum ex. Etiam nec faucibus
    #|  lorem. Aliquam vehicula porta sapien, ut aliquam purus cursus vitae. Nullam at
    #|  ex vehicula, egestas sapien vitae, molestie ipsum.
    #|<|
    #|<|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|<|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|<|tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo
    #|<|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|<|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|<|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|  Cras non semper ante. Vivamus non nulla scelerisque, fermentum sem at, laoreet
    #|  est. Sed convallis, magna sit amet maximus sollicitudin, nulla metus sodales
    #|  eros, eu molestie arcu urna ut nunc. Pellentesque habitant morbi tristique
    #|  senectus et netus et malesuada fames ac turpis egestas. Morbi sollicitudin,
    #|  turpis sit amet ultricies interdum, urna nisl rhoncus tellus, id consectetur
    #|  urna risus ut arcu. Aliquam hendrerit eros id ex tempor vehicula. Nunc a pretium
    #|  risus. Nulla tincidunt, mauris eu pellentesque hendrerit, nisi nibh volutpat
    #|  sapien, vitae vehicula lacus tellus dictum augue. Pellentesque malesuada vitae
    #|  tellus lobortis laoreet. Donec fringilla lacinia nulla sit amet eleifend.
    #|  Suspendisse iaculis metus sed massa bibendum, quis consequat metus lacinia.
    #|  Etiam scelerisque odio nec pulvinar dapibus. Duis interdum interdum quam vel
    #|  dapibus. Quisque dapibus nisl quis magna accumsan, et lobortis magna eleifend.
    #|  Ut venenatis cursus diam, vel dictum augue interdum vitae. Ut scelerisque
    #|  condimentum augue, eget bibendum augue lacinia in.
    #|
    #|  Aenean porta elit vitae pharetra dapibus. Duis a odio neque. Curabitur
    #|  ullamcorper enim ut metus luctus, eu blandit augue consectetur. Vestibulum
    #|  blandit lorem eget blandit fringilla. In et libero non lacus elementum pulvinar
    #|  id a orci. Maecenas porta urna mollis, egestas lacus id, feugiat nisi. Vivamus
    #|  imperdiet ornare dui eleifend semper. Integer erat ipsum, vestibulum a lobortis
    #|  eu, posuere in orci. Pellentesque gravida in purus eu ullamcorper. Nunc urna
    #|  tortor, hendrerit nec eleifend et, dapibus sed dolor.
    #|>|
    #|>|Suspendisse iaculis lacinia arcu a vehicula. Nunc eleifend fermentum iaculis.
    #|>|Duis dignissim, mi sit amet vehicula auctor, odio mauris consectetur lectus, ac
    #|>-tincidunt lorem diam a nisi. Duis vehicula ex ac tortor sagittis, ac commodo
    #|>+tincidunt lorem diam a nisi. Duis vehicula exe ace tortor sagittis, ac commodo
    #|>|lectus venenatis. Nam efficitur justo eros, et ornare neque aliquet ut. Duis
    #|>|vulputate nulla nunc, eget pellentesque diam aliquam at. Cras rhoncus orci at
    #|>|tortor posuere convallis sed sed risus. Quisque sed ipsum ex.
    #|
    #|  Suspendisse convallis justo vitae leo efficitur ultrices. Fusce ullamcorper nisl
    #|  accumsan maximus ultricies. Donec eu orci feugiat, lacinia ipsum a, rhoncus
    #|  augue. Nullam mollis, dolor in varius auctor, ex tortor dapibus quam, id
    #|  consectetur ipsum nunc ac leo. Maecenas condimentum nunc sed convallis ultrices.
    #|  Suspendisse semper hendrerit ante, quis convallis dui eleifend et. Duis dui
    #|  risus, laoreet eu suscipit eget, pretium vitae risus. Lorem ipsum dolor sit
    #|  amet, consectetur adipiscing elit. Proin bibendum consequat pharetra. Morbi
    #|  scelerisque vitae tellus sodales mattis.
    #|
    #|  Nunc maximus porttitor nulla sit amet porta. Aenean tellus dui, viverra nec
    #|  congue vitae, posuere a erat. Vestibulum lectus nibh, gravida et orci at,
    #|  gravida eleifend tellus. Vestibulum nec iaculis odio. Donec et dui quis orci
    #|  gravida euismod non sed eros. Aliquam ipsum metus, tempus a risus molestie,
    #|  maximus vestibulum nibh. Cras sit amet sagittis nunc. Donec bibendum eros
    #|  maximus lacus imperdiet, ac mollis quam tristique. Nunc eleifend ullamcorper
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "test we prefer more similar lines" {
  let prev =
    #|
    #|Some code that is going to get moved somewhere. Make it long so
    #|things are really similar. We only match on at least 3 lines
    #|so make it 3 lines long.
    #|a
    #|b
    #|c
    #|d
    #|e
    #|f
    #|
  let next =
    #|
    #|a
    #|b
    #|c
    #|Some code that is going to get moved somewhere. Make it long so
    #|things are really differs. We only match on at least 3 lines
    #|so make it 3 lines long.
    #|d
    #|e
    #|f
    #|Some code that is going to get moved somewhere. Make it long so
    #|things are really similar. We only match on at least 3 lines
    #|so make it 3 lines long.
    #|
  let expected =
    #|-1,10 +1,13
    #|
    #|<|Some code that is going to get moved somewhere. Make it long so
    #|<|things are really similar. We only match on at least 3 lines
    #|<|so make it 3 lines long.
    #|  a
    #|  b
    #|  c
    #|+|Some code that is going to get moved somewhere. Make it long so
    #|+|things are really differs. We only match on at least 3 lines
    #|+|so make it 3 lines long.
    #|  d
    #|  e
    #|  f
    #|>|Some code that is going to get moved somewhere. Make it long so
    #|>|things are really similar. We only match on at least 3 lines
    #|>|so make it 3 lines long.
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "test moves of match statements" {
  let prev =
    #|
    #|let result =
    #|  (match variable with
    #|  | Case1 case1 ->
    #|    let a = b in
    #|    let double = case1 * case1 in
    #|    a + double
    #|  | Case2 case2 ->
    #|    let foo = case2 ^ "-something" in
    #|    let bar = String.length foo in
    #|    String.is_substring (bar ^ Int.to_string) ~substring
    #|  | Case3 case3 ->
    #|      let one_third = case3 *. 0.3333 in
    #|      let inverse = 1. -. one_third in
    #|      Global.log.debug_s [%sexp "Case3"];
    #|      let sqrt = sqrt inverse in
    #|      let sum = ref 0. in
    #|      List.iter [ 1; 2; 3] ~f:(fun _index ->
    #|        sum := !sum +. sqrt;
    #|      );
    #|      Percentage.of_float !sum) in
    #|fetch result
    #|
  let next =
    #|
    #|let result =
    #|  (match variable with
    #|  | Case3 case3 ->
    #|      let one_third = case3 *. 0.3333 in
    #|      let inverse = 1. -. one_third in
    #|      Global.log.debug_s [%sexp "Case3"];
    #|      let sqrt = sqrt inverse in
    #|      let sum = ref 0. in
    #|      List.iter [ 1; 2; 3] ~f:(fun _index ->
    #|        sum := !sum +. sqrt;
    #|      );
    #|      Percentage.of_float !sum
    #|  | Case1 case1 ->
    #|    let a = b in
    #|    let double = case1 * case1 in
    #|    a + double
    #|  | Case2 case2 ->
    #|    let foo = case2 ^ "-something" in
    #|    let bar = String.length foo in
    #|    String.is_substring (bar ^ Int.to_string) ~substring) in
    #|fetch result
    #|
  let expected =
    #|-1,22 +1,22
    #|
    #|  let result =
    #|    (match variable with
    #|<|  | Case1 case1 ->
    #|<|    let a = b in
    #|<|    let double = case1 * case1 in
    #|<|    a + double
    #|<|  | Case2 case2 ->
    #|<|    let foo = case2 ^ "-something" in
    #|<|    let bar = String.length foo in
    #|<|    String.is_substring (bar ^ Int.to_string) ~substring
    #|    | Case3 case3 ->
    #|        let one_third = case3 *. 0.3333 in
    #|        let inverse = 1. -. one_third in
    #|        Global.log.debug_s [%sexp "Case3"];
    #|        let sqrt = sqrt inverse in
    #|        let sum = ref 0. in
    #|        List.iter [ 1; 2; 3] ~f:(fun _index ->
    #|          sum := !sum +. sqrt;
    #|        );
    #|-|      Percentage.of_float !sum) in
    #|+|      Percentage.of_float !sum
    #|>|  | Case1 case1 ->
    #|>|    let a = b in
    #|>|    let double = case1 * case1 in
    #|>|    a + double
    #|>|  | Case2 case2 ->
    #|>|    let foo = case2 ^ "-something" in
    #|>|    let bar = String.length foo in
    #|>-    String.is_substring (bar ^ Int.to_string) ~substring
    #|>+    String.is_substring (bar ^ Int.to_string) ~substring) in
    #|  fetch result
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "make sure we don't use a replace as a move" {
  let prev =
    #|
    #|module Stable : sig
    #|  module Row : sig
    #|    module V1 : sig
    #|      type t
    #|    end
    #|
    #|    module V2 : sig
    #|      type t
    #|    end
    #|
    #|    module V3 : sig
    #|      type t = Row.t
    #|    end
    #|
    #|    module V4 : sig
    #|      type t =
    #|        { first_name : string
    #|        ; last_name : string
    #|        ; age : int
    #|        ; address : string
    #|        ; favorite_food : string
    #|        }
    #|    end
    #|  end
    #|
    #|  module V1 : sig
    #|    type t [@@deriving bin_io, sexp_of, compare]
    #|  end
    #|
    #|  module V2 : sig
    #|    type t [@@deriving bin_io, sexp_of, compare]
    #|
    #|    val to_v1 : t -> V1.t
    #|  end
    #|
    #|  module V3 : sig
    #|    type nonrec t = t [@@deriving bin_io, sexp_of, compare]
    #|
    #|    val to_v2 : t -> V2.t
    #|  end
    #|
    #|  module V4 : sig
    #|    type t = Row.V4.t list [@@deriving bin_io, sexp_of, compare]
    #|
    #|    val to_v3 : t -> V3.t
    #|  end
    #|end
    #|
  let next =
    #|
    #|module Stable : sig
    #|  module Row : sig
    #|    module V1 : sig
    #|      type t
    #|    end
    #|
    #|    module V2 : sig
    #|      type t
    #|    end
    #|
    #|    module V3 : sig
    #|      type t
    #|    end
    #|
    #|    module V4 : sig
    #|      type t = Row.t
    #|    end
    #|  end
    #|
    #|  module V1 : sig
    #|    type t [@@deriving bin_io, sexp_of, compare]
    #|  end
    #|
    #|  module V2 : sig
    #|    type t [@@deriving bin_io, sexp_of, compare]
    #|
    #|    val to_v1 : t -> V1.t
    #|  end
    #|
    #|  module V3 : sig
    #|    type t [@@deriving bin_io, sexp_of, compare]
    #|
    #|    val to_v2 : t -> V2.t
    #|  end
    #|
    #|  module V4 : sig
    #|    type nonrec t = t [@@deriving bin_io, sexp_of, compare]
    #|
    #|    val to_v3 : t -> V3.t
    #|  end
    #|end
    #|
  let expected =
    #|-1,48 +1,42
    #|
    #|  module Stable : sig
    #|    module Row : sig
    #|      module V1 : sig
    #|        type t
    #|      end
    #|
    #|      module V2 : sig
    #|        type t
    #|      end
    #|
    #|      module V3 : sig
    #|-|      type t = Row.t
    #|-|    end
    #|-|
    #|-|    module V4 : sig
    #|-|      type t =
    #|-|        { first_name : string
    #|-|        ; last_name : string
    #|-|        ; age : int
    #|-|        ; address : string
    #|-|        ; favorite_food : string
    #|-|        }
    #|+|      type t
    #|+|    end
    #|+|
    #|+|    module V4 : sig
    #|+|      type t = Row.t
    #|      end
    #|    end
    #|
    #|    module V1 : sig
    #|      type t [@@deriving bin_io, sexp_of, compare]
    #|    end
    #|
    #|    module V2 : sig
    #|      type t [@@deriving bin_io, sexp_of, compare]
    #|
    #|      val to_v1 : t -> V1.t
    #|    end
    #|
    #|    module V3 : sig
    #|-|    type nonrec t = t [@@deriving bin_io, sexp_of, compare]
    #|-|
    #|-|    val to_v2 : t -> V2.t
    #|-|  end
    #|-|
    #|-|  module V4 : sig
    #|-|    type t = Row.V4.t list [@@deriving bin_io, sexp_of, compare]
    #|+|    type t [@@deriving bin_io, sexp_of, compare]
    #|+|
    #|+|    val to_v2 : t -> V2.t
    #|+|  end
    #|+|
    #|+|  module V4 : sig
    #|+|    type nonrec t = t [@@deriving bin_io, sexp_of, compare]
    #|
    #|      val to_v3 : t -> V3.t
    #|    end
    #|  end
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "don't include deletions or additions on the edges of moves" {
  let prev =
    #|
    #|        1
    #|        2
    #|        3
    #|        to_delete
    #|        5
    #|        6
    #|        7
    #|        8
    #|        9
    #|        10
    #|        11
    #|        12
    #|        13
    #|        14
    #|        15
    #|
  let next =
    #|
    #|        1
    #|        2
    #|        3
    #|        8
    #|        9
    #|        10
    #|        11
    #|        12
    #|        5
    #|        6
    #|        7
    #|        added
    #|        13
    #|        14
    #|        15
    #|
  let expected =
    #|-1,16 +1,16
    #|
    #|          1
    #|          2
    #|          3
    #|-|        to_delete
    #|<|        5
    #|<|        6
    #|<|        7
    #|          8
    #|          9
    #|          10
    #|          11
    #|          12
    #|>|        5
    #|>|        6
    #|>|        7
    #|+|        added
    #|          13
    #|          14
    #|          15
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "a move plus not keeping whitespace hides deleted empty lines" {
  let prev =
    #|
    #|a
    #|b
    #|c
    #|d
    #|e
    #|f
    #|g
    #|h
    #|i
    #|j
    #|k
    #|l
    #|
    #|section
    #|to
    #|move
    #|
    #|m
    #|n
    #|o
    #|p
    #|
  let next =
    #|
    #|a
    #|b
    #|c
    #|section
    #|to
    #|move
    #|d
    #|e
    #|f
    #|g
    #|h
    #|i
    #|j
    #|k
    #|l
    #|m
    #|n
    #|o
    #|p
    #|
  let expected =
    #|-1,22 +1,20
    #|
    #|  a
    #|  b
    #|  c
    #|>|section
    #|>|to
    #|>|move
    #|  d
    #|  e
    #|  f
    #|  g
    #|  h
    #|  i
    #|  j
    #|  k
    #|  l
    #|<|section
    #|<|to
    #|<|move
    #|  m
    #|  n
    #|  o
    #|  p
  pc_expect(pc_test_moves(prev, next), expected)
}

///|
test "test moves when nesting changes" {
  let prev =
    #|
    #|let foo = 3
    #|
    #|let bar = 4
    #|
    #|let rec test x =
    #|  if x > 0
    #|  then test (x-1)
    #|  else x
    #|;;
    #|
    #|let message =
    #|  "This is a message"
    #|;;
    #|
    #|let call_the_server () =
    #|  Server.call {
    #|      user;
    #|      password;
    #|      request
    #|  }
    #|;;
    #|
    #|let read_the_file () =
    #|  Reader.load_sexp "some-really-long file-path.sexp"
    #|;;
    #|
  let next =
    #|
    #|module Server = struct
    #|  let call_the_server () =
    #|    Server.call {
    #|        user;
    #|        password;
    #|        request
    #|    }
    #|  ;;
    #|
    #|  let read_the_file () =
    #|    Reader.load_sexp
    #|       "some-really-long file-path.sexp"
    #|  ;;
    #|end
    #|
    #|let foo = 3
    #|
    #|let bar = 4
    #|
    #|let rec test x =
    #|  if x > 0
    #|  then test (x-1)
    #|  else x
    #|;;
    #|
    #|let message =
    #|  "This is a message"
    #|;;
    #|
    #|include Server
    #|
  let expected =
    #|-1,26 +1,31
    #|+|
    #|+|module Server = struct
    #|>|  let call_the_server () =
    #|>|    Server.call {
    #|>|        user;
    #|>|        password;
    #|>|        request
    #|>|    }
    #|>|  ;;
    #|>|
    #|>|  let read_the_file () =
    #|>-  Reader.load_sexp "some-really-long file-path.sexp"
    #|>+    Reader.load_sexp
    #|>+       "some-really-long file-path.sexp"
    #|>|  ;;
    #|+|end
    #|
    #|  let foo = 3
    #|
    #|  let bar = 4
    #|
    #|  let rec test x =
    #|    if x > 0
    #|    then test (x-1)
    #|    else x
    #|  ;;
    #|
    #|  let message =
    #|    "This is a message"
    #|  ;;
    #|
    #|<|let call_the_server () =
    #|<|  Server.call {
    #|<|      user;
    #|<|      password;
    #|<|      request
    #|<|  }
    #|<|;;
    #|<|
    #|<|let read_the_file () =
    #|<|  Reader.load_sexp "some-really-long file-path.sexp"
    #|<|;;
    #|+|include Server
  pc_expect(pc_test_moves(prev, next), expected)
}

// The two [Quickcheck] tests. [Quickcheck] isn't available, so these use a small
// deterministic generator and a fixed number of trials.

///|
priv struct PcRng {
  mut state : Int32
}

///|
fn PcRng::int_incl(self : PcRng, lo : Int32, hi : Int32) -> Int32 {
  self.state = (self.state * 1103515245 + 12345) & 0x7fffffff
  lo + (self.state >> 8) % (hi - lo + 1)
}

///|
fn PcRng::alpha_string(self : PcRng) -> Bytes {
  let len = self.int_incl(1, 8)
  let buf = StringBuilder()
  for _ in 0..<len {
    let n = self.int_incl(0, 51)
    let c = if n < 26 { 'a'.to_int() + n } else { 'A'.to_int() + n - 26 }
    buf.write_char(Int32::unsafe_to_char(c))
  }
  b(buf.to_string())
}

///|
priv enum PcAction {
  Move(start~ : Int32, length~ : Int32, to_~ : Int32)
  Delete(start~ : Int32, length~ : Int32)
  Insert(start~ : Int32, contents~ : Bytes)
}

///|
fn PcAction::gen(rng : PcRng, str_length~ : Int32) -> PcAction {
  match rng.int_incl(0, 2) {
    0 => {
      let start = rng.int_incl(0, str_length)
      let length = rng.int_incl(0, str_length)
      let to_ = rng.int_incl(0, str_length)
      Move(start~, length~, to_~)
    }
    1 => {
      let start = rng.int_incl(0, str_length)
      let length = rng.int_incl(0, str_length)
      Delete(start~, length~)
    }
    _ => {
      let start = rng.int_incl(0, str_length)
      let contents = rng.alpha_string()
      Insert(start~, contents~)
    }
  }
}

///|
fn pc_prefix(s : Bytes, n : Int32) -> Bytes {
  @bstr.sub(s, 0, @cmp.minimum(n, s.length()))
}

///|
fn pc_drop_prefix(s : Bytes, n : Int32) -> Bytes {
  @bstr.sub(s, @cmp.minimum(n, s.length()), s.length())
}

///|
/// All of these actions just clamp their indices if the are out of range.
fn PcAction::apply(self : PcAction, str : Bytes) -> Bytes {
  match self {
    Move(start~, length~, to_~) => {
      let prefix = pc_prefix(str, start)
      let suffix = pc_drop_prefix(str, start + length)
      let to_move = pc_prefix(pc_drop_prefix(str, start), length)
      let before_insert = prefix + suffix
      let prefix = pc_prefix(before_insert, to_)
      let suffix = pc_drop_prefix(before_insert, to_)
      prefix + to_move + suffix
    }
    Delete(start~, length~) =>
      pc_prefix(str, start) + pc_drop_prefix(str, start + length)
    Insert(start~, contents~) =>
      pc_prefix(str, start) + contents + pc_drop_prefix(str, start)
  }
}

///|
/// Diffs with moves and checks that both inputs can be recovered from the
/// hunks. Gives the error message if they can't.
fn pc_recovery_error(prev : Array[Bytes], next : Array[Bytes]) -> String? {
  let hunks = @kernel.diff(
    context=-1,
    line_big_enough=3,
    keep_ws=false,
    find_moves=true,
    prev~,
    next~,
  )
  let recover_prev = []
  let recover_next = []
  for hunk in hunks {
    for range in @pd.prev_only(hunk.ranges) {
      match range {
        Prev(prev, _) => recover_prev.push_iter(prev.iter())
        Same(same) => recover_prev.push_iter(same.iter().map(p => p.0))
        _ => return Some("unexpected range in prev_only")
      }
    }
    for range in @pd.next_only(hunk.ranges) {
      match range {
        Next(next, _) => recover_next.push_iter(next.iter())
        Same(same) => recover_next.push_iter(same.iter().map(p => p.1))
        _ => return Some("unexpected range in next_only")
      }
    }
  }
  // Avoid comparing duplicate newlines at the end of the strings
  let strip = (lines : Array[Bytes]) => {
    @bstr.strip(@bstr.concat(lines, sep=b"\n"))
  }
  if strip(recover_prev) != strip(prev) {
    return Some(
      "could not recover prev:\n\{shown(strip(recover_prev))}\n(expected:\n\{shown(strip(prev))})",
    )
  }
  if strip(recover_next) != strip(next) {
    return Some(
      "could not recover next:\n\{shown(strip(recover_next))}\n(expected:\n\{shown(strip(next))})",
    )
  }
  None
}

///|
/// Greedily removes lines while the failure persists.
fn pc_shrink(
  prev : Array[Bytes],
  next : Array[Bytes],
) -> (Array[Bytes], Array[Bytes]) {
  let mut prev = prev
  let mut next = next
  let mut progress = true
  while progress {
    progress = false
    for i in 0..<prev.length() {
      if i >= prev.length() {
        break
      }
      let candidate = [..prev[:i], ..prev[i + 1:]]
      if pc_recovery_error(candidate, next) is Some(_) {
        prev = candidate
        progress = true
      }
    }
    for i in 0..<next.length() {
      if i >= next.length() {
        break
      }
      let candidate = [..next[:i], ..next[i + 1:]]
      if pc_recovery_error(prev, candidate) is Some(_) {
        next = candidate
        progress = true
      }
    }
  }
  (prev, next)
}

///|
test "ensure we can always recover the original content if there are moves" {
  let rng = PcRng::{ state: 20240607, }
  for trial in 0..<1000 {
    let prev = Array::makei(50, _ => rng.alpha_string())
    let prev_string = @bstr.concat(prev, sep=b"\n")
    let mut str_length = 0
    for s in prev {
      str_length += s.length()
    }
    let actions = Array::makei(5, _ => PcAction::gen(rng, str_length~))
    let mut next_string = prev_string
    for action in actions {
      next_string = action.apply(next_string)
    }
    let next = @bstr.split_lines(next_string)
    if pc_recovery_error(prev, next) is Some(_) {
      let (prev, next) = pc_shrink(prev, next)
      let error = pc_recovery_error(prev, next).unwrap()
      fail(
        "trial \{trial}: \{error}\nshrunk to prev=\{prev.map(l => shown(l)).join(",")} next=\{next.map(l => shown(l)).join(",")}",
      )
    }
  }
}

///|
test "ensure that our refinement heuristic does not drop any changes" {
  // To trigger the refinement heuristic we need all lines to be different and
  // there is at at least one word shared between the two.
  let rng = PcRng::{ state: 4242, }
  for trial in 0..<50 {
    let lines_prev = rng.int_incl(200, 500)
    let lines_next = rng.int_incl(200, 500)
    let unique_word_prev_line = rng.int_incl(0, lines_prev - 1)
    let unique_word_next_line = rng.int_incl(0, lines_next - 1)
    let unique_word = "uniqueword"
    let mut prev_words = 0
    let prev = Array::makei(lines_prev, line_idx => {
      let words = []
      for word_idx in 0..<5 {
        if line_idx == unique_word_prev_line && word_idx == 0 {
          words.push(unique_word)
        } else {
          words.push("prevword" + prev_words.to_string())
          prev_words += 1
        }
      }
      b(words.join(" "))
    })
    let mut next_words = 0
    let next = Array::makei(lines_next, line_idx => {
      let words = []
      for word_idx in 0..<5 {
        if line_idx == unique_word_next_line && word_idx == 0 {
          words.push(unique_word)
        } else {
          words.push("nextword" + next_words.to_string())
          next_words += 1
        }
      }
      b(words.join(" "))
    })
    let prev_string = @bstr.concat(prev, sep=b"\n")
    let next_string = @bstr.concat(next, sep=b"\n")
    let hunks = @kernel.diff(
      context=-1,
      line_big_enough=3,
      keep_ws=false,
      find_moves=true,
      prev~,
      next~,
    )
    let hunks = @kernel.refine_structured(
      produce_unified_lines=false,
      keep_ws=false,
      split_long_lines=false,
      interleave=false,
      word_big_enough=@kernel.DEFAULT_WORD_BIG_ENOUGH,
      hunks,
    )
    let text = (line : Array[(@kernel.Tag, Bytes)]) => {
      @bstr.concat(line.map(p => p.1))
    }
    let recover_prev = []
    let recover_next = []
    for hunk in hunks {
      for range in @pd.prev_only(hunk.ranges) {
        match range {
          Prev(prev, _) => recover_prev.push_iter(prev.iter().map(text))
          Same(same) => recover_prev.push_iter(same.iter().map(p => text(p.0)))
          _ => fail("trial \{trial}: unexpected range")
        }
      }
      for range in @pd.next_only(hunk.ranges) {
        match range {
          Next(next, _) => recover_next.push_iter(next.iter().map(text))
          Same(same) => recover_next.push_iter(same.iter().map(p => text(p.1)))
          _ => fail("trial \{trial}: unexpected range")
        }
      }
    }
    let recover_prev = @bstr.strip(@bstr.concat(recover_prev, sep=b"\n"))
    let recover_next = @bstr.strip(@bstr.concat(recover_next, sep=b"\n"))
    if recover_prev != @bstr.strip(prev_string) {
      fail("trial \{trial}: refinement dropped changes while recovering prev")
    }
    if recover_next != @bstr.strip(next_string) {
      fail("trial \{trial}: refinement dropped changes while recovering next")
    }
  }
}
