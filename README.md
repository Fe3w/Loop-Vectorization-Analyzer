# LoopLens

[![ci](https://github.com/Fe3w/looplens/actions/workflows/ci.yml/badge.svg)](https://github.com/Fe3w/looplens/actions/workflows/ci.yml)

An out-of-tree LLVM 20 new-pass-manager plugin that finds loops LLVM's loop
vectorizer leaves scalar, explains why using LLVM's own analyses, and
(Phase 2) repairs alias-blocked loops with runtime versioning.

Status: skeleton — prints every loop's header and depth.

## Build and test

```bash
cmake -S . -B build -G Ninja
cmake --build build
cmake --build build --target check     # runs lit + FileCheck tests
```

## Run on your own code

```bash
# Canonical IR: what LoopVectorize sees (rotated, LCSSA, loop-simplify form).
clang-20 -O1 -g -fno-discard-value-names -Xclang -disable-llvm-passes -emit-llvm -S foo.c -o - \
  | opt-20 -passes='sroa,loop-simplify,lcssa,loop(loop-rotate)' -S -o foo.ll
opt-20 -load-pass-plugin=build/lib/LoopLens.so -passes=looplens-analyze -disable-output foo.ll
```

Output is one line per loop, outer before inner:

```
looplens: function 'saxpy'
  loop header=for.body depth=1 loc=saxpy.c:2:3
```

`loc=` is `Loop::getStartLoc()`, the same location LLVM's loop-vectorize remarks
use (`loc=<none>` without debug info).

## Layout

| Path | Contents |
| --- | --- |
| `lib/` | Pass sources |
| `test/` | lit/FileCheck regression tests |
| `bench/` | PolyBench/C and TSVC harness |
| `results/` | CSVs and plots; the only source of reported numbers |
| `scripts/` | Helper scripts (remark parsing, agreement table) |
| `DECISIONS.md` | One line per design decision |
