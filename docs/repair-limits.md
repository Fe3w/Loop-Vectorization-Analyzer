# What `looplens-repair` fixes, and what it does not

`looplens-repair` targets one blocker: a loop that accumulates into a loop-invariant address which
may overlap the addresses the loop reads (LoopAccessAnalysis: `UnsafeDep`). It versions the loop on
"the accumulated address lies outside every range read" and, in the fast copy, keeps the value in a
register (one load before the loop, one store after it). Every claim below is pinned by a test.

## What it does

- **Makes the loop vectorizable when FP reordering is allowed.** The cholesky accumulation
  `A[i][j] -= A[i][k] * A[j][k]` is not vectorized by `clang -O3 -ffast-math`; with the repair it is
  (`test/repair/cholesky-fast.ll`, `test/clang/repair.c`), and also in strict FP with
  `#pragma clang loop vectorize(enable)` (`test/clang/repair-pragma.c`). In strict FP without the
  pragma the fast copy stops at "cannot reorder floating-point operations" instead of the dependence
  (`test/repair/cholesky-strict.ll`): the repair moves the blocker to one the programmer can lift.
- **Leaves loops alone that LLVM already handles.** A loop that only needs runtime pointer checks is
  versioned by LoopVectorize itself; the repair does nothing (`test/repair/no-op-llvm-versions.ll`,
  `test/repair/no-op.ll`).
- **Stops at a check limit.** More than 8 address ranges to check (`-looplens-repair-max-checks`,
  the value of LLVM's `-runtime-memory-check-threshold`) and nothing is versioned
  (`test/repair/threshold.ll`; 8 are still accepted: `test/repair/threshold-at-limit.ll`).

## The four PolyBench loops it does not turn into vector code

Checked with `clang-20 -O3 -ffast-math -g -mllvm -looplens-repair` on generic x86-64, reading
LoopVectorize's and LoopLens's remarks on the IR after the repair.

**trmm.c:88** — `B[i][j] += A[k][i] * B[k][j]` over `k`. Repaired: the store to `B[i][j]` no longer
conflicts in the fast copy. But both reads walk down a column (`A[k][i]`, `B[k][j]`), a constant
stride of one row per iteration, and the target has no legal gather, so LoopVectorize's cost model
says "vectorization is not beneficial"; LoopLens reports `stride` / `cost-strided`. Versioning and
promotion cannot change how the loop walks memory; a loop interchange or a transposed layout would.
(The planning hypothesis "it reads and writes the same array `B`" was wrong: that dependence is what
the repair removes.) Test: `test/clang/limit-trmm.c`.

**nussinov.c:102** — `table[i][j] = max(table[i][j], table[i][k] + table[k+1][j])` over `k`.
Repaired as well. One read walks a row, the other a column, and the cost model again rejects the
fast copy. LoopLens reports no blocker for it: it has no cost rule for a mix of unit and strided
reads (a known gap). The hypothesis "a real dependence or control flow" was wrong: after the repair
the loop is legal, just not profitable. Test: `test/clang/limit-nussinov.c`.

**bicg.c:88** — `s[j] += r[i] * A[i][j]; q[i] += A[i][j] * p[j]` over `j`. Not repaired. The loop has
one accumulator (`q[i]`) and a second store to a varying address (`s[j]`). The repair handles exactly
one store, to a loop-invariant address: with a second store, promoting `q[i]` would not remove every
possible conflict (`s[j]` may still overlap what is read). LoopVectorize keeps `UnsafeDep`; LoopLens
reports `loop-carried-dependence` / `mem-unsafe-dep`. Test: `test/clang/limit-bicg.c`.

**gesummv.c:87** — `tmp[i] += A[i][j] * x[j]; y[i] += B[i][j] * x[j]` over `j`. Not repaired: two
accumulators, i.e. two stores to loop-invariant addresses, outside the one-store pattern (the
hypothesis "two accumulators in one loop" holds). Handling it would need a check between the two
accumulators as well as against every range read. Test: `test/clang/limit-gesummv.c`.

In every repaired kernel the original copy of the loop, which runs only when the ranges overlap,
keeps its `UnsafeDep` remark. That is expected.
