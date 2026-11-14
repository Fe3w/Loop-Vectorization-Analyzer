//===- Repair.cpp - looplens-repair: versioning + scalar promotion ---------===//
//
// Repairs one blocker LoopLens reports as loop-carried-dependence: an
// accumulation into a loop-invariant address that may overlap the addresses
// the loop reads, e.g. PolyBench cholesky's
//
//     for (k = 0; k < j; k++) A[i][j] -= A[i][k] * A[j][k];
//
// LoopAccessAnalysis reports UnsafeDep (same underlying object, unknown
// distance), and LICM cannot promote A[i][j] because it cannot prove the
// overlap away. LLVM 20's LoopVersioningLICM refuses this loop shape. This
// pass versions the loop on "A[i][j] lies outside every range read" and, in
// the fast copy, keeps A[i][j] in a register (load once before the loop,
// store once after it). The fast copy is then an ordinary reduction, which
// LoopVectorize vectorizes when FP reassociation is allowed (-ffast-math or
// #pragma clang loop vectorize(enable)).
//
// Cloning follows LLVM 20's LoopVersioning::versionLoop (LoopVersioning.cpp);
// LoopVersioning itself is not used because its runtime check is built from
// LoopAccessAnalysis's pointer groups, which do not express this check.
//
//===----------------------------------------------------------------------===//

#include "Repair.h"

#include "llvm/Analysis/LoopAccessAnalysis.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/Utils/LoopUtils.h"
#include "llvm/Transforms/Utils/ScalarEvolutionExpander.h"
#include "llvm/Transforms/Utils/ValueMapper.h"

using namespace llvm;

