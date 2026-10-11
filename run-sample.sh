#!/usr/bin/env bash
# Builds and runs sample.cr, saving the binary, its dSYM, and the printed
# backtraces into build/. Fails unless the first backtrace frame includes a
# `file.cr:line`, which is what athena's console exception rendering relies on.
set -euo pipefail

crystal --version
crystal env CRYSTAL_PATH
xcodebuild -version
dsymutil --version

mkdir -p build
crystal build sample.cr -o build/sample
ls -la build
# Non-fatal so a missing or mismatched dSYM still shows the backtraces below
dwarfdump --uuid build/sample build/sample.dwarf || true

build/sample | tee build/backtrace.txt
CRYSTAL_CALLSTACK_FULL_INFO=1 build/sample | tee build/backtrace-full.txt

head -n 1 build/backtrace.txt | grep -qE '[[:alnum:]_]+\.cr:[0-9]+'
