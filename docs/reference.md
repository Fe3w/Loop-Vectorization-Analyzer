# Reference

Detailed usage and output format of the Loop Vectorization Analyzer. Inside the code the project
keeps its original name, LoopLens: the plugin is `build/lib/LoopLens.so`, the passes are
`looplens-analyze` and `looplens-repair`, and the options start with `-looplens-`.
Overview and results: [README](../README.md).

## Use with clang

LoopLens registers itself at LLVM's VectorizerStart extension point, so a normal
optimised clang build runs it right before LoopVectorize, on the IR the
vectorizer sees:

```bash
clang-20 -O3 -g -fpass-plugin=build/lib/LoopLens.so \
  -Xclang -load -Xclang build/lib/LoopLens.so -mllvm -looplens-text=false \
  -Rpass-analysis='looplens|loop-vectorize' -Rpass-missed=loop-vectorize -c foo.c
# foo.c:8:3: remark: Category: reduction; Rule: red-exact-fp; ... [-Rpass-analysis=looplens]
# foo.c:8:3: remark: loop not vectorized [-Rpass-missed=loop-vectorize]
```

At that point LoopLens first runs LoopSimplify and LCSSA, which LoopVectorize
applies itself before its checks (`-looplens-canonicalize=false` turns this off).
`-Xclang -load` is only needed for `-mllvm -looplens-*` options (`-fpass-plugin`
loads the plugin after LLVM options are parsed). `-looplens-text=false` turns off
the stderr text report. Nothing runs at `-O0` (LoopVectorize does not either).
`#pragma clang loop vectorize(enable)` / `vectorize_width(N>1)` are read from the
loop metadata (`hints` line): they let LoopVectorize reorder FP reductions, so
LoopLens does not report `red-exact-fp` for such loops, nor its cost rules (a
forced loop skips LoopVectorize's profitability check).

## Remarks

LoopLens also reports each innermost loop as a standard LLVM optimization
remark (pass `looplens`, remark name = the rule id, or `Vectorizable`), at the
loop's start location — the location LoopVectorize uses for its per-loop
remarks:

```bash
opt-20 -load-pass-plugin=build/lib/LoopLens.so -passes='looplens-analyze,loop-vectorize' \
  -pass-remarks-analysis='looplens|loop-vectorize' -pass-remarks-missed=loop-vectorize \
  -disable-output foo.ll
# remark: unsafe1.c:2:3: Category: loop-carried-dependence; Rule: mem-unsafe-dep; Secondary: none; Evidence: ...; Fix: ...
```

`-pass-remarks-output=foo.yaml` writes the same remarks as YAML with the keys
`Category`, `Rule`, `Secondary`, `Evidence` and `Fix` under `Args`. Remarks need
debug info (`-g`); without it they carry no `DebugLoc`.

## JSON report

`-looplens-json=<path>` also writes one JSON object per loop, one per line
(JSON Lines), in report order:

```bash
opt-20 -load-pass-plugin=build/lib/LoopLens.so -passes=looplens-analyze \
  -looplens-json=out.jsonl -disable-output foo.ll
```

```json
{"function":"saxpy","header":"%for.body","depth":1,"file":"saxpy.c","line":2,"col":3,"innermost":true,"primary":"none","rule":"none","secondary":[],"evidence":"","fix":"","trip":{"kind":"symbolic","count":null,"btc":"(-1 + %n)"},"mem":{"status":"needs-checks","checks":1,"report":"none"}}
```

| Key | Type | Meaning |
| --- | --- | --- |
| `function`, `header`, `depth` | string, string, int | as in the text report |
| `file`, `line`, `col` | string/int or `null` | `Loop::getStartLoc()`; `null` without debug info |
| `innermost` | bool | only innermost loops are classified |
| `primary`, `rule` | string, or `null` for outer loops | classification (`"none"` = no blocker) |
| `secondary` | array of strings | other categories that apply |
| `evidence`, `fix` | string | empty when `primary` is `"none"` |
| `trip` | object | `kind`, `count` (string, or `null` unless constant), `btc` (SCEV text) |
| `mem` | object, innermost only | `status`, `checks`, `report` (LAA remark name) |
| `interchange` | object, `cost-strided` loops only | `legal` (`true`, `false`, or `null` = unknown), `dirs` (array of `"(<outer>,<inner>)"`), `bounds_depend_on_parent` (bool), `why` (`null` or the reason legality is unknown) |

The file is truncated when the first loop of a run is written and appended to
afterwards. `%p` in the path is replaced by the process ID (one file per compiler
process, e.g. `-looplens-json=out.%p.jsonl` in a parallel build). With clang, the option needs the plugin loaded before option
parsing: `-fpass-plugin=LoopLens.so -Xclang -load -Xclang LoopLens.so -mllvm -looplens-json=out.jsonl`.

## Output reference (text report via opt)

```bash
# Canonical IR: what LoopVectorize sees (rotated, LCSSA, loop-simplify form).
clang-20 -O1 -g -fno-discard-value-names -Xclang -disable-llvm-passes -emit-llvm -S foo.c -o - \
  | opt-20 -passes='sroa,loop-simplify,lcssa,loop(loop-rotate)' -S -o foo.ll
opt-20 -load-pass-plugin=build/lib/LoopLens.so -passes=looplens-analyze -disable-output foo.ll
```

Output is one block per loop, outer before inner:

```
looplens: function 'saxpy'
  loop header=%for.body depth=1 loc=saxpy.c:2:3
    trip kind=symbolic count=none btc=[(-1 + %n)] max-btc=[2147483646] symbolic-max-btc=[(-1 + %n)]
    iv phi=%i.05 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body>] controls-exit=yes
    form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes
    mem status=needs-checks checks=1 max-safe-width=any report=none
```

- `loc=` is `Loop::getStartLoc()`, the same location LLVM's loop-vectorize remarks
  use (`loc=<none>` without debug info). The file is the debug-info file name,
  i.e. the path as it was given to clang.
- `trip` comes from ScalarEvolution. `kind` is `constant` (with the exact
  `count`), `symbolic` or `unknown`; `btc` is the backedge-taken count
  (trip count − 1), followed by its constant and symbolic upper bounds, as SCEV
  text in brackets (`***COULDNOTCOMPUTE***` when unknown). Unknown loops carry a
  coarse `reason`, first match wins: `no-exit` (e.g. `while (1)`);
  `needs-scev-predicate` (computable once SCEV may assume e.g. no-wrap, which a
  runtime check can guarantee; any number of exits); `multiple-exits`;
  `exit-cond-not-affine` (an operand of the exit compare or switch — looking
  through `&&`/`||`, `!`, `freeze` and integer casts — is neither
  loop-invariant nor an affine recurrence of the loop, e.g. a loaded value);
  `exit-cond-not-icmp` (e.g. a floating-point compare); `other`. For a single
  exit all leaf conditions are inspected, so the reason does not depend on
  operand order.
- `iv` lists every header phi that `InductionDescriptor` accepts (no SCEV
  predicates assumed), in header order: `kind` int/ptr/fp, `start` value, `step`
  (in bytes for pointer IVs), the add-recurrence `scev`, and `controls-exit=yes`
  for the IV `Loop::getInductionVariable` returns (the one feeding the latch
  compare). `iv <none>` if there is no induction phi; `iv <no-preheader>` when the
  loop has no preheader (InductionDescriptor cannot be asked then).
- `recur` lines name every header phi that is not an induction: the reduction
  kind LLVM's `RecurrenceDescriptor` recognises (`add`, `mul`, `fadd`, `smax`,
  `ianyof`, …; `exact-fp=yes` when it may not be reassociated, `ordered=yes` when
  it could be done in order), `fixed-order` for a recurrence such as
  `t = a[i]` carried to the next iteration, or `unsupported`.
