#!/usr/bin/env bash
# Builds and runs sample.cr, saving the binary, its dSYM, and the printed
# backtraces into build/. Fails unless the backtrace resolves the `raise` in
# `raise_in_method` to sample.cr line 2.
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

grep -qE "^sample\.cr:2:[0-9]+ in 'raise_in_method'" build/backtrace.txt
