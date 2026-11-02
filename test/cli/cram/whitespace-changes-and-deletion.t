Test whitespace changes and deletion.

  $ set -o pipefail

  $ mkdir prev next

  $ cat > prev/file <<'EOF'
  >
  >     assert (
  >       Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));
  >     assert (
  >       Int.( = )
  >         (Set.length t.by_varying_usage)
  >         (Hashtbl.length t.bucket_id_to_keys)))
  > EOF

  $ cat > next/file <<'EOF'
  >
  >   assert (Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));
  >   assert (
  >     Int.( = ) (Set.length t.by_varying_usage) (Hashtbl.length t.bucket_id_to_keys))
  > EOF

default

  $ patdiff -default prev next | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,7 +1,4(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:green fg:black)+|(bg:default fg:green)  assert (Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));(fg:default)
  (bg:gray fg:black) |(bg:default fg:default)  assert (
  (bg:yellow fg:black)!|(bg:default fg:default)      Int.( = ) (Set.length t.by_varying_usage) ((fg:red)Set.length t.by_constant_usage));(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)    assert ((fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)      Int.( = )(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)        (Set.length t.by_varying_usage)(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)        ((fg:default)Hashtbl.length t.bucket_id_to_keys(fg:red))(fg:default)))
  [1]

-no-semantic-cleanup

  $ patdiff -default prev next -no-semantic-cleanup | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,7 +1,4(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:green fg:black)+|(bg:default fg:green)  assert (Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));(fg:default)
  (bg:gray fg:black) |(bg:default fg:default)  assert (
  (bg:yellow fg:black)!|(bg:default fg:default)      Int.( = ) (Set.length t.by_varying_usage) ((fg:red)Set.length t.by_constant_usage));(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)    assert ((fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)      Int.( = )(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)        (Set.length t.by_varying_usage)(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red)        ((fg:default)Hashtbl.length t.bucket_id_to_keys(fg:red))(fg:default)))
  [1]

The diff gets much better if I add a newline to both inputs.

  $ cat > prev/file <<'EOF'
  >
  >     assert (
  >       Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));
  >
  >     assert (
  >       Int.( = )
  >         (Set.length t.by_varying_usage)
  >         (Hashtbl.length t.bucket_id_to_keys)))
  > EOF

  $ cat > next/file <<'EOF'
  >
  >   assert (Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));
  >
  >   assert (
  >     Int.( = ) (Set.length t.by_varying_usage) (Hashtbl.length t.bucket_id_to_keys))
  > EOF

with extra newlines

  $ patdiff -default prev next | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,8 +1,5(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:gray fg:black) |(bg:default fg:default)  assert (Int.( = ) (Set.length t.by_varying_usage) (Set.length t.by_constant_usage));
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:gray fg:black) |(bg:default fg:default)  assert (
  (bg:yellow fg:black)!|(bg:default fg:default)      Int.( = )
  (bg:yellow fg:black)!|(bg:default fg:default)        (Set.length t.by_varying_usage)
  (bg:yellow fg:black)!|(bg:default fg:default)        (Hashtbl.length t.bucket_id_to_keys(fg:red))(fg:default)))
  [1]
