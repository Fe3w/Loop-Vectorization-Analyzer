# Methodology: scoring LoopLens against LoopVectorize

## Data
- **Benchmark:** PolyBench/C 4.2.1-beta, 30 kernels, fetched by `scripts/fetch_polybench.sh`
  (pinned URL, SHA-256 checked) and compiled as shipped — no `restrict`, default dataset macros.
- **Compiler:** `clang-20 -O3 -g` for generic x86-64 (no `-march`), LoopLens loaded with
  `-fpass-plugin` at the VectorizerStart extension point, `-fsave-optimization-record`
  (`scripts/collect.sh`). The exact toolchain is recorded in `results/*_toolchain.txt`.
- Per kernel: LLVM's optimization record (LoopVectorize and LoopLens remarks) and LoopLens's JSON Lines.

## Attributing LoopVectorize's reasons to loops
For each innermost loop, LoopVectorize emits zero or more *reason* remarks at instruction locations
(`UnsafeDep`, `CantReorderFPOps`, …) and then one *per-loop* remark at the loop's start location
(`Vectorized` or `MissedDetails`). The reasons since the previous per-loop remark of the same file
belong to the next per-loop remark. Some verdicts close a loop on their own, without a
`MissedDetails`: `VectorizationNotBeneficial` and the post-legality failures
`UncountableEarlyExitLoopsDisabled`, `UncountableEarlyExitUnsupported`,
`StructCallVectorizationUnsupported` (LoopVectorizePass::processLoop). `Interleaving*` remarks are not reasons. With remarks enabled,
LoopVectorize keeps checking after the first failure, so a loop can have several reasons; the
**first** one is its primary, the same meaning as LoopLens's `primary`.

## Mapping LLVM remark names to LoopLens categories
(Generated from `MAPPING` in `scripts/agreement.py`; first matching pattern wins. A name without a
mapping is reported as `unmapped:<Name>` and counts as a disagreement.)

| LLVM remark `Name` (glob) | LoopLens category |
| --- | --- |
| `Vectorized` | none |
| `CantReorderFPOps`, `NonReductionValueUsedOutsideLoop`, `UnsupportedPhi` | reduction |
| `CantVectorizeLibcall`, `CantVectorizeCall`, `CantVectorizeIntrinsic`, `CantVectorizeInstruction`, `CantVectorizeInstructionReturnType`, `NonSimpleLoad`, `CantVectorizeStore*`, `CantVectorizeNontemporal*`, `StructCallVectorizationUnsupported` | call-or-unsafe-memop |
| `NoCFGForSelect`, `CFGNotUnderstood`, `EarlyExit*`, `*EarlyExitLoop*`, `UncountableEarlyExitLoopsDisabled`, `UncountableEarlyExitUnsupported`, `NoLatchEarlyExit`, `TooManyUncountableEarlyExits`, `LoopContainsUnsupported*`, `UnsupportedOuterLoop` | control-flow |
| `CantReorderMemOps`, `CantIdentifyArrayBounds`, `CantCheckMemDepsAtRunTime`, `TooManySCEVRunTimeChecks` | aliasing |
| `LowTripCount`, `*NotBeneficial` | cost |
| `CantComputeNumberOfIterations`, `UnsupportedUncountableLoop` | trip-count |
| `UnsafeDep` | loop-carried-dependence |

`cost` is LoopVectorize deciding vectorization is not profitable; it agrees with LoopLens's `stride`
category (its cost-model rules) and with `hint` (clang lowers `vectorize(disable)` to
`vectorize_width(1)`, which LoopVectorize reports as `VectorizationNotBeneficial`).

## Matching and metric
- A LoopVectorize per-loop remark and a LoopLens innermost loop match when file, line, column and
  function are equal (function, because an inlined kernel puts the same source loop into `main` too).
- **Agreement** = LoopLens `primary` equals the mapped category of LoopVectorize's first reason
  (`none` for `Vectorized`). Also reported: agreement when LoopVectorize's category is LoopLens's
  primary *or one of its secondaries*.
- Several loops on one key are paired by position (`both-by-order`) when both sides have the same
  number: LoopVectorize visits innermost loops in program order (LoopVectorize.cpp:10775-10784,
  2179-2202), the order LoopLens reports them. Otherwise they, and loops on only one side, are
  listed (`ambiguous`, `looplens-only`, `lv-only`) and excluded from the percentage.
- **All-reasons coverage** (second metric): every category among LoopVectorize's reasons for the
  loop (it keeps checking after the first failure when remarks are on) is LoopLens's primary or one
  of its secondaries (`lv_categories`, `all_reasons_covered`).
- Output: `results/agreement.csv` (one row per loop) and `results/agreement_summary.csv`.

## Held-out check: TSVC_2
`scripts/fetch_tsvc.sh` fetches `tsvc.c`, `common.h`, `array_defs.h` from UoB-HPC/TSVC_2 at commit
911fc639 (SHA-256 checked; the repository publishes no licence, so the sources are never committed).
`scripts/collect.sh --list bench/tsvc/benchmark_list` compiles the one file with the same flags and
`scripts/agreement.py --prefix tsvc_` scores it. LoopLens was not tuned on TSVC; the first scorer run
is kept as `results/tsvc_agreement_summary_before.csv` (it exposed a scorer bug, see
`results/tsvc_disagreements.md`).

## Other targets
The same pipeline runs with `--cflags "-march=x86-64-v4"` and `--cflags "--target=aarch64-linux-gnu
--sysroot=…"` (compile-only; `scripts/fetch_aarch64_sysroot.sh`), results in `results/x86v4_*`,
`results/aarch64_*`, `results/tsvc_x86v4_*`, `results/tsvc_aarch64_*`. On AArch64 most remaining
disagreements are cost-model verdicts (`VectorizationNotBeneficial`, `Interleaved`) where LoopLens
predicts no blocker.

## Limits
- Three targets measured; cost-model outcomes depend on the target and LoopLens has no cost model,
  which is why AArch64 agreement is much lower than x86's.
- The headline metric scores the *primary* reason; all-reasons coverage scores the rest.
- LoopLens analyses the IR at VectorizerStart; LoopVectorize sees it after LoopRotate,
  LoopDeletion, (opt-in) LoopDistribute and InjectTLIMappings.
