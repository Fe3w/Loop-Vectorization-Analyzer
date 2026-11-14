//===- LoopRecord.cpp - Per-loop facts collected by LoopLens -------------===//

#include "LoopRecord.h"

#include "llvm/Analysis/DependenceAnalysis.h"
#include "llvm/Analysis/IVDescriptors.h"
#include "llvm/Analysis/LoopAccessAnalysis.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/Analysis/VectorUtils.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DebugLoc.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRPrintingPasses.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/PatternMatch.h"
#include "llvm/IR/ModuleSlotTracker.h"
#include "llvm/ADT/StringExtras.h"
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

// A value as an IR operand without type: "%name", "%3", "0", "@g".
// Named locals print directly; anything else (unnamed values need slot
// numbers, constants and globals go through the AsmWriter) uses the
// function's lazily created ModuleSlotTracker, so nothing builds a fresh
// module-wide slot table per call.
std::string operandStr(const Value &V, const Function &F,
                       std::unique_ptr<ModuleSlotTracker> &MST) {
  std::string Str;
  raw_string_ostream OS(Str);
  if (V.hasName() && !isa<GlobalValue>(V)) {
    OS << '%';
    printLLVMNameWithoutPrefix(OS, V.getName()); // quotes odd names
    return Str;
  }
  if (!MST) {
    MST = std::make_unique<ModuleSlotTracker>(
        F.getParent(), /*ShouldInitializeAllMetadata=*/false);
    MST->incorporateFunction(F);
  }
  V.printAsOperand(OS, /*PrintType=*/false, *MST);
  return Str;
}

const char *ivKindName(InductionDescriptor::InductionKind K) {
  switch (K) {
  case InductionDescriptor::IK_IntInduction:
    return "int";
  case InductionDescriptor::IK_PtrInduction:
    return "ptr";
  case InductionDescriptor::IK_FpInduction:
    return "fp";
  case InductionDescriptor::IK_NoInduction:
    break;
  }
  llvm_unreachable("not an induction");
}

// Every header phi that InductionDescriptor accepts, in header order.
// SE overload of isInductionPHI: what is provable without SCEV predicates.
// (LoopVectorize uses the PredicatedScalarEvolution overload, which may also
// accept a phi under a runtime no-wrap check.)
// Empty if the loop has no preheader: InductionDescriptor cannot be asked
// then (see below), and the caller prints "iv <no-preheader>".
std::vector<IVFacts> makeIVFacts(const Function &F, const Loop &L,
                                 ScalarEvolution &SE,
                                 std::unique_ptr<ModuleSlotTracker> &MST) {
  std::vector<IVFacts> IVs;
  // LLVM 20: isInductionPHI reads the start value from the preheader edge
  // without checking that a preheader exists, and crashes (segfault) on a
  // header phi that SCEV sees as an add-recurrence of a loop without one.
  // LoopVectorize never asks then: it requires loop-simplify form.
  if (!L.getLoopPreheader())
    return IVs;
  // Only the phi feeding the latch compare (LLVM 20, LoopInfo.h:255).
  PHINode *ExitIV = L.getInductionVariable(SE);
  for (PHINode &Phi : L.getHeader()->phis()) {
    InductionDescriptor D;
    if (!InductionDescriptor::isInductionPHI(&Phi, &L, &SE, D))
      continue;
    IVFacts IV;
    IV.Phi = operandStr(Phi, F, MST);
    IV.Kind = ivKindName(D.getKind());
    IV.Start = operandStr(*D.getStartValue(), F, MST);
    IV.Step = scevStr(D.getStep());
    IV.SCEV = scevStr(SE.getSCEV(&Phi));
    IV.ControlsExit = &Phi == ExitIV;
    IVs.push_back(std::move(IV));
  }
  return IVs;
}

