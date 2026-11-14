#!/usr/bin/env python3
"""Compare LoopLens's loop-interchange verdicts with LLVM's own loop-interchange.

LoopLens writes an "interchange" object for every cost-strided loop
(JSON Lines from scripts/collect.sh or -looplens-json). This script compiles
the same sources with clang-20 -O3 -g -mllvm -enable-loopinterchange, reads
LoopInterchange's remarks (reported at the inner loop's location) and writes
one CSV row per loop with a LoopLens verdict.

  llvm   interchanged | refused-dependences | refused-not-tightly-nested |
         refused-other | none (no remark at that line)
  agree  yes when (LoopLens legal=yes) == (LLVM interchanged)

LLVM's pass also checks profitability, so "refused" is not proof of
illegality; the two documented differences are in test/interchange/.

Usage: interchange_oracle.py --raw DIR --src FILE [--src FILE ...]
                             [--cflags "..."] --out CSV
"""
import argparse
import csv
import glob
import json
import os
import re
import subprocess
import sys

REMARK = re.compile(r"^(?P<file>[^:\s]+):(?P<line>\d+):\d+: remark: (?P<msg>.*?)(?: \[-R.*\])?$")


def llvm_kind(msg):
    if msg.startswith("Loop interchanged"):
        return "interchanged"
    if "due to dependences" in msg:
        return "refused-dependences"
    if "not tightly nested" in msg:
        return "refused-not-tightly-nested"
    return "refused-other"


def llvm_remarks(srcs, cflags, clang):
    out = {}
    for src in srcs:
        cmd = [clang, "-O3", "-g", "-mllvm", "-enable-loopinterchange",
               "-Rpass=loop-interchange", "-Rpass-missed=loop-interchange",
               "-c", src, "-o", os.devnull] + cflags.split()
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            sys.exit("clang failed on %s:\n%s" % (src, res.stderr))
        for ln in res.stderr.splitlines():
            m = REMARK.match(ln)
            if not m:
                continue
            key = (os.path.basename(m["file"]), int(m["line"]))
            kind = llvm_kind(m["msg"])
            # Several remarks can share a line (deeper nests): an interchange
            # wins, then the first refusal seen.
            if key not in out or kind == "interchanged":
                out[key] = kind
    return out


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--src", action="append", required=True)
    ap.add_argument("--cflags", default="")
    ap.add_argument("--clang", default="clang-20")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)

    rows = []
    for path in sorted(glob.glob(os.path.join(a.raw, "*.jsonl"))):
        with open(path) as f:
            for ln in f:
                r = json.loads(ln)
                x = r.get("interchange")
                if x is None or r.get("line") is None:
                    continue
                legal = {True: "yes", False: "no", None: "unknown"}[x["legal"]]
                rows.append([os.path.basename(r["file"]), int(r["line"]), r["function"], legal,
                             x["why"] or "", " ".join(d.replace(",", ";") for d in x["dirs"])])
    remarks = llvm_remarks(a.src, a.cflags, a.clang)
    agree = 0
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["file", "line", "function", "looplens_legal", "looplens_why", "dirs", "llvm", "agree"])
        for row in sorted(rows):
            kind = remarks.get((row[0], row[1]), "none")
            ok = (row[3] == "yes") == (kind == "interchanged")
            agree += ok
            w.writerow(row + [kind, "yes" if ok else "no"])
    print("loops with a verdict: %d, LLVM agrees: %d" % (len(rows), agree))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
