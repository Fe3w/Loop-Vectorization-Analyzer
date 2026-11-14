#!/usr/bin/env python3
"""What does GCC do with the loops LoopLens explains? (S28)

Input: an agreement CSV from scripts/agreement.py (one row per loop, with
LoopVectorize's verdict and LoopLens's category; only rows LoopLens matched,
match=both, are used). Each source file in it is compiled with
gcc -O3 -g -fopt-info-vec-all -- the same optimisation level, debug info and
include directories as scripts/collect.sh, no extra flags -- and GCC's
vectorizer messages are joined to the loops on (file, line).

GCC 13 messages used (stderr):
  <f>:<l>:<c>: optimized: loop vectorized using N byte vectors
  <f>:<l>:<c>: missed: couldn't vectorize loop
  <f>:<l2>:<c2>: missed: not vectorized: <reason>   (follows the line above;
                                                     may point at a statement)
  <f>:<l2>:<c2>: missed: statement clobbers memory: <stmt>   (a call, instead
                                                     of the line above)
A loop GCC reports as vectorized anywhere wins over a "couldn't vectorize"
for the same line (GCC re-analyses after versioning or for an epilogue).
GCC's loop location is the `for` line, as LLVM's Loop::getStartLoc(); the
columns differ, so two LoopLens loops on one line with different columns are
"ambiguous", not guessed (same column = one loop inlined into two functions). GCC's reason is a one-line summary, so the category mapping below is
approximate: e.g. an FP reduction into a memory location is reported as
"complicated access pattern".

Outputs: --out (one row per loop) and --summary (counts per group), plus
<out without .csv>_toolchain.txt with the GCC version.

Usage: gcc_compare.py --agreement results/agreement.csv --suite polybench
         [--include DIR ...] [--gcc gcc-13] [--gcc-output FILE]
         --out CSV --summary CSV
"""
import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
from collections import OrderedDict

# (substring of GCC's "not vectorized:" reason, LoopLens category). First match wins.
REASONS = [
    ("control flow in loop", "control-flow"),           # not if-converted
    ("latch block not empty", "control-flow"),          # loop form
    ("complicated access pattern", "stride"),           # data-ref analysis failed
    ("not suitable for gather", "stride"),
    ("unsupported use in stmt", "reduction"),           # e.g. exact-FP reduction
    ("unsupported use of nested cycle", "reduction"),
    ("reduction", "reduction"),
    ("possible dependence", "loop-carried-dependence"),
    ("bad data dependence", "loop-carried-dependence"),
    ("unsafe dependent", "loop-carried-dependence"),
    ("number of iterations cannot be computed", "trip-count"),
    ("clobbers memory", "call-or-unsafe-memop"),
    ("function call", "call-or-unsafe-memop"),
    ("not profitable", "cost"),
    ("cost model", "cost"),
    ("multiple nested loops", "outer-loop"),
    ("consecutive inner loops", "outer-loop"),
    ("inner-loop count not invariant", "outer-loop"),
]

MSG = re.compile(r"^(?P<file>[^:\s]+):(?P<line>\d+):\d+: (?P<kind>optimized|missed): (?P<msg>.*)$")


def gcc_category(reason):
    for pat, cat in REASONS:
        if pat in reason:
            return cat
    return "other"


def parse(text):
    """{(file, line): (verdict, reason)} from GCC's -fopt-info-vec-all stderr."""
    out, pending = {}, None
    for ln in text.splitlines():
        m = MSG.match(ln)
        if not m:
            continue
        key, msg = (m["file"], int(m["line"])), m["msg"].strip()
        if m["kind"] == "optimized" and msg.startswith("loop vectorized"):
            out[key] = ("vectorized", "")
            pending = None
        elif m["kind"] == "missed" and msg == "couldn't vectorize loop":
            if out.get(key, ("",))[0] != "vectorized":
                out[key] = ("missed", "")
            pending = key
        elif m["kind"] == "missed" and pending and (msg.startswith("not vectorized:")
                                                    or msg.startswith("statement clobbers memory")):
            # A call GCC cannot vectorize is reported as "statement clobbers
            # memory: <stmt>" instead of a "not vectorized:" line.
            reason = (msg[len("not vectorized:"):].strip().rstrip(".")
                      if msg.startswith("not vectorized:") else "statement clobbers memory")
            # Drop GCC's statement dump ("no vectype for stmt: _2 = a[i_29];").
            reason = reason.split(": ", 1)[0]
            if out.get(pending) == ("missed", ""):
                out[pending] = ("missed", reason)
            pending = None
    return out


