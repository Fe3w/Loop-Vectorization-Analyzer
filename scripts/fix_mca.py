#!/usr/bin/env python3
"""Static cost estimate of each suggested fix with llvm-mca (S27).

For every fix example (bench/fixes/<rule>/before.c, after.c, *.flags) compile
before and after with clang-20 -O3 -fno-unroll-loops -S, cut the hot loop out
of the assembly and ask llvm-mca for its steady-state block reciprocal
throughput. Cycles per element = Block RThroughput / elements per iteration
(LoopVectorize's width x interleave count from its remark; 1 when scalar).

-fno-unroll-loops: one iteration of the scalar loop is one source iteration,
and clang then also turns off LoopVectorize's interleaving (IC = 1); the
remark's interleave count is still used, so nothing is assumed.

Which loop: clang marks every loop header "# =>This Inner Loop Header". The
body runs from that label to the backward branch to it. For a vectorized
build the first body with packed SIMD instructions is taken (the other one is
the scalar remainder); otherwise the first inner loop.

Target: generic x86-64 (-mcpu=x86-64, the target the agreement figures use).
If the example's flags contain -march=<cpu>, both variants are modelled on
that CPU: before is compiled without the flag (the flag is the fix, e.g.
stride-gather's -march=x86-64-v4), after with it -- the same machine running
code built without and with the fix.

What this is not: a measurement. llvm-mca models one loop iteration in steady
state -- no caches or memory bandwidth, no loop entry/exit, remainder or
runtime-check cost, and a call counts as one instruction, so a loop with a
call (has_call=yes) gets no ratio: estimated_speedup is "n/a" when either
row has a call, else before / after cycles per element, on the after row.

Usage: fix_mca.py [--examples bench/fixes] [--out results/fix_mca.csv]
                  [--plugin build/lib/LoopLens.so] [--mcpu x86-64]
       fix_mca.py --extract FILE.s [--vectorized | --last]
"""
import argparse
import csv
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CLANG = os.environ.get("CLANG", "clang-20")
MCA = os.environ.get("LLVM_MCA", "llvm-mca-20")

HEADER = re.compile(r"^(\.LBB\w+):.*Inner Loop Header")
LABEL = re.compile(r"^\s*([.\w$]+):")
VEC_REG = re.compile(r"%[xyz]mm\d+")
# Packed SIMD: p* / vp* (packed integer), movdq*, *ps / *pd (packed FP),
# gathers and scatters -- always with an xmm/ymm/zmm operand.
PACKED = re.compile(r"^(v?p\w+|v?movdq\w*|v?\w+p[sd]|v?\w*(gather|scatter)\w*)$")


def loops(asm_lines):
    """[(label, [instruction lines])] for every inner loop header."""
    out = []
    for i, ln in enumerate(asm_lines):
        m = HEADER.match(ln)
        if not m:
            continue
        label, body = m.group(1), []
        back = re.compile(r"^\s*j\w+\s+" + re.escape(label) + r"\s*(#.*)?$")
        for ln2 in asm_lines[i + 1:]:
            s = ln2.split("#", 1)[0].strip()
            if not s or LABEL.match(ln2) or s.startswith("."):
                continue
            body.append(re.sub(r"\s+", " ", s, count=1))
            if back.match(ln2):
                break
        out.append((label, body))
    return out


def is_packed(body):
    return any(PACKED.match(ins.split(" ", 1)[0]) and VEC_REG.search(ins) for ins in body)


def pick(asm_lines, vectorized, last=False):
    ls = loops(asm_lines)
    if not ls:
        return None
    if last:
        return ls[-1]
    if vectorized:
        for lp in ls:
            if is_packed(lp[1]):
                return lp
        return None
    return ls[0]


def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def compile_asm(src, flags, out_s):
    res = run([CLANG, "-O3", "-fno-unroll-loops", "-Rpass=loop-vectorize", "-S", src, "-o", out_s] + flags)
    if res.returncode != 0:
        sys.exit("clang failed on %s:\n%s" % (src, res.stderr))
    m = re.search(r"vectorization width: (\d+), interleaved count: (\d+)", res.stderr)
    return (int(m.group(1)) * int(m.group(2))) if m else None


