# LoopLens design decisions

One line per decision: date, decision, reason.

- 2026-11-06 — Pin LLVM 20 (apt.llvm.org), even though LLVM 23 is current. Reason: brief fixes LLVM 20; the APIs used are stable; avoids chasing release changes before the MVP gate. Revisit after v0.1.
- 2026-11-12 — Install LLVM 20 from Ubuntu 24.04 noble-updates (20.1.2), not apt.llvm.org (20.1.8). Reason: Ubuntu's libllvm20 is already installed system-wide and apt.llvm.org's clang-20 needs a different exact libllvm20 build, so apt refuses to install it. LLVM's API is stable within the 20.x series, so the minor version difference does not matter. CI uses the same packages. Every results file records `opt --version`.
- 2026-11-06 — `looplens-analyze` is a function pass, not a loop pass. Reason: LoopAccessAnalysis and the JSON report want a whole-function view; avoids LoopPassManager canonicalization surprises.
- 2026-11-06 — Iterate loops with `LoopInfo::getLoopsInPreorder()`. Reason: deterministic order (outer before inner, siblings in program order) for FileCheck tests.
- 2026-11-06 — `isRequired() = true`. Reason: the pass is report-only and should also run on clang -O0 (optnone) IR.
- 2026-11-06 — Plugin is built as `LoopLens.so` with no `lib` prefix. Reason: matches `%shlibdir/LoopLens%shlibext` in lit tests.
- 2026-11-12 — `find_package(LLVM REQUIRED CONFIG)` without a version, then check `LLVM_VERSION_MAJOR`. Reason: LLVMConfigVersion.cmake accepts a request only on an exact major.minor match, so `find_package(LLVM 20)` rejects 20.1.x.
- 2026-11-12 — Two repos: a private working repo (planning notes and tooling) and a clean public repo `../looplens-public` produced by `.dev/commit_clean.sh`; only the public repo is pushed. Reason: keep planning notes and tooling out of the portfolio repo without losing their history.
- 2026-11-12 — Work cycle: keep two sub-milestones planned ahead, execute one, review it against its plan, revise the next plan and plan one more; commit after every execute and review. Reason: fast iteration with plans that learn from each execution.
- 2026-11-12 — No dates in the plan; dependency order only. Reason: finish as fast as possible; nothing is deferred because it looks far away.
- 2026-11-12 — Agreement is measured on PolyBench/C for the MVP; TSVC is added in S19 only if it costs at most one session. Reason: the brief lists TSVC under both the agreement objective and Phase 2.
- 2026-11-12 — DECISIONS.md stays in the public repo. Reason: a design log is useful evidence for reviewers and interviewers.
