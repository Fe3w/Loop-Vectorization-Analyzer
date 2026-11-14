//===- Classifier.h - Rule table: loop facts -> blocker categories -*- C++ -*-===//
//
// Maps the facts in a LoopRecord to the categories that explain why
// LoopVectorize leaves the loop scalar. One table of rules, evaluated in
// table order; the order mirrors LoopVectorize's own order of checks
// (LoopVectorizationLegality::canVectorize in LLVM 20, then the cost model),
// so the primary blocker is the first check LoopVectorize would fail.
//
//===----------------------------------------------------------------------===//

#ifndef LOOPLENS_CLASSIFIER_H
#define LOOPLENS_CLASSIFIER_H

#include <string>
#include <vector>

namespace llvm {
class raw_ostream;
} // namespace llvm

namespace looplens {

struct LoopRecord;

enum class Blocker {
  ControlFlow,
  Reduction,
  CallOrUnsafeMemOp,
  TripCount,
  LoopCarriedDependence,
  Aliasing,
  Stride,
  Hint,
  None
};

const char *blockerName(Blocker B); // "control-flow", "trip-count", ...

struct Classification {
  bool Analyzed = false;         // false for outer loops
  Blocker Primary = Blocker::None;
  const char *RuleId = "none";   // the rule that chose Primary
  std::vector<Blocker> Secondary; // other matching categories, table order
  std::string Evidence, Fix;      // for the primary rule; empty if none
};

// Pure function of the record: no LLVM analyses are consulted.
Classification classify(const LoopRecord &R);

// "    blocker primary=<cat> rule=<id> secondary=<cat,...|none>" or
// "    blocker <not-innermost>"; then, when a rule fired,
// "    evidence <facts>" and "    fix <source-level change>".
void printClassification(llvm::raw_ostream &OS, const Classification &C);

} // namespace looplens

#endif // LOOPLENS_CLASSIFIER_H
