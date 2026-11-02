#!/usr/bin/env python3
"""Runs the CLI tests in cram/ against the native build of patdiff.

Each `.t` file has prose, commands (`  $ cmd`, continued by `  > more`) and the
output expected of them, with a `  [N]` line for a non-zero exit code. All the
commands of a file run in one shell, in a new temporary directory.

Usage: moon build --release && python3 test/cli/run_cram.py [file.t ...]

With `--target wasm`, the Wasm build (`moon build --release --target wasm`) is
run with moonrun instead.
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TARGET = "native"
MARKER = "@@CRAM-MARKER@@"


def parse(path):
    """Gives a list of (command, expected output lines)."""
    steps = []
    with open(path, errors="surrogateescape") as f:
        for line in f.read().split("\n"):
            if line.startswith("  $ "):
                steps.append([line[4:], []])
            elif (line.startswith("  > ") or line == "  >") and steps and not steps[-1][1]:
                steps[-1][0] += "\n" + line[4:]
            elif line.startswith("  ") and steps:
                steps[-1][1].append(line[2:])
            elif line == "" and steps:
                # Blank lines inside output are written with two spaces, so
                # this just ends the output.
                pass
    return steps


def make_bin_dir(tmp):
    bin_dir = os.path.join(tmp, ".bin")
    os.mkdir(bin_dir)
    build = os.path.join(ROOT, f"_build/{TARGET}/release/build/cmd")
    for name in ["patdiff", "ansi_text"]:
        if TARGET == "wasm":
            program = os.path.join(bin_dir, name)
            with open(program, "w") as f:
                f.write(f'#!/bin/sh\nexec moonrun "{os.path.join(build, name, name + ".wasm")}" "$@"\n')
            os.chmod(program, os.stat(program).st_mode | stat.S_IEXEC)
        else:
            os.symlink(os.path.join(build, name, name + ".exe"), os.path.join(bin_dir, name))
    wrapper = os.path.join(ROOT, "scripts/patdiff-git-wrapper")
    if os.path.exists(wrapper):
        shutil.copy(wrapper, os.path.join(bin_dir, "patdiff-git-wrapper"))
    colors = os.path.join(bin_dir, "visible_colors")
    with open(colors, "w") as f:
        f.write('#!/bin/sh\nexec ansi_text visualize -minimize\n')
    os.chmod(colors, os.stat(colors).st_mode | stat.S_IEXEC)
    return bin_dir


def run(path):
    steps = parse(path)
    with tempfile.TemporaryDirectory() as tmp:
        bin_dir = make_bin_dir(tmp)
        work = os.path.join(tmp, "work")
        os.mkdir(work)
        script = []
        for i, (cmd, _) in enumerate(steps):
            script.append(f"echo '{MARKER} {i}'")
            script.append(cmd)
            script.append(f"__status=$?; echo; echo \"{MARKER} exit $__status\"")
        env = dict(os.environ, PATH=bin_dir + ":" + os.environ["PATH"], HOME=work, TERM="dumb")
        env.pop("TMPDIR", None)
        proc = subprocess.run(
            ["bash", "-c", "\n".join(script)],
            cwd=work,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
        )
    out = proc.stdout.decode(errors="surrogateescape")
    failures = 0
    chunks = re.split(re.escape(MARKER) + r" (\d+)\n", out)[1:]
    results = {}
    for i in range(0, len(chunks), 2):
        results[int(chunks[i])] = chunks[i + 1]
    for i, (cmd, expected) in enumerate(steps):
        chunk = results.get(i, "")
        body, _, status = chunk.rpartition(MARKER + " exit ")
        # The `echo` above adds a newline, which ends a last line that lacks one.
        if body.endswith("\n"):
            body = body[:-1]
        if body.endswith("\n"):
            body = body[:-1]
        lines = body.split("\n") if body else []
        code = int(status.strip() or "0")
        want = list(expected)
        if code == 0:
            # Blank lines after the output are just separators in the file.
            while lines and lines[-1] == "":
                lines.pop()
        else:
            lines.append(f"[{code}]")
        while want and want[-1] == "":
            want.pop()
        if lines != want:
            failures += 1
            print(f"--- {os.path.basename(path)}: $ {cmd}")
            for line in want:
                if line not in lines:
                    print(f"  - {line}")
            for line in lines:
                if line not in want:
                    print(f"  + {line}")
    return len(steps), failures


def main():
    global TARGET
    files = sys.argv[1:]
    if files[:1] == ["--target"]:
        TARGET = files[1]
        files = files[2:]
    if not files:
        cram = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cram")
        files = sorted(os.path.join(cram, f) for f in os.listdir(cram) if f.endswith(".t"))
    total = 0
    failed = 0
    for path in files:
        steps, failures = run(path)
        total += steps
        failed += failures
    print(f"{total} commands, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
