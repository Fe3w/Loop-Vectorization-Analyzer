# Disagreements between LoopLens and LoopVectorize (PolyBench/C 4.2.1)

Source of truth: `results/agreement.csv` (rows with `agree=no`), produced by
`scripts/agreement.py` from `scripts/collect.sh` output. Classes: (a) LoopLens bug, fixed with a
regression test; (b) LLVM's remark is vaguer than LoopLens (kept); (c) mapping issue.

## Remaining

None in the current `results/agreement.csv`.

## Fixed (first measurement, S17 → S18)

| Kernel:line | LoopVectorize (first reason) | LoopLens before | Class | Cause and fix | Regression test |
| --- | --- | --- | --- | --- | --- |
| trmm.c:88, cholesky.c:93, lu.c:92, lu.c:98 | `UnsafeDep` → loop-carried-dependence | reduction (`red-exact-fp`), loop-carried-dependence secondary | (a) | Rule order: LoopVectorize asks whether FP operations may be reordered (`CantReorderFPOps`) only after its legality checks have passed (`LoopVectorizePass::processLoop`, LoopVectorize.cpp:10485), so an unsafe dependence is reported first. `red-exact-fp` moved after the memory rules. | `test/clang/fp-reduction-unsafe-dep.c` |
| ludcmp.c:108, ludcmp.c:124, ludcmp.c:131, trisolv.c:77 | `CantReorderFPOps` → reduction | none | (a) | At the VectorizerStart extension point these loops had no preheader yet (LoopVectorizePass runs `simplifyLoop`/LCSSA itself, later), so LoopLens could not query the reduction descriptor. LoopLens now runs LoopSimplify + LCSSA in front of itself at that point (`-looplens-canonicalize`, default on). `scripts/codegen_unchanged.sh` shows the generated assembly is identical with and without the plugin for all 30 kernels (`results/codegen_check.txt`). | `test/clang/no-preheader-at-ep.c` |