const char *recurKindName(RecurKind K) {
  switch (K) {
  case RecurKind::None: return "none";
  case RecurKind::Add: return "add";
  case RecurKind::Mul: return "mul";
  case RecurKind::Or: return "or";
  case RecurKind::And: return "and";
  case RecurKind::Xor: return "xor";
  case RecurKind::SMin: return "smin";
  case RecurKind::SMax: return "smax";
  case RecurKind::UMin: return "umin";
  case RecurKind::UMax: return "umax";
  case RecurKind::FAdd: return "fadd";
  case RecurKind::FMul: return "fmul";
  case RecurKind::FMin: return "fmin";
  case RecurKind::FMax: return "fmax";
  case RecurKind::FMinimum: return "fminimum";
  case RecurKind::FMaximum: return "fmaximum";
  case RecurKind::FMulAdd: return "fmuladd";
  case RecurKind::IAnyOf: return "ianyof";
  case RecurKind::FAnyOf: return "fanyof";
  case RecurKind::IFindLastIV: return "ifindlastiv"; // new in LLVM 20
  case RecurKind::FFindLastIV: return "ffindlastiv"; // new in LLVM 20
  }
  llvm_unreachable("bad RecurKind");
}

// Every header phi that is not an induction, classified the way
// LoopVectorizationLegality::canVectorizeInstrs does: reduction first, then
// fixed-order recurrence, else unsupported.
std::vector<RecurFacts> makeRecurFacts(const Function &F, Loop &L,
                                       ScalarEvolution &SE, DominatorTree &DT,
                                       const std::vector<IVFacts> &IVs,
                                       std::unique_ptr<ModuleSlotTracker> &MST) {
  std::vector<RecurFacts> Rs;
  // LLVM 20: like isInductionPHI, AddReductionVar reads the start value from
  // the preheader edge unchecked (IVDescriptors.cpp:227).
  if (!L.getLoopPreheader())
    return Rs;
  for (PHINode &Phi : L.getHeader()->phis()) {
    std::string Name = operandStr(Phi, F, MST);
    if (any_of(IVs, [&](const IVFacts &IV) { return IV.Phi == Name; }))
      continue;
    RecurFacts R;
    R.Phi = Name;
    RecurrenceDescriptor RD;
    if (RecurrenceDescriptor::isReductionPHI(&Phi, &L, RD, /*DB=*/nullptr,
                                             /*AC=*/nullptr, &DT, &SE)) {
      R.Kind = recurKindName(RD.getRecurrenceKind());
      R.ExactFP = RD.hasExactFPMath();
      R.Ordered = RD.isOrdered();
    } else if (RecurrenceDescriptor::isFixedOrderRecurrence(&Phi, &L, &DT)) {
      // Renamed from isFirstOrderRecurrence in LLVM 16.
      R.Kind = "fixed-order";
    } else {
      R.Kind = "unsupported";
    }
    Rs.push_back(std::move(R));
  }
  return Rs;
}

FormFacts makeFormFacts(const Loop &L, const DominatorTree &DT) {
  FormFacts Fm;
  Fm.Simplify = L.isLoopSimplifyForm();
  Fm.Rotated = L.isRotatedForm();
  Fm.LCSSA = L.isLCSSAForm(DT);
  Fm.SingleExiting = L.getExitingBlock() != nullptr;
  Fm.Innermost = L.isInnermost();
  Fm.Guarded = L.isGuarded();
  return Fm;
}

std::string accessStr(const Instruction &I, const Function &F,
                      std::unique_ptr<ModuleSlotTracker> &MST) {
  return std::string(isa<StoreInst>(I) ? "store:" : "load:") +
         operandStr(*getLoadStorePointerOperand(&I), F, MST);
}

// address(Dst) - address(Src) in bytes, or "none". MemoryDepChecker computes
// this internally (getDependenceDistanceStrideAndSize) but LLVM 20's
// Dependence has no distance field, so LoopLens recomputes it -- only for two
// affine add-recurrences of L with equal steps, where the difference is the
// same in every iteration. (Identical pointers like a[idx[i]] would give 0,
// which says nothing about other iterations.)
std::string depDistance(const Instruction &Src, const Instruction &Dst,
                        const Loop &L, ScalarEvolution &SE) {
  auto *A = dyn_cast<SCEVAddRecExpr>(
      SE.getSCEV(const_cast<Value *>(getLoadStorePointerOperand(&Src))));
  auto *B = dyn_cast<SCEVAddRecExpr>(
      SE.getSCEV(const_cast<Value *>(getLoadStorePointerOperand(&Dst))));
  if (!A || !B || A->getLoop() != &L || B->getLoop() != &L || !A->isAffine() ||
      !B->isAffine() || A->getStepRecurrence(SE) != B->getStepRecurrence(SE))
    return "none";
  return scevStr(SE.getMinusSCEV(B, A));
}

