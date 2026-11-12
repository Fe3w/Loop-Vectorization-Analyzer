//===- LoopRecord.cpp - Per-loop facts collected by LoopLens -------------===//

#include "LoopRecord.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DebugLoc.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRPrintingPasses.h"
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

// Why ScalarEvolution could not compute the exact BTC. A closed list; the
// order below is the precedence. Precise blockers and evidence are the
// classifier's job (S08+). Assumes canonical input (loop-simplify/LCSSA/rotate,
// as LoopVectorize sees it): loop shape is reported elsewhere, not here.
std::string unknownTripReason(const Loop &L, ScalarEvolution &SE) {
  SmallVector<BasicBlock *, 4> Exiting;
  L.getExitingBlocks(Exiting);
  // 1. No exit at all (while (1)). getExitingBlock() is null here too, so it
  //    must be told apart from several exits.
  if (Exiting.empty())
    return "no-exit";

  // 2. Computable once SCEV may assume no-wrap (or similar) predicates, which
  //    a runtime check can guarantee -- for one exit or several. LoopVectorize
  //    asks the same question via PredicatedScalarEvolution.
  SmallVector<const SCEVPredicate *, 4> Preds;
  if (!isa<SCEVCouldNotCompute>(SE.getPredicatedBackedgeTakenCount(&L, Preds)))
    return "needs-scev-predicate";

  // 3. Several exits and not countable even with predicates.
  if (Exiting.size() > 1)
    return "multiple-exits";

  // 4./5. Single exit: inspect every leaf condition of the exit, then decide
  //    by precedence (not-affine > not-icmp), independent of operand order.
  Instruction *Term = Exiting.front()->getTerminator();
  bool NotAffine = false, NonICmp = false;
  auto CheckOperand = [&](Value *Op) {
    if (!isAffineOrInvariant(SE.getSCEV(Op), L, SE))
      NotAffine = true; // e.g. a loaded value
  };

  if (auto *SI = dyn_cast<SwitchInst>(Term)) {
    // A switch is an implicit icmp eq of its condition against each
    // (constant) case value.
    CheckOperand(SI->getCondition());
  } else if (auto *Br = dyn_cast<BranchInst>(Term); Br && Br->isConditional()) {
    // Split logical and/or (`a && b` is lowered to `select a, b, false`) and
    // look through `not` (xor true) and freeze, down to the leaf conditions.
    SmallVector<Value *, 4> Work{Br->getCondition()};
    while (!Work.empty()) {
      Value *V = Work.pop_back_val();
      Value *A, *B;
      if (match(V, m_LogicalAnd(m_Value(A), m_Value(B))) ||
          match(V, m_LogicalOr(m_Value(A), m_Value(B)))) {
        Work.push_back(A);
        Work.push_back(B);
      } else if (match(V, m_Not(m_Value(A)))) {
        Work.push_back(A);
      } else if (auto *Fr = dyn_cast<FreezeInst>(V)) {
        Work.push_back(Fr->getOperand(0));
      } else if (auto *Cmp = dyn_cast<ICmpInst>(V)) {
        // icmp operands are integers or pointers, always SCEVable.
        for (Value *Op : Cmp->operands())
          CheckOperand(Op);
      } else if (!L.isLoopInvariant(V)) {
        NonICmp = true; // fcmp, or an i1 that is not a compare
      }
    }
  }
  if (NotAffine)
    return "exit-cond-not-affine";
  if (NonICmp)
    return "exit-cond-not-icmp";
  return "other";
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
                          std::unique_ptr<ModuleSlotTracker> &MST,
                          ScalarEvolution &SE) {
  LoopRecord R;
  R.Function = F.getName().str();
  R.Depth = L.getLoopDepth();

  // Header as an IR operand, always with '%' ("%for.body", "%1"): the form
  // print<loops> uses and the one inside SCEV text ("<%for.body>").
  const BasicBlock *H = L.getHeader();
  raw_string_ostream HOS(R.Header);
  if (H->hasName()) {
    HOS << '%';
    printLLVMNameWithoutPrefix(HOS, H->getName()); // quotes odd names
  } else {
    // Unnamed blocks need slot numbers. Build the tracker only on first use
    // and without module-wide metadata, so modules without unnamed headers
    // pay nothing and the cost is not O(#functions x module size).
    if (!MST) {
      MST = std::make_unique<ModuleSlotTracker>(
          F.getParent(), /*ShouldInitializeAllMetadata=*/false);
      MST->incorporateFunction(F);
    }
    H->printAsOperand(HOS, /*PrintType=*/false, *MST);
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
