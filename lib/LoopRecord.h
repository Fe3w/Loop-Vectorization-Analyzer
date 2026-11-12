//===- LoopRecord.h - Per-loop facts collected by LoopLens -------*- C++ -*-===//
//
// One LoopRecord per loop, filled from LLVM analyses and printed as a stable
// block of lines. Facts are stored as plain values/strings, never as analysis
// pointers, so a record stays valid after the analyses are invalidated (and can
// later be serialised to JSON). Later sub-milestones add memory facts and
// blockers here.
//
//===----------------------------------------------------------------------===//

#ifndef LOOPLENS_LOOPRECORD_H
#define LOOPLENS_LOOPRECORD_H

#include <memory>
#include <string>

namespace llvm {
class Function;
class Loop;
class ModuleSlotTracker;
class ScalarEvolution;
class raw_ostream;
} // namespace llvm

namespace looplens {

enum class TripKind { Constant, Symbolic, Unknown };

// Trip-count facts from ScalarEvolution. BTC = backedge-taken count
// (trip count - 1). SCEV-valued fields hold the SCEV's printed text;
// "***COULDNOTCOMPUTE***" when ScalarEvolution cannot compute it.
struct TripFacts {
  TripKind Kind = TripKind::Unknown;
  std::string Count = "none"; // exact trip count, only for Constant
  std::string Reason;         // only for Unknown, in precedence order:
                              // no-exit | needs-scev-predicate |
                              // multiple-exits | exit-cond-not-affine |
                              // exit-cond-not-icmp | other
  std::string BTC, MaxBTC, SymMaxBTC;
};

struct LoopRecord {
  std::string Function, Header, File;
  unsigned Depth = 0, Line = 0, Col = 0;
  // Separate flag, not Line != 0: compiler-generated locations have line 0,
  // and LoopVectorize remarks still report them as <file>:0:0.
  bool HasLoc = false;
  bool hasLoc() const { return HasLoc; }
  TripFacts Trip;
};

// MST numbers unnamed header blocks. Pass one (initially empty) slot per
// function; it is created on the first unnamed header and reused after that.
LoopRecord makeLoopRecord(const llvm::Function &F, const llvm::Loop &L,
                          std::unique_ptr<llvm::ModuleSlotTracker> &MST,
                          llvm::ScalarEvolution &SE);

// Format (one block per loop):
//   "  loop header=%<hdr> depth=<d> loc=<file>:<line>:<col>"  (or loc=<none>)
//   "    trip kind=<k> [reason=<r>] count=<n|none> btc=[<scev>]
//        max-btc=[<scev>] symbolic-max-btc=[<scev>]"          (one line)
// SCEV text contains spaces, hence the brackets.
void printLoopRecord(llvm::raw_ostream &OS, const LoopRecord &R);

} // namespace looplens

#endif // LOOPLENS_LOOPRECORD_H
