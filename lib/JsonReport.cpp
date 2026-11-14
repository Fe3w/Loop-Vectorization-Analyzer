//===- JsonReport.cpp - One JSON object per loop (JSON Lines) -------------===//

#include "JsonReport.h"
#include "Classifier.h"
#include "LoopRecord.h"

#include "llvm/Support/FileSystem.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/Process.h"
#include "llvm/Support/raw_ostream.h"

#include <memory>
#include <string>

using namespace llvm;

namespace looplens {

void writeLoopJson(raw_ostream &OS, const LoopRecord &R) {
  json::OStream J(OS); // indent 0: the whole object on one line
  J.object([&] {
    J.attribute("function", R.Function);
    J.attribute("header", R.Header);
    J.attribute("depth", int64_t(R.Depth));
    if (R.hasLoc()) {
      J.attribute("file", R.File);
      J.attribute("line", int64_t(R.Line));
      J.attribute("col", int64_t(R.Col));
    } else {
      J.attribute("file", nullptr);
      J.attribute("line", nullptr);
      J.attribute("col", nullptr);
    }
    const Classification &C = R.Class;
    J.attribute("innermost", C.Analyzed);
    if (C.Analyzed) {
      J.attribute("primary", blockerName(C.Primary));
      J.attribute("rule", C.RuleId);
      J.attributeArray("secondary", [&] {
        for (Blocker B : C.Secondary)
          J.value(blockerName(B));
      });
      J.attribute("evidence", C.Evidence);
      J.attribute("fix", C.Fix);
    } else {
      J.attribute("primary", nullptr);
    }
    J.attributeObject("trip", [&] {
      J.attribute("kind", R.Trip.Kind == TripKind::Constant   ? "constant"
                          : R.Trip.Kind == TripKind::Symbolic ? "symbolic"
                                                              : "unknown");
      // A string, not a number: counts may exceed 64 bits.
      if (R.Trip.Kind == TripKind::Constant)
        J.attribute("count", R.Trip.Count);
      else
        J.attribute("count", nullptr);
      J.attribute("btc", R.Trip.BTC);
    });
    if (R.Interchange.Computed)
      J.attributeObject("interchange", [&] {
        const InterchangeFacts &X = R.Interchange;
        if (X.Legal == "unknown")
          J.attribute("legal", nullptr);
        else
          J.attribute("legal", X.Legal == "yes");
        J.attributeArray("dirs", [&] {
          for (const std::string &D : X.Dirs)
            J.value(D);
        });
        J.attribute("bounds_depend_on_parent", X.BoundsDependOnParent);
        if (X.Why.empty())
          J.attribute("why", nullptr);
        else
          J.attribute("why", X.Why);
      });
    if (R.Mem.Analyzed)
      J.attributeObject("mem", [&] {
        J.attribute("status", R.Mem.Status);
        J.attribute("checks", int64_t(R.Mem.Checks));
        J.attribute("report", R.Mem.Report);
      });
  });
  OS << '\n';
}

raw_ostream *jsonStream(StringRef Path) {
  // Process-global: one compiler process writes one file. Use "%p" in the
  // path when several processes might write at once.
  static std::unique_ptr<raw_fd_ostream> Stream;
  static std::string OpenedPath;
  static bool Failed = false;
  if (Stream && OpenedPath == Path)
    return Stream.get();
  if (Failed)
    return nullptr;
  // "%p" -> process ID: one file per compiler process (parallel builds, LTO
  // backends), the convention LLVM uses for profile file names.
  std::string Resolved = Path.str();
  for (size_t P = Resolved.find("%p"); P != std::string::npos;
       P = Resolved.find("%p", P))
    Resolved.replace(P, 2, std::to_string(sys::Process::getProcessId()));
  std::error_code EC;
  auto S = std::make_unique<raw_fd_ostream>(Resolved, EC, sys::fs::OF_Text);
  if (EC) {
    errs() << "looplens: cannot open JSON file '" << Resolved
           << "': " << EC.message() << "\n";
    Failed = true;
    return nullptr;
  }
  Stream = std::move(S);
  OpenedPath = Path.str();
  return Stream.get();
}

} // namespace looplens
