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

Output is one block per loop, outer before inner:

```
looplens: function 'saxpy'
  loop header=for.body depth=1 loc=saxpy.c:2:3
    trip kind=symbolic count=none btc=[(-1 + %n)] max-btc=[2147483646] symbolic-max-btc=[(-1 + %n)]
```

- `loc=` is `Loop::getStartLoc()`, the same location LLVM's loop-vectorize remarks
  use (`loc=<none>` without debug info).
- `trip` comes from ScalarEvolution. `kind` is `constant` (with the exact
  `count`), `symbolic` or `unknown`; `btc` is the backedge-taken count
  (trip count − 1), followed by its constant and symbolic upper bounds, as SCEV
  text in brackets (`***COULDNOTCOMPUTE***` when unknown). Unknown loops carry a
  coarse `reason`, first match wins: `multiple-exits`; `needs-scev-predicate`
  (computable once SCEV may assume e.g. no-wrap, which a runtime check can
  guarantee); `exit-cond-not-affine` (an exit-compare operand, looking through
  `&&`/`||` and integer casts, is neither loop-invariant nor an affine
  recurrence of the loop — e.g. a loaded value); `exit-cond-not-icmp` (e.g. a
  floating-point compare); `other`.

Input should be in the canonical form LoopVectorize sees (loop-simplify, LCSSA,
rotated; the recipe above produces it). LoopLens is an analysis and never
changes the IR, so it does not canonicalise loops itself; on other input its
facts describe the IR as given.

## Layout

| Path | Contents |
| --- | --- |
| `lib/` | Pass sources |
| `test/` | lit/FileCheck regression tests |
| `bench/` | PolyBench/C and TSVC harness |
| `results/` | CSVs and plots; the only source of reported numbers |
| `scripts/` | Helper scripts (remark parsing, agreement table) |
| `DECISIONS.md` | One line per design decision |
