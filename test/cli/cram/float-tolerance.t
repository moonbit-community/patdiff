Test -float-tolerance (including the abbreviation -float-tol).

  $ set -o pipefail

  $ mkdir prev next

First case.

  $ cat > prev/file <<'EOF'
  >
  >  foo
  >  bar
  >  bax
  >  baz
  > EOF

  $ cat > next/file <<'EOF'
  >
  >  foo
  >  bar
  >  baz
  > EOF

  $ echo "====== strict ======"
  ====== strict ======

  $ patdiff -default prev next -float-tol 0x -ascii | ansi_text visualize -minimize
  ------ prev/file
  ++++++ next/file
  @|-1,5 +1,4 ============================================================
   |
   | foo
   | bar
  -| bax
   | baz
  [1]

  $ echo "====== 10% ======"
  ====== 10% ======

  $ patdiff -default prev next -float-tol 10% -ascii | ansi_text visualize -minimize
  ------ prev/file
  ++++++ next/file
  @|-1,5 +1,4 ============================================================
   |
   | foo
   | bar
  -| bax
   | baz
  [1]

Second case.

  $ cat > prev/file <<'EOF'
  > ((apples 12345678 23456789))
  >  (bananas (09:30:00.000000 16:00:00.000000))
  >  (clementines 10s) (durian 50ms)
  >  (elderberries 1s) (figs 2s)
  >  (grapes 2)
  >  (huckleberries 4096) (i_don't_know_any_fruit_starting_with_i 100ms)
  >  (jujubes 50ms) (kiwis 1000000)
  >  (limes 30)
  >  (mangos 10000)
  >  (nectarines 1.66667m)
  >  (oranges 1.66667m) (persimmons 17:15:00.000000)
  >  (quinces ((size 50000) (shelf_life 50s)))
  >  (raspberries true)
  >  (strawberries (are_red Surprisingly_not_always))
  >  (tamarind ())
  >  (ugli_fruits 30s))
  > EOF

  $ cat > next/file <<'EOF'
  > ((apples 12345678 23456788))
  >  (bananas (09:30:00.000000 15:59:00.000000))
  >  (clementines 10s) (durian 50ms)
  >  (elderberries 1s) (figs 2s)
  >  (grapes 2)
  >  (huckleberries 8192) (i_don't_know_any_fruit_starting_with_i 100ms)
  >  (jujubes 50ms) (kiwis 1000000)
  >  (limes 32)
  >  (mangos 10000)
  >  (nectarines 1.667m)
  >  (oranges 1.66667m) (persimmons 17:15:00.000000)
  >  (quinces ((size 49000) (shelf_life 50s)))
  >  (raspberries true)
  >  (strawberries (are_red Surprisingly_not_always))
  >  (tamarind ())
  >  (ugli_fruits 32s))
  > EOF

  $ echo "====== strict ======"
  ====== strict ======

  $ patdiff -default prev next -float-tol 0x -ascii | ansi_text visualize -minimize
  ------ prev/file
  ++++++ next/file
  @|-1,16 +1,16 ============================================================
  -|((apples 12345678 23456789))
  -| (bananas (09:30:00.000000 16:00:00.000000))
  +|((apples 12345678 23456788))
  +| (bananas (09:30:00.000000 15:59:00.000000))
   | (clementines 10s) (durian 50ms)
   | (elderberries 1s) (figs 2s)
   | (grapes 2)
  -| (huckleberries 4096) (i_don't_know_any_fruit_starting_with_i 100ms)
  +| (huckleberries 8192) (i_don't_know_any_fruit_starting_with_i 100ms)
   | (jujubes 50ms) (kiwis 1000000)
  -| (limes 30)
  +| (limes 32)
   | (mangos 10000)
  -| (nectarines 1.66667m)
  +| (nectarines 1.667m)
   | (oranges 1.66667m) (persimmons 17:15:00.000000)
  -| (quinces ((size 50000) (shelf_life 50s)))
  +| (quinces ((size 49000) (shelf_life 50s)))
   | (raspberries true)
   | (strawberries (are_red Surprisingly_not_always))
   | (tamarind ())
  -| (ugli_fruits 30s))
  +| (ugli_fruits 32s))
  [1]

  $ echo "====== 10% ======"
  ====== 10% ======

  $ patdiff -default prev next -float-tol 10% -ascii | ansi_text visualize -minimize
  ------ prev/file
  ++++++ next/file
  @|-1,16 +1,16 ============================================================
   |((apples 12345678 23456788))
  -| (bananas (09:30:00.000000 16:00:00.000000))
  +| (bananas (09:30:00.000000 15:59:00.000000))
   | (clementines 10s) (durian 50ms)
   | (elderberries 1s) (figs 2s)
   | (grapes 2)
  -| (huckleberries 4096) (i_don't_know_any_fruit_starting_with_i 100ms)
  +| (huckleberries 8192) (i_don't_know_any_fruit_starting_with_i 100ms)
   | (jujubes 50ms) (kiwis 1000000)
   | (limes 32)
   | (mangos 10000)
   | (nectarines 1.667m)
   | (oranges 1.66667m) (persimmons 17:15:00.000000)
   | (quinces ((size 49000) (shelf_life 50s)))
   | (raspberries true)
   | (strawberries (are_red Surprisingly_not_always))
   | (tamarind ())
   | (ugli_fruits 32s))
  [1]