- `form` reports the loop-form facts LoopVectorize relies on, straight from
  LoopInfo: loop-simplify form, rotated (latch is an exiting block), LCSSA,
  single or multiple exiting blocks, innermost, and guarded. `guarded` only
  recognises LoopInfo's own guard pattern (a branch around a loop with a unique
  exit), so `guarded=no` is not proof that no guard exists.
- `cfg` (innermost loops) counts blocks, blocks that need predication
  (if-conversion), switches and exiting blocks; `early-exit` is `none`,
  `countable` or `uncountable` (a non-latch exit without an exit count).
- `mem` (innermost loops only; outer loops print `mem <not-innermost>`) is
  LoopAccessAnalysis's verdict: `status=safe`, `needs-checks` (safe with
  `checks=<n>` runtime pointer checks) or `unsafe` (LAA does not allow
  vectorization); `max-safe-width` in bits (`any`, or `n/a` when unsafe);
  `report=` is LAA's remark name, the same `Name:` LoopVectorize writes to its
  remark YAML (e.g. `UnsafeDep`, `CantIdentifyArrayBounds`).
- `dep` lines (innermost loops, after `mem`) list the dependences LAA's
  MemoryDepChecker recorded, in its order: `kind` is LLVM's own name (`Backward`,
  `BackwardVectorizable`, `Forward`, `Unknown`, `IndirectUnsafe`, `…ButPreventsForwarding`),
  `src`/`dst` are `load:`/`store:` plus the pointer, and `dist` is
  address(dst) − address(src) in bytes within one iteration — printed only when
  both pointers advance by the same step every iteration, else `none`.
  `dep <none>` when nothing was recorded.
