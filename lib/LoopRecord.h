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

#include "Classifier.h"

#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace llvm {
class DependenceInfo;
class DominatorTree;
class LoopAccessInfoManager;
class TargetLibraryInfo;
class TargetTransformInfo;
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

// One induction phi of the loop header, as InductionDescriptor sees it
// (SE overload: no SCEV predicates assumed). Kind: int | ptr | fp.
// Step is in bytes for pointer IVs.
struct IVFacts {
  std::string Phi, Kind, Start, Step, SCEV;
  bool ControlsExit = false; // the IV Loop::getInductionVariable returns
};

// A header phi that is not an induction: a reduction RecurrenceDescriptor
// accepts (Kind = RecurKind in lower case: add, fadd, smax, ianyof, ...), a
// fixed-order recurrence ("fixed-order"), or neither ("unsupported").
// ExactFP: the reduction needs exact (non-reassociable) FP math.
struct RecurFacts {
  std::string Phi, Kind;
  bool ExactFP = false, Ordered = false;
};

// Loop-form facts LoopVectorize relies on, straight from LoopInfo.
// Guarded is LoopInfo's own guard pattern only: "no" is not proof of an
// unguarded loop.
struct FormFacts {
  bool Simplify = false, Rotated = false, LCSSA = false;
  bool SingleExiting = false, Innermost = false, Guarded = false;
};

// LoopAccessAnalysis verdict on the loop's memory accesses (innermost loops
// only; Analyzed is false for outer loops). Status: safe | needs-checks |
// unsafe (= !canVectorizeMemory(), Report says why). Report is LAA's remark
// name, the same Name LoopVectorize writes to its remark YAML.
// One dependence MemoryDepChecker recorded. Kind is LLVM's DepName. Src/Dst
// are "load:<ptr>" / "store:<ptr>". Dist is address(Dst) - address(Src) in
// the same iteration, in bytes, as SCEV text -- only when both pointers are
// affine add-recurrences of the loop with the same step; else "none".
struct DepFacts {
  std::string Kind, Src, Dst, Dist;
};

// One load/store of an innermost loop and its stride, classified from the
// pointer's SCEV. Kind: unit | reverse | constant | symbolic | uniform |
// indirect | unknown. Stride: elements ("1", "-1", "3", "0"), "[<bytes>]"
// for a symbolic step (or a constant step that is not a whole number of
// elements), "none" otherwise. Versioned: LAA recorded the pointer as a
// symbolic stride (LoopVectorize may version the loop on stride == 1).
struct AccessFacts {
  std::string Op, Ptr, Kind, Stride;
  bool Versioned = false;
  // Indirect accesses and constant strides beyond 8 elements: the target has
  // a legal masked gather (load) / scatter (store) for this element type
  // (TTI); printed as gather=legal.
  bool GatherLegal = false;
};

// A call in an innermost loop, judged the way LoopVectorizationLegality does
// (LLVM 20, LoopVectorizationLegality.cpp:895-930). Vector: intrinsic (has a
// vector intrinsic), vfabi (VFDatabase mapping), tli (TLI says vectorizable),
// no. Mem: none | read | write. MathLib: LV would add its "-fno-math-errno /
// -ffast-math" hint (floating-point LibFunc with optimized codegen).
struct CallFacts {
  std::string Callee, Vector, Mem;
  bool MathLib = false;
};

// A volatile or atomic load/store ("<load|store>:<ptr>", why=volatile|atomic).
struct NonSimpleFacts {
  std::string Access, Why;
};

struct MemFacts {
  bool Analyzed = false;
  std::vector<CallFacts> Calls;         // block order
  std::vector<NonSimpleFacts> NonSimple; // block order
  std::vector<AccessFacts> Accesses; // block order, then instruction order
  bool DepsRecorded = true; // false: more than MaxDependences, list dropped
  std::vector<DepFacts> Deps;
  std::string Status, Report = "none";
  unsigned Checks = 0;
  std::string MaxSafeWidth; // "any", bits, or "n/a" when unsafe
};

// Control-flow facts of an innermost loop (Analyzed false otherwise).
// Predicated: blocks LoopVectorize must if-convert
// (LoopAccessInfo::blockNeedsPredication). EarlyExit: none (one exiting
// block) | countable | uncountable (a non-latch exit with no exit count).
// Unpredicable: the first call without a vector form or non-simple access
// in a predicated block, e.g. "call to @sqrtf in %if.then"; empty if none.
struct CFGFacts {
  bool Analyzed = false;
  unsigned Blocks = 0, Predicated = 0, Switches = 0, Exits = 0;
  std::string EarlyExit = "none", UncountableExit, Unpredicable;
};

// Loop hints from !llvm.loop metadata (#pragma clang loop). Set only when
// present. LoopVectorizeHints::allowReordering() is true when vectorization
// is forced (vectorize(enable)) or a width > 1 is given.
struct HintFacts {
  std::optional<bool> Vectorize; // llvm.loop.vectorize.enable
  std::optional<int> Width;      // llvm.loop.vectorize.width
  bool any() const { return Vectorize || Width; }
  bool allowReordering() const { return forced(); }
  // Forced vectorization: LoopVectorize skips its profitability check.
  bool forced() const { return (Vectorize && *Vectorize) || (Width && *Width > 1); }
  // vectorize(disable) is lowered to width 1 by clang.
  bool disabled() const { return (Vectorize && !*Vectorize) || (Width && *Width == 1); }
};

