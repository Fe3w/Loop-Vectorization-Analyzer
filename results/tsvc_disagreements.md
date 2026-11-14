# Disagreements between LoopLens and LoopVectorize (TSVC_2)

Source of truth: `results/tsvc_agreement.csv` (rows with `agree=no`), produced by
`scripts/agreement.py --prefix tsvc_` from `scripts/collect.sh --list` output. TSVC was not used to
tune LoopLens at first (held-out check, `results/tsvc_agreement_summary_before.csv`); in session 10
the `cost-strided` rule was derived from TSVC's cost-model misses (5 loops), so TSVC is no longer
held out for that rule.

## Remaining

| Loop | LoopVectorize | LoopLens primary | Class |
| --- | --- | --- | --- |
| tsvc.c:568 (s128) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1498 (s253) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1602 (s257) | `` | stride | cost model, not predicted |
| tsvc.c:1703 (s272) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1753 (s274) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1829 (s276) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1886 (s278) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1916 (s279) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1977 (s2710) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:1977 (s2710) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:3169 (s441) | `VectorizationNotBeneficial` | none | cost model, not predicted |
| tsvc.c:3197 (s442) | `VectorizationNotBeneficial` | none | cost model, not predicted |

All remaining disagreements are cost-model rejections (`VectorizationNotBeneficial`): legality
passed and LoopVectorize decided vectorization does not pay off on generic x86-64. LoopLens has no
full cost model; its cost rules (`stride-gather`, `cost-strided`) do not apply to these loops (mostly
predicated stores and short bodies; a TTI cost estimate was tried and rejected, see
docs/PROGRESS.md session 10). Not a
LoopLens bug; a cost-model rule is future work.

The two loops of `s2710` share one source location (line 1977, column 9); they are paired by order
(`match=both-by-order`; LoopVectorize visits innermost loops in program order, as LoopLens reports
them).

## Fixed in the scorer (class (c)), found on TSVC

The first scorer run on TSVC (`results/tsvc_agreement_summary_before.csv`: 155 loops
matched, 148 agree, 25 LoopLens-only) mis-attributed remarks:
LoopVectorizePass reports some verdicts *without* a following `MissedDetails` —
`VectorizationNotBeneficial` (cost model) and, after legality, `UncountableEarlyExitLoopsDisabled`,
`UncountableEarlyExitUnsupported`, `StructCallVectorizationUnsupported`
(LoopVectorize.cpp:10366-10410). The scorer took them as reasons of the *next* loop. They now close
their own loop (test `test/scripts/agreement-not-beneficial.test`). PolyBench has none of these
remarks; its result is unchanged.