def run_gcc(gcc, files, includes):
    text = []
    for f in files:
        cmd = [gcc, "-O3", "-g", "-fopt-info-vec-all", "-c", f, "-o", os.devnull, "-I", os.path.dirname(f)]
        for inc in includes:
            cmd += ["-I", inc]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            sys.exit("%s failed on %s:\n%s" % (gcc, f, res.stderr))
        text.append(res.stderr)
    return "\n".join(text)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--agreement", required=True)
    ap.add_argument("--suite", required=True)
    ap.add_argument("--include", action="append", default=[])
    ap.add_argument("--gcc", default=shutil.which("gcc-13") and "gcc-13" or "gcc")
    ap.add_argument("--gcc-output", help="parse this file instead of running GCC (tests)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--summary", required=True)
    a = ap.parse_args(argv)

    with open(a.agreement, newline="") as f:
        loops = [r for r in csv.DictReader(f) if r["match"] == "both"]
    if a.gcc_output:
        text = open(a.gcc_output).read()
    else:
        files = list(OrderedDict.fromkeys(r["file"] for r in loops))
        text = run_gcc(a.gcc, files, a.include)
        ver = subprocess.run([a.gcc, "--version"], stdout=subprocess.PIPE, text=True).stdout.splitlines()[0]
        with open(os.path.splitext(a.out)[0] + "_toolchain.txt", "w") as f:
            f.write("gcc: %s\nflags: -O3 -g -fopt-info-vec-all -I <file dir>%s\n"
                    % (ver, "".join(" -I " + i for i in a.include)))
    gcc = parse(text)
    # Rows on one line with the same column are one source loop inlined into
    # another function (e.g. a TSVC kernel and its copy in main): GCC's one
    # verdict for the line applies to each. Different columns: ambiguous.
    cols = {}
    for r in loops:
        cols.setdefault((r["file"], int(r["line"])), set()).add(r["col"])

    rows = []
    for r in loops:
        key = (r["file"], int(r["line"]))
        llvm = "vectorized" if r["lv_verdict"] == "Vectorized" else "missed"
        if len(cols[key]) > 1:
            verdict, reason, cat = "ambiguous", "", ""
        elif key in gcc:
            verdict, reason = gcc[key]
            cat = gcc_category(reason) if verdict == "missed" else "none"
            if verdict == "missed" and not reason:
                cat = "other"
        else:
            verdict, reason, cat = "none", "", ""
        same = "yes" if cat and cat == r["looplens_primary"] else "no"
        rows.append([a.suite, r["file"], key[1], r["function"], r["looplens_primary"], r["looplens_rule"],
                     llvm, verdict, reason, cat, same])
    rows.sort(key=lambda x: (x[1], x[2], x[4]))
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["suite", "file", "line", "function", "looplens_primary", "looplens_rule", "llvm", "gcc",
                    "gcc_reason", "gcc_category", "same_category"])
        w.writerows(rows)

    def count(group, rs):
        vec = sum(x[7] == "vectorized" for x in rs)
        same = sum(x[7] == "missed" and x[10] == "yes" for x in rs)
        other = sum(x[7] == "missed" and x[10] == "no" for x in rs)
        return [a.suite, group, len(rs), vec, same, other, len(rs) - vec - same - other]

    summ = [count("all", rows),
            count("llvm-vectorized", [x for x in rows if x[6] == "vectorized"]),
            count("llvm-missed", [x for x in rows if x[6] == "missed"])]
    for cat in sorted({x[4] for x in rows if x[6] == "missed"}):
        summ.append(count("looplens:" + cat, [x for x in rows if x[6] == "missed" and x[4] == cat]))
    with open(a.summary, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["suite", "group", "loops", "gcc_vectorized", "gcc_missed_same_category",
                    "gcc_missed_other_category", "gcc_no_verdict"])
        w.writerows(summ)
    m = summ[2]
    print("%s: %d loops; LLVM missed %d, of which GCC vectorizes %d; both missed with the same category: "
          "%d of %d with a GCC reason" % (a.suite, len(rows), m[2], m[3], m[4], m[4] + m[5]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
