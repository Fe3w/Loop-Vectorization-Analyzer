# Changelog

## Unreleased

- Repository renamed to `Loop-Vectorization-Analyzer` (was `looplens`; GitHub redirects the old URL).
  Internal names are unchanged: `LoopLens.so`, `looplens-analyze`, `looplens-repair`, `-looplens-*`.
- README rewritten: how it works, key results, comparisons, findings, worked example, limitations;
  setup and usage moved to `docs/setup.md`, options and output format to `docs/reference.md`.
- Figures redrawn and extended (`scripts/plots.py`): results tiles, agreement split by LLVM's reason,
  why LLVM missed each loop, speedup with run spread, GCC comparison, the LLVM 20 interchange bug;
  architecture diagram `docs/img/pipeline.svg`.
- The LLVM 20.1.2 loop-interchange wrong result (listed under v0.2) is fixed after LLVM 20: LLVM
  21.1.8, 22.1.8 and 23.1.5 refuse the nest (`results/interchange_newer_llvm.txt`).

## v0.2 (2026-11-14)

- `looplens-repair`: versions a loop that accumulates into a possibly-overlapping address and keeps
  the value in a register in the fast copy (`-mllvm -looplens-repair`, check limit
  `-looplens-repair-max-checks`). 5 PolyBench loops repaired.
- Correctness evidence: strict-FP byte equality on PolyBench (SMALL, MEDIUM), an overlap driver that
  runs both loop copies, a mutation test, and a fast-math tolerance fixed in advance
  (`docs/correctness.md`, `results/repair_differential.csv`).
- What the repair does not fix, with a test per loop (`docs/repair-limits.md`).
- Three targets measured (generic x86-64, x86-64-v4, AArch64 compile-only); second metric
  (all reasons covered); new rules `cost-strided`, `hint-vectorize-disabled`, `mem-call-writes`;
  target-aware `red-exact-fp` and `stride-gather`.
- Every rule's suggested fix checked against LLVM (`scripts/verify_fixes.sh`).
- Timing harness with equal-flag configurations (`bench/timing/time.sh`) and one measured laptop
  run (`results/timing.csv`, i7-13650HX): repair speedups from 0.91× to 5.79×; large gains only with
  `-ffast-math` (cholesky, lu); none on nussinov and trmm (`docs/writeup.md`).
- Plots from CSVs (`scripts/plots.py`), technical write-up (`docs/writeup.md`), weekly reproduce
  workflow.
- Interchange legality for column walks (`cost-strided`), from DependenceAnalysis direction vectors:
  `interchange legal=<yes|no|unknown>` line, JSON `interchange` object, and a specific fix text
  (LLVM's `-mllvm -enable-loopinterchange`, rewrite triangular bounds by hand, or transpose).
  LLVM's own pass is the oracle (`scripts/interchange_oracle.py`, `results/interchange_tsvc.csv`).
- llvm-mca estimate per suggested fix (`scripts/fix_mca.py`, `results/fix_mca.csv`): cycles per
  element before and after, ratio only when no call is in the loop.
- GCC 13 comparison per loop (`scripts/gcc_compare.py`, `results/gcc_compare_*.csv`).
- Found in LLVM 20.1.2: loop-interchange ignores confused dependences and changes the result of a
  program whose arrays overlap (`test/interchange/confused-miscompile.test`).

## v0.1 — MVP (2026-11-12)

- `looplens-analyze`: per-loop facts from LLVM 20's analyses — source location, trip count
  (ScalarEvolution) with an unknown-trip reason, induction variables, reductions and recurrences,
  loop form and control flow, LoopAccessAnalysis verdict, dependences with byte distances, per-access
  strides, calls and volatile/atomic accesses.
- Classifier: one rule table in LoopVectorize's own order of checks; primary and secondary blocker,
  evidence and a source-level fix per rule.
- Output: text report, JSON Lines (`-looplens-json`), LLVM optimization remarks (pass `looplens`).
- Runs inside `clang -O2/-O3` at the VectorizerStart extension point (after LoopSimplify + LCSSA);
  generated code unchanged (`results/codegen_check.txt`).
- Measurement: PolyBench/C 4.2.1 (30 kernels) and TSVC_2 as a held-out suite, scored against
  LoopVectorize's remarks by `scripts/agreement.py`; results in `results/`, method in
  `docs/methodology.md`, one-command rebuild with `scripts/reproduce.sh`.
- 155 lit/FileCheck tests (IR, C end-to-end and script tests).
