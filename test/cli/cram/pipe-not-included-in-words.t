The pipe character is not part of words.

  $ set -o pipefail

  $ mkdir prev next

  $ cat > prev/file <<'EOF'
  >
  > min=0|max=10
  > EOF

  $ cat > next/file <<'EOF'
  >
  > min=5|max=10
  > EOF

  $ patdiff -default prev next | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,2 +1,2(-weight) ============================================================
  (bg:gray fg:black) |(bg:default fg:default)
  (bg:red fg:black)-|(off fg:gray-12)min=(fg:red)0(fg:gray-12)|max=10(fg:default)
  (bg:green fg:black)+|(off)min=(fg:green)5(fg:default)|max=10
  [1]
