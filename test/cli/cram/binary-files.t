Test the messages when non-ASCII text files or binary files differ.

  $ set -o pipefail

  $ mkdir prev next

message when non-ASCII text files differ

  $ cat > prev/file <<'EOF'
  > ┌Signals──┐┌Values───┐┌Waves─────────┐
  >       │clock    ││         ││┌───┐   ┌───┐ │
  >       │         ││         ││    └───┘   └─│
  > EOF

  $ cat > next/file <<'EOF'
  > ┌Signals──┐┌Values───┐┌Waves─────────┐
  >       │clock2   ││         ││┌───┐   ┌───┐ │
  >       │         ││         ││    └───┘   └─│
  > EOF

  $ patdiff -default prev next -location-style omake | ansi_text visualize -minimize
  (fg:red)------ (fg:default +bold)prev/file(-weight)
  (fg:green)++++++ (fg:default +bold)next/file(-weight)
  File "prev/file", line 2, characters 0-1:
  (bg:gray fg:black) |(bg:default fg:default)┌Signals──┐┌Values───┐┌Waves─────────┐
  (bg:red fg:black)-|(off fg:red)      │clock(fg:gray-12)    ││         ││┌───┐   ┌───┐ │(fg:default)
  (bg:green fg:black)+|(off fg:green)      │clock2(fg:default)   ││         ││┌───┐   ┌───┐ │
  (bg:gray fg:black) |(bg:default fg:default)      │         ││         ││    └───┘   └─│
  [1]

message when binary files differ

  $ printf 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\000zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz' > prev/file

  $ printf 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\000\001zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz' > next/file

  $ patdiff -default prev next -location-style omake | ansi_text visualize -minimize
  File "prev/file", line 1, characters 0-1:
    File "next/file"
    binary files differ
  
  [1]
