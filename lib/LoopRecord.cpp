//===- LoopRecord.cpp - Per-loop facts collected by LoopLens -------------===//

#include "LoopRecord.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DebugLoc.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/ModuleSlotTracker.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace looplens {

namespace {

std::string scevStr(const SCEV *S) {
  std::string Str;
  raw_string_ostream OS(Str);
  OS << *S; // constants print without type ("99"); print<scalar-evolution>
            // adds it ("i32 99")
  return Str;
}

// Why ScalarEvolution could not compute the exact BTC. Coarse, structural
// reasons, first match wins; the precise blocker is the classifier's job.
std::string unknownTripReason(const Loop &L, ScalarEvolution &SE) {
  // Without a preheader / single latch SCEV builds no add-recurrences at all.
  if (!L.isLoopSimplifyForm())
    return "not-simplify-form";
  BasicBlock *Exiting = L.getExitingBlock();
  if (!Exiting)
    return "multiple-exits";
  // Single exit: is the exit condition built from values SCEV can describe
  // (loop-invariant, or an add-recurrence of this loop)? A loaded value is
  // neither -> data-dependent exit.
  auto *Br = dyn_cast<BranchInst>(Exiting->getTerminator());
  if (Br && Br->isConditional())
    if (auto *Cmp = dyn_cast<ICmpInst>(Br->getCondition()))
      for (Value *Op : Cmp->operands()) {
        if (!SE.isSCEVable(Op->getType()))
          return "exit-cond-not-affine";
        const SCEV *S = SE.getSCEV(Op);
        auto *AR = dyn_cast<SCEVAddRecExpr>(S);
        if (!SE.isLoopInvariant(S, &L) && !(AR && AR->getLoop() == &L))
          return "exit-cond-not-affine";
      }
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
  } else if (isa<SCEVConstant>(BTC)) {
    T.Kind = TripKind::Constant;
    // Trip count = BTC + 1 in a type one bit wider, so BTC = 2^N - 1 does
    // not wrap to 0.
    const SCEV *TC = SE.getTripCountFromExitCount(BTC);
    if (auto *C = dyn_cast<SCEVConstant>(TC)) {
      T.Count.clear();
      raw_string_ostream OS(T.Count);
      C->getAPInt().print(OS, /*isSigned=*/false);
    }
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