// True if S mentions a value loaded inside L: the address depends on data
// read in the loop (a[idx[i]]), so it is a gather/scatter, not a stride.
bool dependsOnLoadInLoop(const SCEV *S, const Loop &L) {
  return SCEVExprContains(S, [&](const SCEV *E) {
    auto *U = dyn_cast<SCEVUnknown>(E);
    auto *LI = U ? dyn_cast<LoadInst>(U->getValue()) : nullptr;
    return LI && L.contains(LI);
  });
}

// Whether the target has a legal masked gather (load) / scatter (store) for
// this access's element type, asked for a 256-bit vector (a VF LoopVectorize
// considers on every target measured).
bool gatherLegal(const Instruction &I, const Function &F,
                 const TargetTransformInfo &TTI) {
  Type *Elt = getLoadStoreType(&I);
  if (!(Elt->isIntegerTy() || Elt->isFloatingPointTy() || Elt->isPointerTy()))
    return false;
  unsigned Bits =
      std::max<unsigned>(8, F.getDataLayout().getTypeSizeInBits(Elt));
  auto *VT = FixedVectorType::get(Elt, std::max(2u, 256 / Bits));
  Align Al = getLoadStoreAlignment(&I);
  return isa<LoadInst>(I) ? TTI.isLegalMaskedGather(VT, Al)
                          : TTI.isLegalMaskedScatter(VT, Al);
}

// Stride classification of one load/store (order of the checks = DECISIONS).
AccessFacts makeAccessFact(const Instruction &I, const Function &F,
                           const Loop &L, ScalarEvolution &SE,
                           const LoopAccessInfo &LAI,
                           const TargetTransformInfo &TTI,
                           std::unique_ptr<ModuleSlotTracker> &MST) {
  AccessFacts A;
  A.Op = isa<StoreInst>(I) ? "store" : "load";
  Value *Ptr = const_cast<Value *>(getLoadStorePointerOperand(&I));
  A.Ptr = operandStr(*Ptr, F, MST);
  const SCEV *S = SE.getSCEV(Ptr);
  uint64_t Elt = F.getDataLayout().getTypeAllocSize(getLoadStoreType(&I));

  if (SE.isLoopInvariant(S, &L)) {
    A.Kind = "uniform";
    A.Stride = "0";
    return A;
  }
  auto *AR = dyn_cast<SCEVAddRecExpr>(S);
  if (AR && AR->getLoop() == &L && AR->isAffine()) {
    const SCEV *Step = AR->getStepRecurrence(SE);
    if (auto *C = dyn_cast<SCEVConstant>(Step)) {
      int64_t Bytes = C->getAPInt().getSExtValue();
      if (Elt && Bytes % int64_t(Elt) == 0) {
        int64_t K = Bytes / int64_t(Elt);
        A.Kind = K == 1 ? "unit" : K == -1 ? "reverse" : "constant";
        A.Stride = std::to_string(K);
        // Beyond LoopVectorize's interleave-group factor (8) a strided access
        // is lowered as a gather/scatter or scalarised.
        if (K > 8 || K < -8)
          A.GatherLegal = gatherLegal(I, F, TTI);
      } else {
        A.Kind = "constant";
        A.Stride = "[" + scevStr(Step) + "]";
      }
      return A;
    }
    if (SE.isLoopInvariant(Step, &L)) {
      A.Kind = "symbolic";
      A.Stride = "[" + scevStr(Step) + "]";
      A.Versioned = LAI.getSymbolicStrides().count(Ptr);
      return A;
    }
  }
  A.Kind = dependsOnLoadInLoop(S, L) ? "indirect" : "unknown";
  A.Stride = "none";
  if (A.Kind == "indirect")
    A.GatherLegal = gatherLegal(I, F, TTI);
  return A;
}

