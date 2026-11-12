//===- LoopRecord.cpp - Per-loop facts collected by LoopLens -------------===//

#include "LoopRecord.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DebugLoc.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/PatternMatch.h"
#include "llvm/IR/ModuleSlotTracker.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;
using namespace llvm::PatternMatch;

namespace looplens {

namespace {

std::string scevStr(const SCEV *S) {
  std::string Str;
  raw_string_ostream OS(Str);
  OS << *S; // constants print without type ("99"); print<scalar-evolution>
            // adds it ("i32 99")
  return Str;
}

// True if S is something SCEV can reason about in L's exit condition:
// loop-invariant, or an AFFINE add-recurrence {a,+,b} of L. Integer casts are
// looked through: an affine IV under a sext/zext that SCEV could not fold is
// still affine (whether it may wrap is the predicate question, asked first).
bool isAffineOrInvariant(const SCEV *S, const Loop &L, ScalarEvolution &SE) {
  while (auto *Cast = dyn_cast<SCEVCastExpr>(S))
    S = Cast->getOperand(0);
  if (SE.isLoopInvariant(S, &L))
    return true;
  auto *AR = dyn_cast<SCEVAddRecExpr>(S);
  return AR && AR->getLoop() == &L && AR->isAffine();
}

// Why ScalarEvolution could not compute the exact BTC. A closed list, first
// match wins; precise blockers and evidence are the classifier's job (S08+).
// Assumes canonical input (loop-simplify/LCSSA/rotate, as LoopVectorize sees
// it): loop shape is reported elsewhere and is not a reason here.
std::string unknownTripReason(const Loop &L, ScalarEvolution &SE) {
  BasicBlock *Exiting = L.getExitingBlock();
  if (!Exiting)
    return "multiple-exits";

  // Computable once SCEV may assume no-wrap (or similar) predicates, which a
  // runtime check can guarantee; LoopVectorize asks the same question via
  // PredicatedScalarEvolution.
  SmallVector<const SCEVPredicate *, 4> Preds;
  if (!isa<SCEVCouldNotCompute>(SE.getPredicatedBackedgeTakenCount(&L, Preds)))
    return "needs-scev-predicate";

  auto *Br = dyn_cast<BranchInst>(Exiting->getTerminator());
  if (!Br || !Br->isConditional())
    return "other";

  // Split logical and/or (`a && b` is lowered to `select a, b, false`) into
  // their leaf conditions.
  SmallVector<Value *, 4> Work{Br->getCondition()}, Leaves;
  while (!Work.empty()) {
    Value *V = Work.pop_back_val();
    Value *A, *B;
    if (match(V, m_LogicalAnd(m_Value(A), m_Value(B))) ||
        match(V, m_LogicalOr(m_Value(A), m_Value(B)))) {
      Work.push_back(A);
      Work.push_back(B);
    } else {
      Leaves.push_back(V);
    }
  }

  bool SawNonICmp = false;
  for (Value *Leaf : Leaves) {
    if (auto *Cmp = dyn_cast<ICmpInst>(Leaf)) {
      // icmp operands are integers or pointers, always SCEVable.
      for (Value *Op : Cmp->operands())
        if (!isAffineOrInvariant(SE.getSCEV(Op), L, SE))
          return "exit-cond-not-affine"; // e.g. a loaded value
    } else if (!L.isLoopInvariant(Leaf)) {
      SawNonICmp = true; // fcmp, or an i1 that is not a compare
    }
  }
  return SawNonICmp ? "exit-cond-not-icmp" : "other";
}

TripFacts makeTripFacts(const Loop &L, ScalarEvolution &SE) {
  TripFacts T;
  // LLVM 20: getBackedgeTakenCount(L, ExitCountKind). The getSmallConstant*
  // helpers are not used: getSmallConstantTripCount returns 0 above 2^32 and
  // getSmallConstantMaxTripCount returns 0 for any 64-bit maximum.
  const SCEV *BTC = SE.getBackedgeTakenCount(&L);
  T.BTC = scevStr(BTC);
  T.MaxBTC = scevStr(SE.getConstantMaxBackedgeTakenCount(&L));
  T.SymMaxBTC = scevStr(SE.getSymbolicMaxBackedgeTakenCount(&L));

  if (isa<SCEVCouldNotCompute>(BTC)) {
    T.Kind = TripKind::Unknown;
    T.Reason = unknownTripReason(L, SE);
  } else if (auto *C = dyn_cast<SCEVConstant>(BTC)) {
    T.Kind = TripKind::Constant;
    // Trip count = BTC + 1, computed one bit wider so BTC = 2^N - 1 does not
    // wrap to 0. Done on the APInt directly, so Constant always has a count.
    const APInt &B = C->getAPInt();
    APInt TC = B.zext(B.getBitWidth() + 1) + 1;
    T.Count.clear();
    raw_string_ostream OS(T.Count);
    TC.print(OS, /*isSigned=*/false);
  } else {
    T.Kind = TripKind::Symbolic;
  }
  return T;
}

const char *tripKindName(TripKind K) {
  switch (K) {
  case TripKind::Constant:
    return "constant";
  case TripKind::Symbolic:
    return "symbolic";
  case TripKind::Unknown:
    return "unknown";
  }
  llvm_unreachable("bad TripKind");
}

} // namespace

LoopRecord makeLoopRecord(const Function &F, const Loop &L,
                          ModuleSlotTracker &MST, ScalarEvolution &SE) {
  LoopRecord R;
  R.Function = F.getName().str();
  R.Depth = L.getLoopDepth();

  // Unnamed blocks print as their slot number ("%1"), the same form
  // `opt -passes='print<loops>'` uses.
  const BasicBlock *H = L.getHeader();
  if (H->hasName()) {
    R.Header = H->getName().str();
  } else {
    raw_string_ostream OS(R.Header);
    H->printAsOperand(OS, /*PrintType=*/false, MST);
  }

  // Loop::getStartLoc() is the location LoopVectorize puts in its remarks, so
  // LoopLens and LLVM agree on file:line:col by construction. Lookup order
  // (LLVM 20, found by experiment; the header comment in LoopInfo.h only
  // mentions the last two): LoopID's first DILocation -> preheader terminator
  // -> header terminator.
  if (DebugLoc DL = L.getStartLoc()) {
    R.HasLoc = true;
    R.File = DL->getFilename().str(); // file name only, like remark YAML
    R.Line = DL.getLine();
    R.Col = DL.getCol();
  }
  R.Trip = makeTripFacts(L, SE);
  return R;
}

void printLoopRecord(raw_ostream &OS, const LoopRecord &R) {
  OS << "  loop header=" << R.Header << " depth=" << R.Depth << " loc=";
  if (R.hasLoc())
    OS << R.File << ':' << R.Line << ':' << R.Col;
  else
    OS << "<none>";
  OS << '\n';

  const TripFacts &T = R.Trip;
  OS << "    trip kind=" << tripKindName(T.Kind);
  if (T.Kind == TripKind::Unknown)
    OS << " reason=" << T.Reason;
  OS << " count=" << T.Count << " btc=[" << T.BTC << "] max-btc=[" << T.MaxBTC
     << "] symbolic-max-btc=[" << T.SymMaxBTC << "]\n";
}

} // namespace looplens
