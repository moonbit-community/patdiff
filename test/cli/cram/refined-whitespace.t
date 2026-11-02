Test the display of whitespace with -keep-whitespace.

  $ set -o pipefail

  $ mkdir prev next

Show added newline at start of input

  $ cat > prev/file <<'EOF'
  > bar
  > EOF

  $ cat > next/file <<'EOF'
  >
  >  bar
  > EOF

  $ patdiff -default prev next -keep-whitespace | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,2(-weight) ============================================================
  (bg:red fg:black)-|(off fg:gray-12)bar(fg:default)
  (bg:green fg:black)+|(off)
  (bg:green fg:black)+|(off +invert fg:green) (-invert fg:default)bar
  [1]

-unrefined works too

  $ cat > prev/file <<'EOF'
  > bar
  > EOF

  $ cat > next/file <<'EOF'
  >
  >  bar
  > EOF

  $ patdiff -default prev next -keep-whitespace -unrefined | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,2(-weight) ============================================================
  (bg:red fg:black)-|(bg:default fg:red)bar(fg:default)
  (bg:green fg:black)+|(bg:default fg:default)
  (bg:green fg:black)+|(bg:default fg:green) bar(fg:default)
  [1]

-ascii works too (it implies -unrefined)

  $ cat > prev/file <<'EOF'
  > bar
  > EOF

  $ cat > next/file <<'EOF'
  >
  >  bar
  > EOF

  $ patdiff -default prev next -keep-whitespace -ascii | ansi_text visualize -minimize
  ------ prev/file
  ++++++ next/file
  @|-1,1 +1,2 ============================================================
  -|bar
  +|
  +| bar
  [1]

Show leading whitespace

  $ cat > prev/file <<'EOF'
  > bar
  > EOF

  $ cat > next/file <<'EOF'
  >  bar
  > EOF

  $ patdiff -default prev next -keep-whitespace | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,1(-weight) ============================================================
  (bg:red fg:black)-|(off fg:gray-12)bar(fg:default)
  (bg:green fg:black)+|(off +invert fg:green) (-invert fg:default)bar
  [1]

Show internal whitespace

  $ cat > prev/file <<'EOF'
  > foo bar
  > EOF

  $ cat > next/file <<'EOF'
  > foo  bar
  > EOF

  $ patdiff -default prev next -keep-whitespace | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,1(-weight) ============================================================
  (bg:red fg:black)-|(off fg:gray-12)foo(+invert fg:red) (-invert fg:gray-12)bar(fg:default)
  (bg:green fg:black)+|(off)foo(+invert fg:green)  (-invert fg:default)bar
  [1]

Show trailing whitespace

  $ cat > prev/file <<'EOF'
  > foo
  > EOF

  $ cat > next/file <<'EOF'
  > foo 
  > EOF

  $ patdiff -default prev next -keep-whitespace | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,1(-weight) ============================================================
  (bg:red fg:black)-|(off fg:gray-12)foo(fg:default)
  (bg:green fg:black)+|(off)foo(+invert fg:green) (-invert fg:default)
  [1]
