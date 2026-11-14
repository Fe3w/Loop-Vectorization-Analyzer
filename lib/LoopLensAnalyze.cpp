//===- LoopLensAnalyze.cpp - Explain missed loop vectorization -----------===//
//
// A new-pass-manager *function* pass that visits every loop, builds a
// LoopRecord (header, depth, source location, trip count, induction
// variables, loop form, memory safety) and prints one block of lines per
// loop.
// Trip counts, memory facts and the blocker classifier build on this walk.
//
// Usage:
//   opt -load-pass-plugin=build/lib/LoopLens.so \
//       -passes=looplens-analyze -disable-output input.ll
//
// API notes (LLVM 20): PassPlugin / registerPipelineParsingCallback /
// LoopInfo::getLoopsInPreorder are unchanged from LLVM 15 through 20.
//===----------------------------------------------------------------------===//

#include "JsonReport.h"
#include "LoopRecord.h"
#include "Remarks.h"
#include "Repair.h"

#include "llvm/Analysis/DependenceAnalysis.h"
#include "llvm/Analysis/LoopAccessAnalysis.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/ModuleSlotTracker.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Transforms/Utils/LCSSA.h"
#include "llvm/Transforms/Utils/LoopSimplify.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {

// With opt, plugin options work after -load-pass-plugin. With clang,
// -fpass-plugin= alone loads the plugin after option parsing, so
// -mllvm -looplens-json is rejected; add -Xclang -load -Xclang LoopLens.so.
cl::opt<std::string>
    JsonPath("looplens-json",
             cl::desc("LoopLens: write one JSON object per loop (JSON Lines) "
                      "to this file"),
             cl::value_desc("path"), cl::init(""));

cl::opt<bool> PrintText("looplens-text",
                        cl::desc("LoopLens: print the text report to stderr"),
                        cl::init(true));

// At VectorizerStart some loops are not in loop-simplify form yet;
// LoopVectorizePass canonicalises them itself (simplifyLoop + LCSSA) before
// its legality checks. Running the same two utilities in front of LoopLens
// lets it see what LoopVectorize sees, without LoopLens changing IR itself.
cl::opt<bool> Canonicalize(
    "looplens-canonicalize",
    cl::desc("LoopLens (clang pipeline): run LoopSimplify and LCSSA before "
             "LoopLens, as LoopVectorize does before its own checks"),
    cl::init(true));

// Phase 2: also run looplens-repair at the extension point (off by default:
// it is a transform; the analysis alone never changes code).
cl::opt<bool> RunRepair(
    "looplens-repair",
    cl::desc("LoopLens (clang pipeline): run looplens-repair before the loop "
             "vectorizer"),
    cl::init(false));

struct LoopLensAnalyze : PassInfoMixin<LoopLensAnalyze> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    if (F.isDeclaration())
      return PreservedAnalyses::all();

    // Ask the analysis manager; never build LoopInfo ourselves.
    LoopInfo &LI = FAM.getResult<LoopAnalysis>(F);
    ScalarEvolution &SE = FAM.getResult<ScalarEvolutionAnalysis>(F);
    DominatorTree &DT = FAM.getResult<DominatorTreeAnalysis>(F); // isLCSSAForm
    // LLVM 16+: LoopAccessAnalysis is a *function* analysis whose result is a
    // LoopAccessInfoManager (per-loop LoopAccessInfo, computed on demand and
    // cached). Before LLVM 16 it was a loop analysis returning
    // LoopAccessInfo directly through the loop analysis manager.
    LoopAccessInfoManager &LAIM = FAM.getResult<LoopAccessAnalysis>(F);
    const TargetLibraryInfo &TLI = FAM.getResult<TargetLibraryAnalysis>(F);
    const TargetTransformInfo &TTI = FAM.getResult<TargetIRAnalysis>(F);
    // S26: interchange legality of cost-strided loops. DependenceInfo is
    // cheap to get; dependences are computed only when asked.
    DependenceInfo &DI = FAM.getResult<DependenceAnalysis>(F);
    OptimizationRemarkEmitter &ORE =
        FAM.getResult<OptimizationRemarkEmitterAnalysis>(F);

    if (PrintText)
      errs() << "looplens: function '" << F.getName() << "'\n";
    // Slot tracker for unnamed headers (%N): created lazily by
    // makeLoopRecord on the first unnamed header, then reused for this
    // function's other loops.
    std::unique_ptr<ModuleSlotTracker> MST;
    // Preorder: outer loop before its inner loops, siblings in program
    // order, so test output is deterministic.
    raw_ostream *Json =
        JsonPath.empty() ? nullptr : looplens::jsonStream(JsonPath);
    for (Loop *L : LI.getLoopsInPreorder()) {
      looplens::LoopRecord R =
          looplens::makeLoopRecord(F, *L, MST, SE, DT, LAIM, TLI, TTI, &DI);
      if (PrintText)
        looplens::printLoopRecord(errs(), R);
      if (Json)
        looplens::writeLoopJson(*Json, R);
      looplens::emitLoopRemark(ORE, *L, R);
    }

    // Analysis-only pass: nothing changed, every analysis stays valid.
    return PreservedAnalyses::all();
  }

  // Run even on optnone functions (clang -O0 output), so users are not
  // surprised by an empty report.
  static bool isRequired() { return true; }
};

} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "LoopLens", "0.1",
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "looplens-analyze") {
                    FPM.addPass(LoopLensAnalyze());
                    return true;
                  }
                  if (Name == "looplens-repair") {
                    FPM.addPass(looplens::LoopLensRepair());
                    return true;
                  }
                  return false;
                });
            // Inside clang (-fpass-plugin): run right before the loop
            // vectorizer, on the IR it will see. Between this extension
            // point and LoopVectorize LLVM 20 only runs LoopRotate,
            // LoopDeletion, (opt-in) LoopDistribute and InjectTLIMappings
            // (PassBuilderPipelines.cpp).
            // LLVM 20's -O0 pipeline also invokes this extension point
            // (PassBuilderPipelines.cpp:2229), but LoopVectorize never runs
            // at -O0, so there is nothing to explain: skip it.
            PB.registerVectorizerStartEPCallback(
                [](FunctionPassManager &FPM, OptimizationLevel Level) {
                  if (Level == OptimizationLevel::O0)
                    return;
                  if (Canonicalize) {
                    FPM.addPass(LoopSimplifyPass());
                    FPM.addPass(LCSSAPass());
                  }
                  if (RunRepair) {
                    FPM.addPass(looplens::LoopLensRepair());
                    // The repair may leave new loops outside simplify form.
                    FPM.addPass(LoopSimplifyPass());
                    FPM.addPass(LCSSAPass());
                  }
                  FPM.addPass(LoopLensAnalyze());
                });
          }};
}
