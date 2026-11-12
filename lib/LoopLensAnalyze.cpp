//===- LoopLensAnalyze.cpp - Explain missed loop vectorization -----------===//
//
// A new-pass-manager *function* pass that visits every loop, builds a
// LoopRecord (header, depth, source location) and prints one line per loop.
// Trip counts, memory facts and the blocker classifier build on this walk.
//
// Usage:
//   opt -load-pass-plugin=build/lib/LoopLens.so \
//       -passes=looplens-analyze -disable-output input.ll
//
// API notes (LLVM 20): PassPlugin / registerPipelineParsingCallback /
// LoopInfo::getLoopsInPreorder are unchanged from LLVM 15 through 20.
//===----------------------------------------------------------------------===//

#include "LoopRecord.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/ModuleSlotTracker.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {

struct LoopLensAnalyze : PassInfoMixin<LoopLensAnalyze> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    if (F.isDeclaration())
      return PreservedAnalyses::all();

    // Ask the analysis manager; never build LoopInfo ourselves.
    LoopInfo &LI = FAM.getResult<LoopAnalysis>(F);
    ScalarEvolution &SE = FAM.getResult<ScalarEvolutionAnalysis>(F);

    errs() << "looplens: function '" << F.getName() << "'\n";
    // Slot tracker for unnamed headers (%N): created lazily by
    // makeLoopRecord on the first unnamed header, then reused for this
    // function's other loops.
    std::unique_ptr<ModuleSlotTracker> MST;
    // Preorder: outer loop before its inner loops, siblings in program
    // order, so test output is deterministic.
    for (Loop *L : LI.getLoopsInPreorder())
      looplens::printLoopRecord(errs(),
                                looplens::makeLoopRecord(F, *L, MST, SE));

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
                  return false;
                });
          }};
}
