///|
/// Upstream's `test`: both inputs are stripped, and the result must not depend
/// on the order of the arguments.
fn skw_test(
  file1 : String,
  lines1 : String,
  file2 : String,
  lines2 : String,
) -> String raise {
  let prev = @kernel.DiffInput::of_string(
    file1,
    @bstr.to_string(@bstr.strip(b(lines1))),
  )
  let next = @kernel.DiffInput::of_string(
    file2,
    @bstr.to_string(@bstr.strip(b(lines2))),
  )
  let should_keep_whitespace = @kernel.should_keep_whitespace(prev~, next~)
  // [for_diff] should be symmetric.
  assert_eq(
    should_keep_whitespace,
    @kernel.should_keep_whitespace(prev=next, next=prev),
  )
  "(should_keep_whitespace \{should_keep_whitespace})"
}

///|
fn skw_test1(file1 : String, contents1 : String) -> String raise {
  skw_test(file1, contents1, file1, contents1)
}

///|
test ".txt vs .py" {
  let python =
    #|
    #|from __future__ import division
    #|print 8/7
    #|
  let expected =
    #|(should_keep_whitespace true)
  assert_eq(
    skw_test("not_python.txt", "not a python file", "is_python.py", python),
    expected,
  )
}

///|
test "#!/bin/python" {
  let contents =
    #|
    #|#!/bin/python
    #|print "foo"
    #|
  let expected =
    #|(should_keep_whitespace true)
  assert_eq(skw_test1("python.py", contents), expected)
}

///|
test "#!/usr/bin/env python3" {
  let contents =
    #|
    #|#!/usr/bin/env python3
    #|print "foo"
    #|
  let expected =
    #|(should_keep_whitespace true)
  assert_eq(skw_test1("python.py", contents), expected)
}

///|
test "#!/bin/bash" {
  let contents =
    #|
    #|#!/bin/bash
    #|echo foo
    #|
  let expected =
    #|(should_keep_whitespace false)
  assert_eq(skw_test1("bash.sh", contents), expected)
}

///|
test "f#" {
  let contents =
    #|
    #|// Learn more about F# at http://fsharp.org
    #|
    #|open System
    #|
    #|[<EntryPoint>]
    #|let main argv =
    #|    printfn "Hello World from F#!"
    #|    0 // return an integer exit code
    #|
  let expected =
    #|(should_keep_whitespace true)
  assert_eq(skw_test1("fsharp.fs", contents), expected)
}
