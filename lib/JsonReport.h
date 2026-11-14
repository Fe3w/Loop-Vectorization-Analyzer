//===- JsonReport.h - One JSON object per loop (JSON Lines) -----*- C++ -*-===//
//
// Serialises a LoopRecord as one line of JSON. Schema: README "JSON report".
//
//===----------------------------------------------------------------------===//

#ifndef LOOPLENS_JSONREPORT_H
#define LOOPLENS_JSONREPORT_H

#include "llvm/ADT/StringRef.h"

namespace llvm {
class raw_ostream;
} // namespace llvm

namespace looplens {

struct LoopRecord;

// Writes one JSON object and a newline.
void writeLoopJson(llvm::raw_ostream &OS, const LoopRecord &R);

// The process-wide JSON Lines stream for Path, opened (truncated) on first
// use and appended to afterwards, so every function of a run lands in one
// file. "%p" in Path is replaced by the process ID. Returns nullptr (after one
// error message) if it cannot be opened.
llvm::raw_ostream *jsonStream(llvm::StringRef Path);

} // namespace looplens

#endif // LOOPLENS_JSONREPORT_H
