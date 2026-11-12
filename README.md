# LoopLens

An out-of-tree LLVM 20 new-pass-manager plugin that finds loops LLVM's loop
vectorizer leaves scalar, explains why using LLVM's own analyses, and
(Phase 2) repairs alias-blocked loops with runtime versioning.

Status: Week 1 skeleton (prints every loop's header and depth).

## Build and test

```bash
cmake -S . -B build -G Ninja
cmake --build build
cmake --build build --target check     # runs lit + FileCheck tests
```

## Run on your own code

```bash
clang-20 -O1 -g -Xclang -disable-llvm-passes -emit-llvm -S foo.c -o foo.ll
opt-20 -load-pass-plugin=build/lib/LoopLens.so \
  -passes='function(loop-simplify,lcssa),looplens-analyze' -disable-output foo.ll
```

## Layout

| Path | Contents |
| --- | --- |
| `lib/` | Pass sources |
| `test/` | lit/FileCheck regression tests |
| `bench/` | PolyBench/C and TSVC harness (week 5+) |
| `results/` | CSVs and plots; the only source of reported numbers |
| `scripts/` | Helper scripts (remark parsing, agreement table) |
| `DECISIONS.md` | One line per design decision |
