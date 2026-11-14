//===- Classifier.cpp - Rule table: loop facts -> blocker categories ------===//

#include "Classifier.h"
#include "LoopRecord.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdlib>


using namespace llvm;

namespace looplens {

namespace {

struct Rule {
  const char *Id;
  Blocker Cat;
  bool (*Applies)(const LoopRecord &);
  std::string (*Evidence)(const LoopRecord &); // facts quoted from R
  std::string (*Fix)(const LoopRecord &);      // source-level advice
};

// --- Predicates (one per rule) -------------------------------------------

// LoopVectorize runs simplifyLoop itself, so a missing preheader or several
// latches is not a blocker; several *exiting* blocks are (early-exit loops
// are supported only in a narrow form in LLVM 20).
// LLVM 20 refuses uncountable early exits (PotentiallyFaultingEarlyExitLoop,
// WritesInEarlyExitLoop, or UncountableEarlyExitLoopsDisabled: the
// -enable-early-exit-vectorization flag is off by default).
bool uncountableEarlyExit(const LoopRecord &R) {
  return R.CFG.EarlyExit == "uncountable";
}

// Something if-conversion cannot predicate (NoCFGForSelect); reported
// before the instruction checks, so it outranks call-no-vector-form.
bool unpredicable(const LoopRecord &R) { return !R.CFG.Unpredicable.empty(); }

// LoopVectorize refuses a reduction that needs exact FP math unless ordered
// (in-order) reductions are enabled, which x86 does not do by default
// (CantReorderFPOps; LoopVectorizationLegality.cpp:1315-1333).
// A loop hint that forces vectorization (or a width > 1) allows reordering
// (LoopVectorizeHints::allowReordering, LoopVectorizationLegality.cpp:250).
// Otherwise an ordered reduction is still fine where the target enables
// ordered reductions (TTI::enableOrderedReductions, e.g. AArch64;
// LoopVectorize.cpp:10476-10483, canVectorizeFPMath).
bool exactFPReduction(const LoopRecord &R) {
  if (R.Hints.allowReordering())
    return false;
  return any_of(R.Recurs, [&](const RecurFacts &Rc) {
    return Rc.ExactFP && !(R.TargetOrderedReductions && Rc.Ordered);
  });
}

// A header phi that is neither induction, reduction nor fixed-order
// recurrence (NonReductionValueUsedOutsideLoop / UnsupportedPhi).
bool unsupportedPhi(const LoopRecord &R) {
  return any_of(R.Recurs,
                [](const RecurFacts &Rc) { return Rc.Kind == "unsupported"; });
}

// A call LoopVectorize cannot widen (CantVectorizeLibcall).
bool callWithoutVectorForm(const LoopRecord &R) {
  return any_of(R.Mem.Calls,
                [](const CallFacts &C) { return C.Vector == "no"; });
}

// A call that has a vector form (e.g. via -fveclib) but may write memory
// (errno): LoopAccessAnalysis refuses it (CantVectorizeInstruction).
bool callWritesMemory(const LoopRecord &R) {
  return any_of(R.Mem.Calls, [](const CallFacts &C) {
    return C.Vector != "no" && C.Vector != "intrinsic" && C.Mem == "write";
  });
}
std::string evCallWrites(const LoopRecord &R) {
  for (const CallFacts &C : R.Mem.Calls)
    if (C.Vector != "no" && C.Vector != "intrinsic" && C.Mem == "write")
      return "call to " + C.Callee + " has a vector variant (" + C.Vector +
             ") but may write memory";
  return "";
}
std::string fixCallWrites(const LoopRecord &R) {
  for (const CallFacts &C : R.Mem.Calls)
    if (C.MathLib)
      return "compile with -fno-math-errno (or -ffast-math) so the math call "
             "does not write errno";
  return "make the callee free of memory writes (e.g. "
         "__attribute__((const))) or move the call out of the loop";
}

// Volatile or atomic accesses (CantVectorizeInstruction / NonSimpleLoad).
bool nonSimpleAccess(const LoopRecord &R) { return !R.Mem.NonSimple.empty(); }

bool uncountable(const LoopRecord &R) {
  return (R.Trip.Kind == TripKind::Unknown &&
          R.Trip.Reason != "needs-scev-predicate") ||
         R.Mem.Report == "CantComputeNumberOfIterations";
}

bool unsafeDependence(const LoopRecord &R) {
  return R.Mem.Status == "unsafe" && R.Mem.Report == "UnsafeDep";
}

bool noRuntimeCheck(const LoopRecord &R) {
  return R.Mem.Report == "CantIdentifyArrayBounds" ||
         R.Mem.Report == "CantCheckMemDepsAtRunTime";
}

// Cost-model category: a gather/scatter, or a symbolic stride LAA will not
// version. Constant strides are not flagged: LoopVectorize vectorizes them
// as interleave groups (measured: stride 2 vectorized on x86-64).
bool gatherOrUnversionedStride(const LoopRecord &R) {
  // A forced loop (vectorize(enable/assume_safety), width > 1) is vectorized
  // without asking the cost model.
  if (R.Hints.forced())
    return false;
  return any_of(R.Mem.Accesses, [](const AccessFacts &A) {
    return (A.Kind == "indirect" && !A.GatherLegal) ||
           (A.Kind == "symbolic" && !A.Versioned);
  });
}

// vectorize(disable) / vectorize_width(1): the programmer asked for scalar.
bool hintDisabled(const LoopRecord &R) { return R.Hints.disabled(); }
std::string evHint(const LoopRecord &) {
  return "loop metadata asks for scalar code (#pragma clang loop vectorize(disable) "
         "or vectorize_width(1))";
}
std::string fixHint(const LoopRecord &) {
  return "remove the pragma if vector code is wanted";
}

// --- Evidence and fix text (one pair per rule; DECISIONS, README) --------
// Fix texts are worded for LLVM 20. Verified to make LLVM 20 vectorize the
// fixture: red-exact-fp (#pragma clang loop vectorize(enable)) and the
// math-library branch of call-no-vector-form (-fno-math-errno).

std::string evUncountableExit(const LoopRecord &R) {
  return std::to_string(R.CFG.Exits) + " exits; the exit from " +
         R.CFG.UncountableExit + " has no computable count";
}
std::string fixUncountableExit(const LoopRecord &) {
  return "LLVM 20 does not vectorize loops with an uncountable early exit by "
         "default; compute the exit index in a separate loop, or drop the "
         "early exit";
}

std::string evUnpredicable(const LoopRecord &R) {
  return R.CFG.Unpredicable + ", a block that needs predication";
}
std::string fixUnpredicable(const LoopRecord &) {
  return "move the call or access out of the if, or make it unconditional "
         "when that is safe";
}

const RecurFacts *firstRecur(const LoopRecord &R, bool (*P)(const RecurFacts &)) {
  for (const RecurFacts &Rc : R.Recurs)
    if (P(Rc))
      return &Rc;
  return nullptr;
}
bool isExactFP(const RecurFacts &Rc) { return Rc.ExactFP; } // for evidence
bool isUnsupported(const RecurFacts &Rc) { return Rc.Kind == "unsupported"; }

std::string evExactFP(const LoopRecord &R) {
  const RecurFacts *Rc = firstRecur(R, isExactFP);
  return Rc->Kind + " reduction " + Rc->Phi + " needs exact FP order";
}
std::string fixExactFP(const LoopRecord &) {
  return "allow reassociation: -ffast-math or -fassociative-math, or "
         "#pragma clang loop vectorize(enable)";
}

std::string evUnsupportedPhi(const LoopRecord &R) {
  return firstRecur(R, isUnsupported)->Phi +
         " is neither an induction, a reduction nor a recurrence";
}
std::string fixUnsupportedPhi(const LoopRecord &R) {
  return "rewrite the update of " + firstRecur(R, isUnsupported)->Phi +
         " as a sum/min/max of independent terms, or split it into its own "
         "loop";
}

const CallFacts &firstUnvectorizableCall(const LoopRecord &R) {
  return *find_if(R.Mem.Calls, [](const CallFacts &C) { return C.Vector == "no"; });
}
std::string evCall(const LoopRecord &R) {
  return "call to " + firstUnvectorizableCall(R).Callee + " has no vector form";
}
std::string fixCall(const LoopRecord &R) {
  const CallFacts &C = firstUnvectorizableCall(R);
  if (C.MathLib) // LLVM's own hint for math-library calls
    return "compile with -fno-math-errno (or -ffast-math), or provide a vector "
           "math library with -fveclib=";
  return "inline " + C.Callee +
         ", declare a vector variant (#pragma omp declare simd), or move the "
         "call out of the loop";
}

std::string evNonSimple(const LoopRecord &R) {
  const NonSimpleFacts &N = R.Mem.NonSimple.front();
  return N.Why + " " + N.Access;
}
std::string fixNonSimple(const LoopRecord &) {
  return "drop volatile/atomic if not required, or move the access out of the "
         "loop";
}

std::string evUncountable(const LoopRecord &R) {
  if (R.Trip.Kind == TripKind::Unknown)
    return "trip count unknown (" + R.Trip.Reason + ")";
  return "trip count unknown to LoopAccessAnalysis (" + R.Mem.Report + ")";
}
std::string fixUncountable(const LoopRecord &) {
  return "make the exit test compare the induction variable with a "
         "loop-invariant bound";
}

std::string evUnsafeDep(const LoopRecord &R) {
  // The first dependence that is not safe by itself.
  for (const DepFacts &D : R.Mem.Deps) {
    if (D.Kind == "Forward" || D.Kind == "BackwardVectorizable" ||
        D.Kind == "NoDep")
      continue;
    return D.Kind + " dependence " + D.Src + " -> " + D.Dst + ", distance " +
           (D.Dist == "none" ? std::string("unknown") : D.Dist + " bytes");
  }
  return "unsafe dependence (" + R.Mem.Report + ")";
}
std::string fixUnsafeDep(const LoopRecord &) {
  return "the loop carries a value between iterations; restructure it (e.g. "
         "a separate scan), or make the dependence distance at least the vector "
         "length";
}

std::string evNoRuntimeCheck(const LoopRecord &R) {
  return "LAA cannot build runtime alias checks (" + R.Mem.Report + ")";
}
std::string fixNoRuntimeCheck(const LoopRecord &) {
  return "if the pointers never overlap, mark them restrict or use "
         "#pragma clang loop vectorize(assume_safety)";
}

std::string evGather(const LoopRecord &R) {
  for (const AccessFacts &A : R.Mem.Accesses)
    if ((A.Kind == "indirect" && !A.GatherLegal) ||
        (A.Kind == "symbolic" && !A.Versioned))
      return A.Op + " " + A.Ptr + " is " + A.Kind +
             (A.Kind == "indirect" ? " and the target has no legal gather" : "");
  return "";
}
std::string fixGather(const LoopRecord &) {
  return "make the access contiguous (sort or transpose the data); gathers "
         "may pay off with -march=native";
}

// Cost model (heuristic, measured in results/): every access of the loop has a
// constant stride beyond the interleave-group factor (8 elements) and the
// target has no legal gather for it, so LoopVectorize would scalarise every
// access and its cost model rejects the loop (VectorizationNotBeneficial).
bool isBigStride(const AccessFacts &A) {
  if (A.Kind != "constant" || A.Stride.empty() || A.Stride[0] == '[')
    return false;
  long K = std::strtol(A.Stride.c_str(), nullptr, 10);
  return K > 8 || K < -8;
}
bool allAccessesStrided(const LoopRecord &R) {
  return !R.Hints.forced() && !R.Mem.Accesses.empty() &&
         all_of(R.Mem.Accesses, [](const AccessFacts &A) {
           return isBigStride(A) && !A.GatherLegal;
         });
}
std::string evAllStrided(const LoopRecord &R) {
  return "all " + std::to_string(R.Mem.Accesses.size()) +
         " memory accesses have a constant stride of more than 8 elements (" +
         R.Mem.Accesses.front().Stride + "), and the target has no legal gather";
}
// S26: specific when the interchange legality is known
// (LoopRecord::Interchange, from DependenceAnalysis direction vectors).
std::string fixAllStrided(const LoopRecord &R) {
  const InterchangeFacts &X = R.Interchange;
  if (X.Computed && X.Legal == "yes" && X.BoundsDependOnParent)
    return "interchange this loop with its parent loop by hand (legal: no "
           "dependence has direction (<,>); the inner bounds depend on the "
           "parent's index, so they must be rewritten)";
  if (X.Computed && X.Legal == "yes")
    return "interchange this loop with its parent loop (legal: no dependence "
           "has direction (<,>)); clang -mllvm -enable-loopinterchange lets "
           "LLVM do it";
  if (X.Computed && X.Legal == "no")
    return "interchange with the parent loop is not legal (a dependence has "
           "direction (<,>)); transpose the data so the innermost loop walks "
           "memory contiguously";
  std::string Fix = "interchange the loops or transpose the data so the "
                    "innermost loop walks memory contiguously";
  if (X.Computed)
    Fix += " (interchange legality unknown: " + X.Why + ")";
  return Fix;
}

// --- The table. Order = LoopVectorize's order of checks (DECISIONS). -----
//   1. loop CFG / early exits  2. phis and instructions (S09, S10)
//   3. countability  4. memory (LAA)  5. FP reordering (after legality)
//   6. cost model
// Several exiting blocks are not a rule: LLVM 20 accepts countable early
// exits on legality (test control-flow/countable-multi-exit.ll).
const Rule Rules[] = {
    // LoopVectorize reads the loop hints before any legality check.
    {"hint-vectorize-disabled", Blocker::Hint, hintDisabled, evHint, fixHint},
    {"cfg-uncountable-early-exit", Blocker::ControlFlow, uncountableEarlyExit,
     evUncountableExit, fixUncountableExit},
    {"cfg-unpredicable", Blocker::ControlFlow, unpredicable, evUnpredicable,
     fixUnpredicable},
    {"recur-unsupported", Blocker::Reduction, unsupportedPhi, evUnsupportedPhi,
     fixUnsupportedPhi},
    {"call-no-vector-form", Blocker::CallOrUnsafeMemOp, callWithoutVectorForm,
     evCall, fixCall},
    {"mem-non-simple", Blocker::CallOrUnsafeMemOp, nonSimpleAccess,
     evNonSimple, fixNonSimple},
    {"mem-call-writes", Blocker::CallOrUnsafeMemOp, callWritesMemory,
     evCallWrites, fixCallWrites},
    {"trip-uncountable", Blocker::TripCount, uncountable, evUncountable,
     fixUncountable},
    {"mem-unsafe-dep", Blocker::LoopCarriedDependence, unsafeDependence,
     evUnsafeDep, fixUnsafeDep},
    {"mem-no-runtime-check", Blocker::Aliasing, noRuntimeCheck,
     evNoRuntimeCheck, fixNoRuntimeCheck},
    // After legality: LoopVectorizePass::processLoop asks about exact FP
    // math only once LoopVectorizationLegality::canVectorize has passed
    // (LoopVectorize.cpp:10485), so an unsafe dependence is reported first.
    {"red-exact-fp", Blocker::Reduction, exactFPReduction, evExactFP,
     fixExactFP},
    {"stride-gather", Blocker::Stride, gatherOrUnversionedStride, evGather,
     fixGather},
    {"cost-strided", Blocker::Stride, allAccessesStrided, evAllStrided,
     fixAllStrided},
};

} // namespace

const char *blockerName(Blocker B) {
  switch (B) {
  case Blocker::ControlFlow:
    return "control-flow";
  case Blocker::Reduction:
    return "reduction";
  case Blocker::CallOrUnsafeMemOp:
    return "call-or-unsafe-memop";
  case Blocker::TripCount:
    return "trip-count";
  case Blocker::LoopCarriedDependence:
    return "loop-carried-dependence";
  case Blocker::Aliasing:
    return "aliasing";
  case Blocker::Stride:
    return "stride";
  case Blocker::Hint:
    return "hint";
  case Blocker::None:
    return "none";
  }
  llvm_unreachable("bad Blocker");
}

Classification classify(const LoopRecord &R) {
  Classification C;
  if (!R.Mem.Analyzed) // outer loop: LoopVectorize's inner-loop path skips it
    return C;
  C.Analyzed = true;
  for (const Rule &Ru : Rules) {
    if (!Ru.Applies(R))
      continue;
    if (C.Primary == Blocker::None) {
      C.Primary = Ru.Cat;
      C.RuleId = Ru.Id;
      C.Evidence = Ru.Evidence(R);
      C.Fix = Ru.Fix(R);
    } else if (Ru.Cat != C.Primary && !is_contained(C.Secondary, Ru.Cat)) {
      C.Secondary.push_back(Ru.Cat);
    }
  }
  return C;
}

void printClassification(raw_ostream &OS, const Classification &C) {
  if (!C.Analyzed) {
    OS << "    blocker <not-innermost>\n";
    return;
  }
  OS << "    blocker primary=" << blockerName(C.Primary) << " rule=" << C.RuleId
     << " secondary=";
  if (C.Secondary.empty())
    OS << "none";
  ListSeparator LS(",");
  for (Blocker B : C.Secondary)
    OS << LS << blockerName(B);
  OS << '\n';
  if (C.Primary == Blocker::None)
    return;
  OS << "    evidence " << C.Evidence << '\n';
  OS << "    fix " << C.Fix << '\n';
}

} // namespace looplens