def mca(body, mcpu, tmp):
    path = os.path.join(tmp, "body.s")
    with open(path, "w") as f:
        f.write("\n".join(body) + "\n")
    res = run([MCA, "-mtriple=x86_64-linux-gnu", "-mcpu=" + mcpu, "-iterations=100", path])
    if res.returncode != 0:
        sys.exit("llvm-mca failed:\n%s" % res.stderr)
    m = re.search(r"Block RThroughput:\s*([0-9.]+)", res.stdout)
    return float(m.group(1))


def looplens_rule(src, flags, plugin):
    res = run([CLANG, "-O3", "-fpass-plugin=" + plugin, "-Xclang", "-load", "-Xclang", plugin,
               "-mllvm", "-looplens-text=false", "-Rpass-analysis=looplens", "-c", src, "-o", os.devnull]
              + flags)
    m = re.search(r"Rule: ([a-z-]+);", res.stderr)
    return m.group(1) if m else "none"


def read_flags(path):
    return open(path).read().split() if os.path.exists(path) else []


def estimate(examples, out, plugin, default_cpu):
    rows, n_after = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        for name in sorted(os.listdir(examples)):
            d = os.path.join(examples, name)
            if not os.path.isfile(os.path.join(d, "before.c")):
                continue
            bflags = read_flags(os.path.join(d, "before.flags"))
            aflags = read_flags(os.path.join(d, "after.flags"))
            march = [f for f in bflags + aflags if f.startswith("-march=")]
            mcpu = march[-1].split("=", 1)[1] if march else default_cpu
            rule = looplens_rule(os.path.join(d, "before.c"), bflags, plugin)
            cpe = {}
            for variant, flags in (("before", bflags), ("after", bflags + aflags)):
                src = os.path.join(d, variant + ".c")
                if not os.path.exists(src):
                    continue
                s_path = os.path.join(tmp, "%s.%s.s" % (name, variant))
                elems = compile_asm(src, flags, s_path)
                lp = pick(open(s_path).read().splitlines(), elems is not None)
                row = [name, rule, variant, "yes" if elems else "no", elems or 1]
                if lp is None:
                    rows.append(row + ["", "", "", "", mcpu, "not-found", ""])
                    continue
                rt = mca(lp[1], mcpu, tmp)
                c = rt / (elems or 1)
                has_call = any(ins.startswith("call") for ins in lp[1])
                cpe[variant] = None if has_call else c
                speed = ""
                if variant == "after" and "before" in cpe:
                    n_after += 1
                    both = cpe["before"] is not None and cpe[variant] is not None
                    speed = "%.2f" % (cpe["before"] / c) if both else "n/a"
                rows.append(row + [len(lp[1]), "%.2f" % rt, "%.3f" % c, "yes" if has_call else "no",
                                   mcpu, "found", speed])
    with open(out, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["example", "rule", "variant", "vectorized", "elements_per_iter", "instructions",
                    "block_rthroughput", "cycles_per_element", "has_call", "mcpu", "loop",
                    "estimated_speedup"])
        w.writerows(rows)
    print("examples: %d, with an after row: %d" % (len({r[0] for r in rows}), n_after))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--examples", default=os.path.join(ROOT, "bench", "fixes"))
    ap.add_argument("--out", default=os.path.join(ROOT, "results", "fix_mca.csv"))
    ap.add_argument("--plugin", default=os.path.join(ROOT, "build", "lib", "LoopLens.so"))
    ap.add_argument("--mcpu", default="x86-64")
    ap.add_argument("--extract")
    ap.add_argument("--vectorized", action="store_true")
    ap.add_argument("--last", action="store_true")
    a = ap.parse_args(argv)
    if a.extract:
        lp = pick(open(a.extract).read().splitlines(), a.vectorized, a.last)
        if lp is None:
            print("# loop not-found")
            return 1
        print("# loop %s packed=%s instructions=%d" % (lp[0], "yes" if is_packed(lp[1]) else "no", len(lp[1])))
        print("\n".join(lp[1]))
        return 0
    estimate(a.examples, a.out, a.plugin, a.mcpu)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