// The call test of LoopVectorizationLegality::canVectorizeInstrs (LLVM 20).
// LV's `isTLIScalarize` is a static helper in its .cpp; LoopLens uses
// TLI.isFunctionVectorizable(name), which agrees with it for the default
// (empty) vector library.
CallFacts makeCallFact(const CallInst &CI, const Function &F,
                       const TargetLibraryInfo &TLI,
                       std::unique_ptr<ModuleSlotTracker> &MST) {
  CallFacts C;
  const Function *Callee = CI.getCalledFunction();
  C.Callee = Callee ? operandStr(*Callee, F, MST) : "indirect";
  if (getVectorIntrinsicIDForCall(&CI, &TLI))
    C.Vector = "intrinsic";
  else if (Callee && !VFDatabase::getMappings(CI).empty())
    C.Vector = "vfabi";
  else if (Callee && TLI.isFunctionVectorizable(Callee->getName()))
    C.Vector = "tli";
  else
    C.Vector = "no";
  C.Mem = CI.mayWriteToMemory() ? "write"
          : CI.mayReadFromMemory() ? "read"
                                   : "none";
  LibFunc Func;
  C.MathLib = C.Vector != "intrinsic" && Callee && CI.getType()->isFloatingPointTy() &&
              TLI.getLibFunc(Callee->getName(), Func) &&
              TLI.hasOptimizedCodeGen(Func);
  return C;
}

bool isNonSimpleAccess(const Instruction &I) {
  if (auto *LI = dyn_cast<LoadInst>(&I))
    return !LI->isSimple();
  if (auto *SI = dyn_cast<StoreInst>(&I))
    return !SI->isSimple();
  return false;
}

CFGFacts makeCFGFacts(const Function &F, Loop &L, ScalarEvolution &SE,
                      DominatorTree &DT, const TargetLibraryInfo &TLI,
                      std::unique_ptr<ModuleSlotTracker> &MST) {
  CFGFacts C;
  if (!L.isInnermost())
    return C;
  C.Analyzed = true;
  BasicBlock *Latch = L.getLoopLatch();
  for (BasicBlock *BB : L.blocks()) {
    ++C.Blocks;
    if (isa<SwitchInst>(BB->getTerminator()))
      ++C.Switches;
    if (L.isLoopExiting(BB)) {
      ++C.Exits;
      if (BB != Latch &&
          isa<SCEVCouldNotCompute>(SE.getExitCount(&L, BB)) &&
          C.UncountableExit.empty())
        C.UncountableExit = operandStr(*BB, F, MST);
    }
    if (!LoopAccessInfo::blockNeedsPredication(BB, &L, &DT))
      continue;
    ++C.Predicated;
    // What if-conversion cannot predicate: a call LV cannot widen, or a
    // volatile/atomic access (LLVM reports NoCFGForSelect for these).
    for (Instruction &I : *BB) {
      if (!C.Unpredicable.empty())
        break;
      std::string Where = " in " + operandStr(*BB, F, MST);
      if (auto *CI = dyn_cast<CallInst>(&I)) {
        auto *II = dyn_cast<IntrinsicInst>(CI);
        if (isa<DbgInfoIntrinsic>(CI) || (II && II->isAssumeLikeIntrinsic()))
          continue;
        CallFacts CF = makeCallFact(*CI, F, TLI, MST);
        if (CF.Vector == "no")
          C.Unpredicable = "call to " + CF.Callee + Where;
      } else if (isNonSimpleAccess(I)) {
        C.Unpredicable = std::string(I.isAtomic() ? "atomic " : "volatile ") +
                         accessStr(I, F, MST) + Where;
      }
    }
  }
  if (C.Exits > 1)
    C.EarlyExit = C.UncountableExit.empty() ? "countable" : "uncountable";
  return C;
}

