Test -exclude and -include on directories.

  $ set -o pipefail

  $ mkdir prev next

  $ printf 'prev\n' > prev/foo; printf 'next\n' > next/foo

  $ printf 'prev\n' > prev/bar; printf 'next\n' > next/bar

  $ printf 'prev\n' > prev/baz; printf 'next\n' > next/baz

patdiff

  $ patdiff -default prev next -ascii | ansi_text visualize -minimize
  ------ prev/bar
  ++++++ next/bar
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  ------ prev/baz
  ++++++ next/baz
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  ------ prev/foo
  ++++++ next/foo
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  [1]

patdiff -exclude

  $ patdiff -default prev next -ascii -exclude bar | ansi_text visualize -minimize
  ------ prev/baz
  ++++++ next/baz
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  ------ prev/foo
  ++++++ next/foo
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  [1]

patdiff -include

  $ patdiff -default prev next -ascii -include 'bar|baz' | ansi_text visualize -minimize
  ------ prev/bar
  ++++++ next/bar
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  ------ prev/baz
  ++++++ next/baz
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  [1]

patdiff -include -exclude

  $ patdiff -default prev next -ascii -include 'bar|baz' -exclude baz | ansi_text visualize -minimize
  ------ prev/bar
  ++++++ next/bar
  @|-1,1 +1,1 ============================================================
  -|prev
  +|next
  [1]
