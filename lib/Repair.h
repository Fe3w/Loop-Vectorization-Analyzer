//===- Repair.h - looplens-repair (Phase 2) ----------------------*- C++ -*-===//
//
// A transform: versions loops that accumulate into a loop-invariant address
// and promotes that address to a register in the fast copy. See Repair.cpp.
//
//===----------------------------------------------------------------------===//

#ifndef LOOPLENS_REPAIR_H
#define LOOPLENS_REPAIR_H

#include "llvm/IR/PassManager.h"

namespace looplens {

struct LoopLensRepair : llvm::PassInfoMixin<LoopLensRepair> {
  llvm::PreservedAnalyses run(llvm::Function &F,
                              llvm::FunctionAnalysisManager &FAM);
};

} // namespace looplens

#endif // LOOPLENS_REPAIR_H
