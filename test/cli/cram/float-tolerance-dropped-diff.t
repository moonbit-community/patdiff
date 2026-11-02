Regression test for a case where we used to drop the first line of this diff.

  $ set -o pipefail

  $ mkdir prev next

  $ cat > prev/file <<'EOF'
  >
  > ((foo (1 2))
  >  (bar 0.5%))
  > EOF

  $ cat > next/file <<'EOF'
  >
  > ()
  > EOF

default

  $ patdiff -default prev next | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,3 +1,2(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:yellow fg:black)!|(bg:default fg:default)((fg:red)(foo (1 2))(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red) (bar 0.5%)(fg:default))
  [1]

-float-tolerance 0x

  $ patdiff -default prev next -float-tolerance 0x | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,3 +1,2(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:yellow fg:black)!|(bg:default fg:default)((fg:red)(foo (1 2))(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red) (bar 0.5%)(fg:default))
  [1]

-float-tolerance 0x -no-semantic-cleanup

  $ patdiff -default prev next -float-tolerance 0x -no-semantic-cleanup | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,3 +1,2(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:yellow fg:black)!|(bg:default fg:default)((fg:red)(foo (1 2))(fg:default)
  (bg:yellow fg:black)!|(bg:default fg:red) (bar 0.5%)(fg:default))
  [1]
