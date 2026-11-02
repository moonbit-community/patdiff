Test that ANSI escape sequences in the input are handled.

  $ set -o pipefail

  $ mkdir prev next

ansi escape code in input

  $ printf '\033[0;1m\n' > prev/file

  $ printf '\033[0;2m\n' > next/file

  $ patdiff -default prev next | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,1(-weight) ============================================================
  (bg:red fg:black)-|(off +bold fg:default)
  (bg:green fg:black)+|(off +faint fg:default)
  [1]

colored text

  $ printf '\033[0;33myellow text\033[0m\n' > prev/file

  $ printf '\033[0;34mblue text\033[0m\n' > next/file

  $ patdiff -default prev next | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  (bg:gray fg:black)@|(bg:default fg:default +bold)-1,1 +1,1(-weight) ============================================================
  (bg:red fg:black)-|(off fg:yellow)yellow(fg:gray-12) text(fg:default)
  (bg:green fg:black)+|(off fg:blue)blue(fg:default) text
  [1]