- `access` lines (innermost loops) give each load and store with its stride,
  classified from the pointer's SCEV: `uniform` (stride 0), `unit` (+1 element),
  `reverse` (−1), `constant` (K elements), `symbolic` (a loop-invariant step,
  printed in bytes; `versioned=yes` if LoopAccessAnalysis recorded it as a
  symbolic stride LoopVectorize can version on), `indirect` (the address depends
  on a value loaded in the loop, e.g. `b[idx[i]]`) or `unknown`.
- `call` lines (innermost loops) judge each call the way LoopVectorize does:
  `vector=intrinsic` (has a vector intrinsic, e.g. `llvm.sqrt.f32`), `vfabi`
  (a declared vector variant), `tli` (the target library says so) or `no`;
  `mem` is its memory effect, and `math-lib=yes` marks a math-library call that
  `-fno-math-errno` / `-ffast-math` would typically turn into an intrinsic.
  `nonsimple` lines list volatile and atomic loads/stores.
- `blocker` (last line of each innermost loop; outer loops print
  `blocker <not-innermost>`) is the classification: `primary` is the category of
  the first rule that applies, `rule` names that rule, `secondary` lists the
  other categories that also apply. Rules are checked in LoopVectorize's own
  order (LLVM 20 `LoopVectorizationLegality::canVectorize`, then the cost model):

  | Rule | Category | When |
  | --- | --- | --- |
  | `hint-vectorize-disabled` | hint | `#pragma clang loop vectorize(disable)` or `vectorize_width(1)` (LoopVectorize reports these as "not beneficial") |
  | `cfg-uncountable-early-exit` | control-flow | an early exit without an exit count (LLVM 20 keeps early-exit vectorization off by default) |
  | `cfg-unpredicable` | control-flow | a call without a vector form, or a volatile/atomic access, in a block that needs predication (`NoCFGForSelect`) |
  | `red-exact-fp` | reduction | an FP reduction that needs exact (non-reassociable) math and cannot be done in order on this target (`CantReorderFPOps`; x86 yes, AArch64 does ordered reductions; use `-ffast-math` or `-fassociative-math`) |
  | `recur-unsupported` | reduction | a header phi that is neither induction, reduction nor recurrence |
  | `call-no-vector-form` | call-or-unsafe-memop | a call with `vector=no` (`CantVectorizeLibcall`) |
  | `mem-non-simple` | call-or-unsafe-memop | a volatile or atomic access |
  | `mem-call-writes` | call-or-unsafe-memop | a call with a vector variant (e.g. `-fveclib`) that may still write memory, such as `errno` |
  | `trip-uncountable` | trip-count | trip count unknown (and not just a SCEV predicate away), or LAA could not count iterations |
  | `mem-unsafe-dep` | loop-carried-dependence | LAA: unsafe dependence (`UnsafeDep`) |
  | `mem-no-runtime-check` | aliasing | LAA cannot build a runtime alias check (`CantIdentifyArrayBounds`, `CantCheckMemDepsAtRunTime`) |
  | `stride-gather` | stride | a gather/scatter (`indirect`) the target has no legal gather for, or a symbolic stride LAA does not version; a cost-model category |
  | `cost-strided` | stride | every access has a constant stride beyond 8 elements and the target has no legal gather (column walks); a cost-model category |

  For `cost-strided` loops an `interchange` line comes before `blocker`:
  `interchange legal=<yes|no|unknown> [dirs=[(<,>),...]] [bounds=depend-on-parent] [why=...]`. It says
  whether swapping the loop with its parent is legal, from DependenceAnalysis
  direction vectors (normalised as LoopInterchange does). The swap reverses a
  dependence exactly when its (parent, loop) directions can be `(<,>)` or
  `(>,<)`, so either of those makes it `no`. Dependences that some loop
  further out already carries are skipped. `why` is `no-parent-loop`,
  `not-perfect-nest` (the parent's own blocks touch memory, as in
  LoopInterchange's "tightly nested" check), `confused` (DependenceAnalysis
  could not describe a pair) or `unsupported-memop`.
  `bounds=depend-on-parent` marks a triangular nest (`i = j..N`): there the
  swap needs new bounds, and LLVM 20's pass cannot derive them. The `fix` text
  then says one of four things: the interchange is legal and
  `-mllvm -enable-loopinterchange` does it; it is legal but the bounds must be
  rewritten by hand (triangular); it is not legal; or legality is unknown. Tests: `test/interchange/`, with LLVM's
  own `loop-interchange` as the oracle. Two documented differences, both in
  tests:
  - **Overlapping arrays.** LLVM 20 drops confused dependences and
    interchanges anyway. `confused-miscompile.test` shows the result changing
    when the arrays overlap.
  - **Repetition loop.** LLVM 20 refuses when a loop outside the swapped pair
    has direction `*` (`outer-repetition.ll`, the TSVC shape), although the
    swap is legal.

  After a `blocker` line with a primary category, `evidence` quotes the facts
  that made the rule fire and `fix` suggests a source-level change, e.g.

  ```
      blocker primary=reduction rule=red-exact-fp secondary=none
      evidence fadd reduction %s.05 needs exact FP order
      fix allow reassociation: -ffast-math or -fassociative-math, or #pragma clang loop vectorize(enable)
  ```

  Fix verification: `scripts/verify_fixes.sh` applies each rule's suggested fix to
  a small example (`bench/fixes/<rule>/before.c` → `after.c`) and checks that
  LLVM 20 then vectorizes it; the result per rule is in
  `results/fix_verification.csv`. Every rule's fix is verified there except
  `recur-unsupported`, which has no mechanical fix (a true recurrence must be
  rewritten by hand).

  Second compiler: `scripts/gcc_compare.py` adds GCC 13's verdict and reason
  for each loop (`results/gcc_compare_*.csv`; summary in `docs/writeup.md`).

  Static estimate: `scripts/fix_mca.py` runs llvm-mca on the hot loop of
  each example before and after the fix and writes cycles per element plus
  their ratio to `results/fix_mca.csv`. It is a model, not a measurement: no
  caches, and no ratio when the loop contains a call.

  Not blockers: several exiting blocks when every exit is countable (LLVM 20
  accepts them on legality), switches, nested ifs and conditional stores (LLVM 20 if-converts
  them), a missing preheader (LoopVectorize simplifies loops itself), runtime
  pointer checks (it versions the loop), constant strides (interleave groups).
