# Is `looplens-repair` correct?

`looplens-repair` rewrites loops (versioning plus keeping an accumulated value in a register), so it
needs evidence that it never changes a program's results. This page is the plan, the execution and a
review of that evidence. Every number comes from `results/repair_differential.csv`, written by
`scripts/differential.sh`.

## Plan

1. **PolyBench, strict FP.** Build all 30 PolyBench/C 4.2.1 kernels at `-O3` with and without the
   repair, with `-DPOLYBENCH_DUMP_ARRAYS`, on the SMALL and MEDIUM datasets, and compare the dumped
   arrays byte for byte. The promotion keeps the order of floating-point operations, so any
   difference at all is a bug.
2. **Overlap tests.** PolyBench arrays never overlap, so on PolyBench the runtime check always
   chooses the promoted (fast) copy and the original copy never runs. A separate driver
   (`test/differential/overlap/overlap.c`) calls four kernels shaped like the repaired PolyBench
   loops (cholesky/lu, a flat accumulator, trmm's column reads, nussinov's integer max) with the
   accumulator placed before, at the first element of, inside, at the last element of, just past and
   far from the ranges read, and with two ranges that overlap each other. It is built at `-O0`
   (reference), `-O3` and `-O3` with the repair, all with `-ffp-contract=off` so that the comparison
   is about the repair and not about fused multiply-add choices; results are printed exactly (`%a`)
   and must be identical. A hand-written kernel (`load-in-loop.ll`) covers the second promotion shape,
   where the load of the accumulator is still inside the loop.
3. **Fast-math, against a tolerance fixed before running.** With `-ffast-math` the repaired loops may
   be vectorized, which reassociates sums, so byte equality is not expected. A dumped value is within
   tolerance if its relative error is at most 1e-6, or its absolute error is at most 0.011 and the
   value is below 1e4 in magnitude. Reason: PolyBench prints `%0.2lf`, so 0.01 is one unit in the last
   printed digit; reassociating a sum of 10²–10³ doubles changes it by roughly n·ε relative (about
   1e-13), far below one printed digit, so a larger difference would be a bug rather than rounding.
   Reported separately from the strict result.

## Execution

- **PolyBench, strict FP:** 60 kernel runs (30 kernels × SMALL, MEDIUM); all 60 byte-identical; 5
  loops repaired per dataset (trmm 1, cholesky 1, lu 2, nussinov 1).
- **Overlap tests** (run by `cmake --build build --target check`):
  - `overlap.test`: `-O0`, `-O3` and `-O3` + repair print identical output for all 50 calls, and the
    repair fired on all four kernels.
  - `both-paths.test`: the repaired IR of each kernel contains the runtime check and both loop copies.
  - `mutant.test`: with the runtime check forced to "no overlap" the output differs from the
    reference (so the test would catch a missing or wrong check); forced to "overlap" it is identical.
  - `load-in-loop.ll`: the load-in-loop shape gives identical exact values under `lli` before and
    after the repair, and its mutant does not.
- **Fast-math:** all 60 runs within tolerance. Values differ only in cholesky and lu (the kernels
  whose repaired loops LoopVectorize then vectorizes: 7 → 8 and 6 → 8 vectorized loops); the largest
  absolute difference is 0.01, one unit in the last printed digit. trmm and nussinov are repaired but
  not vectorized and show no difference.

## Review

- What this establishes: on the 5 loops the repair transforms in PolyBench, and on the four kernel
  shapes of the overlap driver, results are unchanged in strict FP whether or not the address ranges
  overlap, and both loop copies are exercised.
- What it does not establish: correctness on loop shapes outside these (the repair's candidate
  conditions are narrow by design: one store to a loop-invariant address, other accesses loads with
  computable ranges, at most 8 ranges); behaviour on targets other than x86-64, which were not run;
  address computations that wrap around the address space (the range check assumes they do not, as
  LLVM's own runtime checks do for `inbounds` accesses).
- The LARGE dataset is not dumped (hundreds of megabytes per kernel); MEDIUM already runs every
  repaired loop for thousands of iterations.
- The fast-math comparison is limited by PolyBench's two printed decimals: it bounds the error at
  one printed unit, not at machine precision.
