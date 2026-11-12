//===- LoopLensAnalyze.cpp - Explain missed loop vectorization -----------===//
//
// Week 1 skeleton: a new-pass-manager *function* pass that visits every loop
// and prints its header name and nesting depth. Later weeks add SCEV, LAA and
// the classifier on top of this loop walk.
//
// Usage:
//   opt -load-pass-plugin=build/lib/LoopLens.so \
//       -passes=looplens-analyze -disable-output input.ll
//
// API notes (LLVM 20): PassPlugin / registerPipelineParsingCallback /
// LoopInfo::getLoopsInPreorder are unchanged from LLVM 15 through 20.
//===----------------------------------------------------------------------===//

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Function.h"
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

    errs() << "looplens: function '" << F.getName() << "'\n";
    // Preorder: outer loop before its inner loops, siblings in program
    // order, so test output is deterministic.
    for (Loop *L : LI.getLoopsInPreorder())
      errs() << "  loop header=" << L->getHeader()->getName()
             << " depth=" << L->getLoopDepth() << "\n";

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
