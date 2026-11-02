Test patdiff-git-wrapper. This warns of obvious mistakes, like silently changing the
calling convention without updating the script.

  $ git init -q

  $ git config user.email nobody@localhost

  $ git config user.name nobody

  $ printf 'foo bar baz\n' > foo

  $ git add foo

  $ git commit -a -m z -q

  $ printf 'foo baz quux\n' > foo

  $ patdiff -make-config .patdiff
  Default configuration written to .patdiff

  $ export HOME=.

Standard git diff.

  $ git diff
  diff --git a/foo b/foo
  index 1aeaedb..434ebd4 100644
  --- a/foo
  +++ b/foo
  @@ -1 +1 @@
  -foo bar baz
  +foo baz quux

Diff according to instructions in the script.

  $ export GIT_EXTERNAL_DIFF=patdiff-git-wrapper

  $ git diff | ansi_text visualize -minimize
  (+bold)patdiff -git a/foo b/foo
  (+bold)index 1aeaedb..0000000 100644
  (+bold fg:red)------ (fg:default) a/foo(-weight)
  (+bold fg:green)++++++ (fg:default) b/foo(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,1(-weight) ============================================================
  (bg:red fg:black)-|(off fg:gray-12)foo(fg:red) bar(fg:gray-12) baz(fg:default)
  (bg:green fg:black)+|(off)foo baz(fg:green) quux(fg:default)