// Memory facts from LoopAccessAnalysis, innermost loops only (the loops
// LoopVectorize's inner-loop path analyses; for others LAA would only report
// "loop is not the innermost loop").
MemFacts makeMemFacts(const Function &F, Loop &L, LoopAccessInfoManager &LAIM,
                      ScalarEvolution &SE, const TargetLibraryInfo &TLI,
                      const TargetTransformInfo &TTI,
                      std::unique_ptr<ModuleSlotTracker> &MST) {
  MemFacts M;
  if (!L.isInnermost())
    return M;
  M.Analyzed = true;
  const LoopAccessInfo &LAI = LAIM.getInfo(L);
  const MemoryDepChecker &DC = LAI.getDepChecker();
  // Dependences first: unsafe loops (returned early below) need them most.
  if (const auto *Deps = DC.getDependences()) {
    for (const MemoryDepChecker::Dependence &D : *Deps) {
      const Instruction &Src = *D.getSource(DC), &Dst = *D.getDestination(DC);
      M.Deps.push_back({MemoryDepChecker::Dependence::DepName[D.Type],
                        accessStr(Src, F, MST), accessStr(Dst, F, MST),
                        depDistance(Src, Dst, L, SE)});
    }
  } else {
    M.DepsRecorded = false;
  }
  for (BasicBlock *BB : L.blocks())
    for (Instruction &I : *BB) {
      if (isa<LoadInst>(I) || isa<StoreInst>(I)) {
        M.Accesses.push_back(makeAccessFact(I, F, L, SE, LAI, TTI, MST));
        if (isNonSimpleAccess(I))
          M.NonSimple.push_back({accessStr(I, F, MST),
                                 I.isAtomic() ? "atomic" : "volatile"});
      } else if (auto *CI = dyn_cast<CallInst>(&I)) {
        // LV ignores debug intrinsics; assume-like ones (assume, lifetime,
        // pseudo-probe, ...) are dropped when vectorizing.
        auto *II = dyn_cast<IntrinsicInst>(CI);
        if (isa<DbgInfoIntrinsic>(CI) || (II && II->isAssumeLikeIntrinsic()))
          continue;
        M.Calls.push_back(makeCallFact(*CI, F, TLI, MST));
      }
    }
  if (const OptimizationRemarkAnalysis *R = LAI.getReport())
    M.Report = R->getRemarkName().str();
  M.Checks = LAI.getNumRuntimePointerChecks();
  if (!LAI.canVectorizeMemory()) {
    M.Status = "unsafe";
    // The dep checker's width is not meaningful once LAA refused (and
    // print<access-info> does not show it), so it is not reported.
    M.MaxSafeWidth = "n/a";
    return M;
  }
  // Same test print<access-info> uses for "with run-time checks".
  M.Status = LAI.getRuntimePointerChecking()->Need ? "needs-checks" : "safe";
  M.MaxSafeWidth = DC.isSafeForAnyVectorWidth()
                       ? "any"
                       : std::to_string(DC.getMaxSafeVectorWidthInBits());
  return M;
}

const char *yesNo(bool B) { return B ? "yes" : "no"; }

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

// One DependenceAnalysis direction entry as text (DVEntry bits LT=1, EQ=2,
// GT=4).
const char *dirText(unsigned D) {
  static const char *const Names[] = {"none", "<", "=", "<=",
                                      ">",    "<>", ">=", "*"};
  return Names[D & Dependence::DVEntry::ALL];
}

