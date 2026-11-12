//===- LoopRecord.cpp - Per-loop facts collected by LoopLens -------------===//

#include "LoopRecord.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/DebugLoc.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/ModuleSlotTracker.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace looplens {

LoopRecord makeLoopRecord(const Function &F, const Loop &L,
                          ModuleSlotTracker &MST) {
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
  return R;
}

void printLoopRecord(raw_ostream &OS, const LoopRecord &R) {
  OS << "  loop header=" << R.Header << " depth=" << R.Depth << " loc=";
  if (R.hasLoc())
    OS << R.File << ':' << R.Line << ':' << R.Col;
  else
    OS << "<none>";
  OS << '\n';
}

} // namespace looplens