namespace looplens {

namespace {

// Past this many address ranges the runtime check is not worth it and nothing
// is versioned. Default 8 = LLVM's own -runtime-memory-check-threshold.
cl::opt<unsigned> MaxChecks(
    "looplens-repair-max-checks",
    cl::desc("looplens-repair: do not version a loop that needs more than "
             "this many runtime address-range checks"),
    cl::init(8));

struct Candidate {
  Loop *L;
  LoadInst *LdP;   // the load of the accumulated address P, or null when
                   // LICM already hoisted it (only the store is left)
  StoreInst *St;   // the store to P
  // [Low, High) of every other address read, as SCEVs valid in the preheader.
  SmallVector<std::pair<const SCEV *, const SCEV *>, 4> Ranges;
};

// The accumulation pattern, or nullopt. Conditions are listed in
// docs/plans/S21.md (design); each one keeps the promotion legal.
std::optional<Candidate> findCandidate(Loop &L, ScalarEvolution &SE,
                                       LoopAccessInfoManager &LAIM,
                                       const DominatorTree &DT,
                                       const DataLayout &DL) {
  if (!L.isInnermost() || !L.isLoopSimplifyForm() || !L.getExitBlock() ||
      L.getExitingBlock() != L.getLoopLatch())
    return std::nullopt;
  // Only loops LoopAccessAnalysis refuses: never version a loop needlessly.
  if (LAIM.getInfo(L).canVectorizeMemory())
    return std::nullopt;
  const SCEV *BTC = SE.getBackedgeTakenCount(&L);
  if (isa<SCEVCouldNotCompute>(BTC))
    return std::nullopt;

  Candidate C{&L, nullptr, nullptr, {}};
  SmallVector<LoadInst *, 8> Loads;
  for (BasicBlock *BB : L.blocks())
    for (Instruction &I : *BB) {
      if (auto *S = dyn_cast<StoreInst>(&I)) {
        if (C.St || !S->isSimple())
          return std::nullopt; // exactly one store
        C.St = S;
      } else if (auto *LI = dyn_cast<LoadInst>(&I)) {
        if (!LI->isSimple())
          return std::nullopt;
        Loads.push_back(LI);
      } else if (I.mayReadOrWriteMemory()) {
        return std::nullopt; // calls, fences, atomics, ...
      }
    }
  if (!C.St)
    return std::nullopt;

  Value *P = C.St->getPointerOperand();
  auto *PI = dyn_cast<Instruction>(P);
  if ((PI && L.contains(PI)) || !SE.isLoopInvariant(SE.getSCEV(P), &L))
    return std::nullopt; // P must be available before the loop
  BasicBlock *SB = C.St->getParent();
  for (LoadInst *LI : Loads) {
    if (LI->getPointerOperand() == P) {
      if (C.LdP || LI->getParent() != SB || !LI->comesBefore(C.St) ||
          LI->getType() != C.St->getValueOperand()->getType())
        return std::nullopt;
      C.LdP = LI;
      continue;
    }
    // Other reads: loop-invariant or affine add-recurrences of L.
    const SCEV *A = SE.getSCEV(LI->getPointerOperand());
    const SCEV *Size = SE.getConstant(
        DL.getIndexType(LI->getPointerOperandType()),
        DL.getTypeStoreSize(LI->getType()).getFixedValue());
    const SCEV *Low, *High;
    if (SE.isLoopInvariant(A, &L)) {
      Low = A;
      High = SE.getAddExpr(A, Size);
    } else if (auto *AR = dyn_cast<SCEVAddRecExpr>(A);
               AR && AR->getLoop() == &L && AR->isAffine()) {
      const SCEV *Step = AR->getStepRecurrence(SE);
      const SCEV *End = SE.getAddExpr(
          AR->getStart(),
          SE.getMulExpr(Step, SE.getNoopOrZeroExtend(BTC, Step->getType())));
      Low = SE.getUMinExpr(AR->getStart(), End);
      High = SE.getAddExpr(SE.getUMaxExpr(AR->getStart(), End), Size);
    } else {
      return std::nullopt; // e.g. an indirect load: no range to check
    }
    C.Ranges.push_back({Low, High});
  }
  // Without a load of P in the loop (LICM hoisted it but could not sink the
  // store), the value is already carried in a phi: only the store moves.
  if (C.Ranges.size() > MaxChecks)
    return std::nullopt; // over the runtime-check limit
  if (C.Ranges.empty())
    return std::nullopt;
  // The store (and the load before it) execute on every iteration, so the
  // value left in P after the loop is the last stored value.
  if (!DT.dominates(SB, L.getLoopLatch()))
    return std::nullopt;
  // Every SCEV must be expandable in the preheader.
  SCEVExpander Exp(SE, DL, "lr");
  Instruction *IP = L.getLoopPreheader()->getTerminator();
  for (auto &R : C.Ranges)
    if (!Exp.isSafeToExpandAt(R.first, IP) || !Exp.isSafeToExpandAt(R.second, IP))
      return std::nullopt;
  return C;
}

// Single-operand LCSSA phis in the exit block get the cloned loop's value as
// a second operand (LoopVersioning::addPHINodes, LLVM 20).
void addExitPhis(Loop &Fast, Loop &Orig, ValueToValueMapTy &VMap,
                 const SmallVectorImpl<Instruction *> &DefsUsedOutside) {
  BasicBlock *PHIBlock = Fast.getExitBlock();
  for (Instruction *Inst : DefsUsedOutside) {
    PHINode *PN = nullptr;
    for (PHINode &Phi : PHIBlock->phis())
      if (Phi.getIncomingValue(0) == Inst) {
        PN = &Phi;
        break;
      }
    if (!PN) {
      PN = PHINode::Create(Inst->getType(), 2, Inst->getName() + ".lr");
      PN->insertBefore(PHIBlock->begin());
      SmallVector<User *, 8> Users;
      for (User *U : Inst->users())
        if (!Fast.contains(cast<Instruction>(U)->getParent()))
          Users.push_back(U);
      for (User *U : Users)
        U->replaceUsesOfWith(Inst, PN);
      PN->addIncoming(Inst, Fast.getExitingBlock());
    }
  }
  for (PHINode &PN : PHIBlock->phis()) {
    Value *V = PN.getIncomingValue(0);
    if (auto It = VMap.find(V); It != VMap.end())
      V = It->second;
    PN.addIncoming(V, Orig.getExitingBlock());
  }
}

void repair(Candidate &C, ScalarEvolution &SE, LoopInfo &LI,
            DominatorTree &DT, const DataLayout &DL,
            OptimizationRemarkEmitter &ORE) {
  Loop &L = *C.L;
  BasicBlock *CheckBB = L.getLoopPreheader();
  Value *P = C.St->getPointerOperand();

  // 1. Runtime check: does [P, P+size) overlap any range read?
  SCEVExpander Exp(SE, DL, "lr");
  Instruction *IP = CheckBB->getTerminator();
  IRBuilder<> B(IP);
  Type *PtrTy = P->getType();
  const SCEV *PS = SE.getSCEV(P);
  const SCEV *PEnd = SE.getAddExpr(
      PS, SE.getConstant(DL.getIndexType(PtrTy),
                         DL.getTypeStoreSize(C.St->getValueOperand()->getType()).getFixedValue()));
  Value *PLo = Exp.expandCodeFor(PS, PtrTy, IP->getIterator());
  Value *PHi = Exp.expandCodeFor(PEnd, PtrTy, IP->getIterator());
  Value *Conflict = nullptr;
  for (auto &[Lo, Hi] : C.Ranges) {
    Value *VLo = Exp.expandCodeFor(Lo, PtrTy, IP->getIterator());
    Value *VHi = Exp.expandCodeFor(Hi, PtrTy, IP->getIterator());
    // Overlap iff P < Hi && Lo < P+size.
    Value *O = B.CreateAnd(B.CreateICmpULT(PLo, VHi), B.CreateICmpULT(VLo, PHi));
    Conflict = Conflict ? B.CreateOr(Conflict, O) : O;
  }
  Conflict->setName("lr.conflict");
  CheckBB->setName(L.getHeader()->getName() + ".lr.check");

  // 2. Clone the loop (with a fresh preheader) as the original, slow copy.
  SmallVector<Instruction *, 8> DefsUsedOutside = findDefsUsedOutsideOfLoop(&L);
  BasicBlock *PH = SplitBlock(CheckBB, CheckBB->getTerminator(), &DT, &LI,
                              nullptr, L.getHeader()->getName() + ".ph");
  ValueToValueMapTy VMap;
  SmallVector<BasicBlock *, 8> OrigBlocks;
  Loop *Orig = cloneLoopWithPreheader(PH, CheckBB, &L, VMap, ".lr.orig", &LI,
                                      &DT, OrigBlocks);
  remapInstructionsInBlocks(OrigBlocks, VMap);
  Instruction *OldTerm = CheckBB->getTerminator();
  BranchInst::Create(Orig->getLoopPreheader(), PH, Conflict, CheckBB);
  OldTerm->eraseFromParent();
  DT.changeImmediateDominator(L.getExitBlock(), CheckBB);
  addExitPhis(L, *Orig, VMap, DefsUsedOutside);
  formDedicatedExitBlocks(Orig, &DT, &LI, nullptr, /*PreserveLCSSA=*/true);
  formDedicatedExitBlocks(&L, &DT, &LI, nullptr, /*PreserveLCSSA=*/true);

  // 3. Promote P in the fast copy: load once, carry in a phi, store once.
  BasicBlock *Latch = L.getLoopLatch();
  Value *SV = C.St->getValueOperand();
  if (C.LdP) {
    IRBuilder<> PB(L.getLoopPreheader()->getTerminator());
    LoadInst *Init = PB.CreateAlignedLoad(C.LdP->getType(), P,
                                          C.LdP->getAlign(), "lr.init");
    Init->copyMetadata(*C.LdP);
    PHINode *Acc = PHINode::Create(C.LdP->getType(), 2, "lr.acc");
    Acc->insertBefore(L.getHeader()->begin());
    Acc->addIncoming(Init, L.getLoopPreheader());
    Acc->addIncoming(SV, Latch);
    C.LdP->replaceAllUsesWith(Acc);
    C.LdP->eraseFromParent();
  }
  BasicBlock *Exit = L.getExitBlock();
  PHINode *Final = PHINode::Create(SV->getType(), 1, "lr.final");
  Final->insertBefore(Exit->begin());
  Final->addIncoming(SV, Latch);
  StoreInst *Out = new StoreInst(Final, P, false, C.St->getAlign(),
                                 Exit->getFirstInsertionPt());
  Out->copyMetadata(*C.St);
  C.St->eraseFromParent();

  SE.forgetLoop(&L);
  SE.forgetLoop(Orig);
  unsigned N = C.Ranges.size();
  ORE.emit([&] {
    return OptimizationRemark("looplens-repair", "VersionedAndPromoted",
                              L.getStartLoc(), L.getHeader())
           << "versioned loop and promoted the loop-invariant store to a "
              "register ("
           << ore::NV("Checks", N) << " address range"
           << (N == 1 ? "" : "s") << " checked at run time)";
  });
}

} // namespace

PreservedAnalyses LoopLensRepair::run(Function &F,
                                      FunctionAnalysisManager &FAM) {
  if (F.isDeclaration())
    return PreservedAnalyses::all();
  LoopInfo &LI = FAM.getResult<LoopAnalysis>(F);
  ScalarEvolution &SE = FAM.getResult<ScalarEvolutionAnalysis>(F);
  DominatorTree &DT = FAM.getResult<DominatorTreeAnalysis>(F);
  LoopAccessInfoManager &LAIM = FAM.getResult<LoopAccessAnalysis>(F);
  OptimizationRemarkEmitter &ORE =
      FAM.getResult<OptimizationRemarkEmitterAnalysis>(F);
  const DataLayout &DL = F.getDataLayout();

  // Find all candidates first: the transform changes LoopInfo.
  SmallVector<Candidate, 4> Cands;
  for (Loop *L : LI.getLoopsInPreorder())
    if (auto C = findCandidate(*L, SE, LAIM, DT, DL))
      Cands.push_back(std::move(*C));
  if (Cands.empty())
    return PreservedAnalyses::all();
  for (Candidate &C : Cands)
    repair(C, SE, LI, DT, DL, ORE);
  // LoopInfo and the dominator tree are updated above, but SCEV, LAA and
  // everything derived from the old CFG are not: claim nothing.
  return PreservedAnalyses::none();
}

} // namespace looplens