// S26: legality of interchanging L with its parent loop, from dependence
// direction vectors.
//
// Swapping the two loops swaps the two direction entries of every dependence
// they both carry. A dependence must stay lexicographically positive (its
// source still runs first). DependenceAnalysis gives, per level, the *set* of
// possible directions of (Dst iteration - Src iteration). Enumerating the
// pairs (o, i) of that set: a pair that is negative is the same dependence
// seen from the other end (-o, -i), so the only pairs whose swap flips the
// order are (<,>) and (>,<). Hence: illegal iff for some dependence the
// parent level may be '<' while the inner may be '>', or vice versa.
// Dependences that cannot be '=' at some level outside the parent are carried
// by that outer loop and are unaffected by the swap; they are skipped.
//
// This is more precise than LLVM 20's LoopInterchange, which rejects (=,*) and
// (*,=) after the swap, and more conservative: LLVM 20 drops confused
// dependences (Dependence::getLevels() is 0 for them, so the matrix row is all
// 'I'), LoopLens reports them as unknown (test/interchange/confused*.{ll,test}).
InterchangeFacts makeInterchangeFacts(Loop &L, ScalarEvolution &SE,
                                      DependenceInfo &DI) {
  InterchangeFacts X;
  X.Computed = true;
  Loop *P = L.getParentLoop();
  if (!P) {
    X.Why = "no-parent-loop";
    return X;
  }
  // "Perfect" in LoopInterchange's sense (tightlyNested /
  // containsUnsafeInstructions, LLVM 20): the parent's own blocks hold no
  // instruction that reads or writes memory or has side effects. Plain
  // arithmetic such as `i - 1` hoisted into the parent's header is allowed.
  // LoopNest::arePerfectlyNested is stricter (it refuses that `add`), so it
  // would disagree with the oracle on test/interchange/illegal-lt-gt.ll.
  bool Perfect = P->getSubLoops().size() == 1;
  for (BasicBlock *BB : P->blocks())
    if (Perfect && !L.contains(BB))
      for (Instruction &I : *BB)
        if (I.mayHaveSideEffects() || I.mayReadFromMemory())
          Perfect = false;
  if (!Perfect) {
    X.Why = "not-perfect-nest";
    return X;
  }
  SmallVector<Instruction *, 16> MemOps;
  for (BasicBlock *BB : L.blocks())
    for (Instruction &I : *BB) {
      if (!I.mayReadOrWriteMemory())
        continue;
      auto *LI = dyn_cast<LoadInst>(&I);
      auto *SI = dyn_cast<StoreInst>(&I);
      if ((!LI && !SI) || (LI && !LI->isSimple()) || (SI && !SI->isSimple())) {
        X.Why = "unsupported-memop";
        return X;
      }
      MemOps.push_back(&I);
    }
  const SCEV *BTC = SE.getBackedgeTakenCount(&L);
  X.BoundsDependOnParent =
      isa<SCEVCouldNotCompute>(BTC) || !SE.isLoopInvariant(BTC, P);
  const unsigned Outer = P->getLoopDepth(), Inner = L.getLoopDepth();
  bool Confused = false, Illegal = false;
  for (unsigned A = 0; A < MemOps.size(); ++A)
    for (unsigned B = A; B < MemOps.size(); ++B) {
      Instruction *Src = MemOps[A], *Dst = MemOps[B];
      if (isa<LoadInst>(Src) && isa<LoadInst>(Dst))
        continue; // input dependences never constrain the order
      std::unique_ptr<Dependence> D = DI.depends(Src, Dst, true);
      if (!D)
        continue;
      if (D->isConfused() || D->getLevels() < Inner) {
        Confused = true;
        continue;
      }
      D->normalize(&SE); // as LoopInterchange does
      bool CarriedOutside = false;
      for (unsigned Lv = 1; Lv < Outer; ++Lv)
        if (!(D->getDirection(Lv) & Dependence::DVEntry::EQ))
          CarriedOutside = true;
      if (CarriedOutside)
        continue;
      unsigned O = D->getDirection(Outer), I = D->getDirection(Inner);
      std::string Pair =
          std::string("(") + dirText(O) + "," + dirText(I) + ")";
      if (!is_contained(X.Dirs, Pair))
        X.Dirs.push_back(Pair);
      using DV = Dependence::DVEntry;
      if (((O & DV::LT) && (I & DV::GT)) || ((O & DV::GT) && (I & DV::LT)))
        Illegal = true;
    }
  if (Illegal)
    X.Legal = "no";
  else if (Confused)
    X.Why = "confused";
  else
    X.Legal = "yes";
  return X;
}

} // namespace

