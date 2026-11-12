//===- LoopRecord.h - Per-loop facts collected by LoopLens -------*- C++ -*-===//
//
// One LoopRecord per loop, filled from LLVM analyses and printed as one stable
// line. Later sub-milestones add trip counts, memory facts and blockers here.
//
//===----------------------------------------------------------------------===//

#ifndef LOOPLENS_LOOPRECORD_H
#define LOOPLENS_LOOPRECORD_H

#include <string>

namespace llvm {
class Function;
class Loop;
class ModuleSlotTracker;
class raw_ostream;
} // namespace llvm

namespace looplens {

struct LoopRecord {
  std::string Function, Header, File;
  unsigned Depth = 0, Line = 0, Col = 0;
  // Separate flag, not Line != 0: compiler-generated locations have line 0,
  // and LoopVectorize remarks still report them as <file>:0:0.
  bool HasLoc = false;
  bool hasLoc() const { return HasLoc; }
};

// MST numbers unnamed blocks; pass one tracker per function (after
// MST.incorporateFunction(F)) so numbering is not rebuilt for every loop.
LoopRecord makeLoopRecord(const llvm::Function &F, const llvm::Loop &L,
                          llvm::ModuleSlotTracker &MST);

// Format: "  loop header=<hdr> depth=<d> loc=<file>:<line>:<col>"
//     or: "  loop header=<hdr> depth=<d> loc=<none>"
void printLoopRecord(llvm::raw_ostream &OS, const LoopRecord &R);

} // namespace looplens

#endif // LOOPLENS_LOOPRECORD_H
