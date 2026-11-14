//===- Remarks.h - LoopLens classification as LLVM remarks -----*- C++ -*-===//
//
// One OptimizationRemarkAnalysis per innermost loop, pass name "looplens",
// remark name = the primary rule id ("Vectorizable" when no rule applies),
// at the loop's start location -- the location LoopVectorize uses for its
// per-loop remarks, so both land on the same source line.
//
//===----------------------------------------------------------------------===//

#ifndef LOOPLENS_REMARKS_H
#define LOOPLENS_REMARKS_H

namespace llvm {
class Loop;
class OptimizationRemarkEmitter;
} // namespace llvm

namespace looplens {

struct LoopRecord;

void emitLoopRemark(llvm::OptimizationRemarkEmitter &ORE, const llvm::Loop &L,
                    const LoopRecord &R);

} // namespace looplens

#endif // LOOPLENS_REMARKS_H