LoopRecord makeLoopRecord(const Function &F, Loop &L,
                          std::unique_ptr<ModuleSlotTracker> &MST,
                          ScalarEvolution &SE, DominatorTree &DT,
                          LoopAccessInfoManager &LAIM,
                          const TargetLibraryInfo &TLI,
                          const TargetTransformInfo &TTI, DependenceInfo *DI) {
  LoopRecord R;
  R.Function = F.getName().str();
  R.Depth = L.getLoopDepth();

  // Header as an IR operand, always with '%' ("%for.body", "%1"): the form
  // print<loops> uses and the one inside SCEV text ("<%for.body>").
  R.Header = operandStr(*L.getHeader(), F, MST);

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
  R.HasPreheader = L.getLoopPreheader() != nullptr;
  R.IVs = makeIVFacts(F, L, SE, MST);
  R.Recurs = makeRecurFacts(F, L, SE, DT, R.IVs, MST);
  R.Form = makeFormFacts(L, DT);
  R.TargetOrderedReductions = TTI.enableOrderedReductions();
  R.Hints.Vectorize = getOptionalBoolLoopAttribute(&L, "llvm.loop.vectorize.enable");
  R.Hints.Width = getOptionalIntLoopAttribute(&L, "llvm.loop.vectorize.width");
  R.CFG = makeCFGFacts(F, L, SE, DT, TLI, MST);
  R.Mem = makeMemFacts(F, L, LAIM, SE, TLI, TTI, MST);
  R.Class = classify(R);
  // S26: the cost-strided fix depends on whether interchange is legal.
  if (DI && StringRef(R.Class.RuleId) == "cost-strided") {
    R.Interchange = makeInterchangeFacts(L, SE, *DI);
    R.Class = classify(R);
  }
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

  if (!R.HasPreheader)
    OS << "    iv <no-preheader>\n";
  else if (R.IVs.empty())
    OS << "    iv <none>\n";
  for (const IVFacts &IV : R.IVs)
    OS << "    iv phi=" << IV.Phi << " kind=" << IV.Kind << " start=" << IV.Start
       << " step=" << IV.Step << " scev=[" << IV.SCEV
       << "] controls-exit=" << yesNo(IV.ControlsExit) << '\n';

  for (const RecurFacts &Rc : R.Recurs) {
    OS << "    recur phi=" << Rc.Phi << " kind=" << Rc.Kind;
    if (Rc.ExactFP)
      OS << " exact-fp=yes";
    if (Rc.Ordered)
      OS << " ordered=yes";
    OS << '\n';
  }

  const FormFacts &Fm = R.Form;
  OS << "    form simplify=" << yesNo(Fm.Simplify)
     << " rotated=" << yesNo(Fm.Rotated) << " lcssa=" << yesNo(Fm.LCSSA)
     << " exiting=" << (Fm.SingleExiting ? "single" : "multiple")
     << " innermost=" << yesNo(Fm.Innermost)
     << " guarded=" << yesNo(Fm.Guarded) << '\n';

  if (R.Hints.any()) {
    OS << "    hints";
    if (R.Hints.Vectorize)
      OS << " vectorize=" << (*R.Hints.Vectorize ? "enable" : "disable");
    if (R.Hints.Width)
      OS << " width=" << *R.Hints.Width;
    OS << '\n';
  }

  const CFGFacts &C = R.CFG;
  if (C.Analyzed)
    OS << "    cfg blocks=" << C.Blocks << " predicated=" << C.Predicated
       << " switches=" << C.Switches << " exits=" << C.Exits
       << " early-exit=" << C.EarlyExit << '\n';

  const MemFacts &M = R.Mem;
  if (!M.Analyzed) {
    OS << "    mem <not-innermost>\n";
    printClassification(OS, R.Class);
    return;
  }
  OS << "    mem status=" << M.Status << " checks=" << M.Checks
     << " max-safe-width=" << M.MaxSafeWidth << " report=" << M.Report << '\n';
  if (!M.DepsRecorded)
    OS << "    dep <not-recorded>\n";
  else if (M.Deps.empty())
    OS << "    dep <none>\n";
  for (const DepFacts &D : M.Deps)
    OS << "    dep kind=" << D.Kind << " src=" << D.Src << " dst=" << D.Dst
       << " dist=[" << D.Dist << "]\n";
  for (const AccessFacts &A : M.Accesses) {
    OS << "    access " << A.Op << " ptr=" << A.Ptr << " kind=" << A.Kind
       << " stride=" << A.Stride;
    if (A.Versioned)
      OS << " versioned=yes";
    if (A.GatherLegal)
      OS << " gather=legal";
    OS << '\n';
  }
  for (const CallFacts &C : M.Calls) {
    OS << "    call callee=" << C.Callee << " vector=" << C.Vector
       << " mem=" << C.Mem;
    if (C.MathLib)
      OS << " math-lib=yes";
    OS << '\n';
  }
  for (const NonSimpleFacts &N : M.NonSimple)
    OS << "    nonsimple " << N.Access << " why=" << N.Why << '\n';
  if (R.Interchange.Computed) {
    const InterchangeFacts &X = R.Interchange;
    OS << "    interchange legal=" << X.Legal;
    if (!X.Dirs.empty() || X.Why.empty() || X.Why == "confused") {
      OS << " dirs=[";
      ListSeparator LS(",");
      for (const std::string &D : X.Dirs)
        OS << LS << D;
      OS << ']';
    }
    if (X.BoundsDependOnParent)
      OS << " bounds=depend-on-parent";
    if (!X.Why.empty())
      OS << " why=" << X.Why;
    OS << '\n';
  }
  printClassification(OS, R.Class);
}

} // namespace looplens