- `header=` is the header block as an IR operand (`%for.body`, `%1` when
  unnamed), the form `print<loops>` uses and the one inside SCEV text.

## PolyBench data collection

```bash
scripts/fetch_polybench.sh            # PolyBench/C 4.2.1-beta into bench/polybench (sha256 checked)
scripts/collect.sh --bench bench/polybench/polybench-c-4.2.1-beta \
  --out results/raw --summary results/collect_summary.csv
```

`collect.sh` compiles each of the 30 kernels with `clang-20 -O3 -g` and the
plugin, keeping per kernel the optimization record (LoopVectorize and LoopLens
remarks) and LoopLens's JSON Lines in `results/raw/` (not committed), plus
`manifest.csv` and `toolchain.txt`. The committed `results/collect_summary.csv`
counts, per kernel, LoopLens's innermost loops and LoopVectorize's per-loop
remarks; `results/collect_summary_toolchain.txt` records the compiler that
produced it.

Test fixtures are made with `scripts/make_fixture.sh` (the recipe above with
`-g0`, plus stripping of attributes and loop metadata; `--tbaa` keeps TBAA, which
LoopAccessAnalysis needs; `--g` keeps debug info for remark tests; `--o3` captures the IR exactly as LoopVectorize sees it
at `clang -O3`, needed wherever SimplifyCFG/InstCombine change the loop, e.g.
min/max and any-of reductions).

Input should be in the canonical form LoopVectorize sees (loop-simplify, LCSSA,
rotated; the recipe above produces it). LoopLens is an analysis and never
changes the IR, so it does not canonicalise loops itself; on other input its
facts describe the IR as given.