// Is interchanging an innermost loop with its parent legal? Computed only for
// loops the classifier reports as cost-strided (S26). Legal: yes | no |
// unknown. Dirs: the distinct (parent, loop) direction pairs of the
// dependences DependenceAnalysis finds between the loop's loads and stores
// (at least one a store), after Dependence::normalize, e.g. "(<,>)". Why
// (only for unknown): no-parent-loop | not-perfect-nest | confused |
// unsupported-memop.
struct InterchangeFacts {
  bool Computed = false;
  std::string Legal = "unknown", Why;
  std::vector<std::string> Dirs;
  // The loop's backedge-taken count varies with the parent loop (triangular
  // or trapezoidal nest, e.g. i = j..N): swapping needs new bounds, which
  // LLVM 20's LoopInterchange does not derive.
  bool BoundsDependOnParent = false;
};

struct LoopRecord {
  std::string Function, Header, File;
  unsigned Depth = 0, Line = 0, Col = 0;
  // Separate flag, not Line != 0: compiler-generated locations have line 0,
  // and LoopVectorize remarks still report them as <file>:0:0.
  bool HasLoc = false;
  bool hasLoc() const { return HasLoc; }
  TripFacts Trip;
  bool HasPreheader = false;
  std::vector<IVFacts> IVs; // header phi order; empty without a preheader
  std::vector<RecurFacts> Recurs; // non-IV header phis; empty w/o preheader
  FormFacts Form;
  HintFacts Hints;
  // Target fact: TTI::enableOrderedReductions() (true on AArch64, false on
  // x86). LoopVectorize then vectorizes exact-FP reductions in order.
  bool TargetOrderedReductions = false;
  CFGFacts CFG;
  MemFacts Mem;
  InterchangeFacts Interchange;
  Classification Class; // filled last, from the facts above
};

// MST numbers unnamed header blocks. Pass one (initially empty) slot per
// function; it is created on the first unnamed header and reused after that.
// L is non-const because LoopAccessInfoManager::getInfo takes Loop &.
LoopRecord makeLoopRecord(const llvm::Function &F, llvm::Loop &L,
                          std::unique_ptr<llvm::ModuleSlotTracker> &MST,
                          llvm::ScalarEvolution &SE,
                          llvm::DominatorTree &DT,
                          llvm::LoopAccessInfoManager &LAIM,
                          const llvm::TargetLibraryInfo &TLI,
                          const llvm::TargetTransformInfo &TTI,
                          llvm::DependenceInfo *DI = nullptr);

// Format (one block per loop):
//   "  loop header=%<hdr> depth=<d> loc=<file>:<line>:<col>"  (or loc=<none>)
//   "    trip kind=<k> [reason=<r>] count=<n|none> btc=[<scev>]
//        max-btc=[<scev>] symbolic-max-btc=[<scev>]"          (one line)
//   "    iv phi=%<p> kind=<int|ptr|fp> start=<v> step=<scev> scev=[<scev>]
//        controls-exit=<yes|no>"           (one line per IV; "    iv <none>";
//                                           "    iv <no-preheader>" if not asked)
//   "    recur phi=%<p> kind=<k> [exact-fp=yes] [ordered=yes]"
//                                          (one per non-IV header phi)
//   "    form simplify=<y/n> rotated=<y/n> lcssa=<y/n> exiting=<single|multiple>
//        innermost=<y/n> guarded=<y/n>"                       (one line)
//   "    hints [vectorize=<enable|disable>] [width=<n>]"   (only with hints)
//   "    cfg blocks=<n> predicated=<n> switches=<n> exits=<n>
//        early-exit=<none|countable|uncountable>"           (innermost)
//   "    mem status=<safe|needs-checks|unsafe> checks=<n>
//        max-safe-width=<any|bits|n/a> report=<RemarkName|none>"  (innermost)
//   "    mem <not-innermost>"                                    (outer loops)
//   "    dep kind=<DepName> src=<load|store>:<ptr> dst=<load|store>:<ptr>
//        dist=[<bytes>|none]"   (innermost; one per dependence, LAA order;
//                                "    dep <none>" / "    dep <not-recorded>")
//   "    access <load|store> ptr=<p> kind=<k> stride=<s> [versioned=yes]"
//                               (innermost; one per load/store)
//   "    call callee=<@f|indirect> vector=<intrinsic|vfabi|tli|no>
//        mem=<none|read|write> [math-lib=yes]"   (innermost; one per call)
//   "    nonsimple <load|store>:<ptr> why=<volatile|atomic>"     (innermost)
//   "    interchange legal=<yes|no|unknown> [dirs=[(<o>,<i>),...]]
//        [bounds=depend-on-parent] [why=<reason>]"
//                               (innermost cost-strided loops only, S26)
//   "    blocker primary=<cat> rule=<id> secondary=<cats|none>"  (last line;
//                               "    blocker <not-innermost>" for outer loops)
// SCEV text contains spaces, hence the brackets.
void printLoopRecord(llvm::raw_ostream &OS, const LoopRecord &R);

} // namespace looplens

#endif // LOOPLENS_LOOPRECORD_H
