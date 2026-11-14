//===- Remarks.cpp - LoopLens classification as LLVM remarks -------------===//

#include "Remarks.h"
#include "Classifier.h"
#include "LoopRecord.h"

#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/DiagnosticInfo.h"

#include <string>

using namespace llvm;

namespace looplens {

void emitLoopRemark(OptimizationRemarkEmitter &ORE, const Loop &L,
                    const LoopRecord &R) {
  const Classification &C = R.Class;
  if (!C.Analyzed) // outer loop: LoopVectorize emits none either
    return;
  // The lambda form builds the remark only when a remark consumer is on.
  ORE.emit([&] {
    bool None = C.Primary == Blocker::None;
    OptimizationRemarkAnalysis Rem("looplens", None ? "Vectorizable" : C.RuleId,
                                   L.getStartLoc(), L.getHeader());
    std::string Secondary;
    for (Blocker B : C.Secondary)
      Secondary += (Secondary.empty() ? "" : ",") + std::string(blockerName(B));
    if (Secondary.empty())
      Secondary = "none";
    // Each ore::NV becomes a key in the YAML Args and its value in the text.
    Rem << "Category: " << ore::NV("Category", blockerName(C.Primary))
        << "; Rule: " << ore::NV("Rule", C.RuleId)
        << "; Secondary: " << ore::NV("Secondary", Secondary);
    if (!None)
      Rem << "; Evidence: " << ore::NV("Evidence", C.Evidence)
          << "; Fix: " << ore::NV("Fix", C.Fix);
    return Rem;
  });
}

} // namespace looplens
