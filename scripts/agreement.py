#!/usr/bin/env python3
"""Score LoopLens against LLVM's loop vectorizer (LoopVectorize) on S16's raw data.

Inputs (per kernel, in --raw): <kernel>.opt.yaml (LLVM optimization record:
LoopVectorize and LoopLens remarks) and <kernel>.jsonl (LoopLens JSON Lines).

Method (docs/methodology.md):
  * LoopVectorize emits, per innermost loop, zero or more *reason* remarks
    (UnsafeDep, CantReorderFPOps, ...) at instruction locations, then one
    *per-loop* remark (Vectorized, MissedDetails, or VectorizationNotBeneficial
    for a cost-model rejection) at the loop's start location. The reasons since the previous per-loop remark of the same file
    belong to the next one. The first reason is LoopVectorize's primary.
    Interleaving* remarks are not reasons and are ignored.
  * The primary is mapped to a LoopLens category with MAPPING below.
  * Loops are matched on (file, line, col, function) of the per-loop remark
    and the LoopLens JSON line of an innermost loop (function, because an
    inlined kernel puts the same source loop into several functions).
  * agree: LoopLens primary == mapped LV category ('none' <-> Vectorized,
    'cost' <-> stride). agree_incl_secondary: the LV category is the
    LoopLens primary or one of its secondaries.

Outputs (in --out): agreement.csv (one row per loop) and
agreement_summary.csv (one row). Only the standard library and PyYAML.
"""
import argparse
import csv
import fnmatch
import glob
import json
import os
import sys

import yaml

# LLVM remark Name (glob) -> LoopLens category. Order matters: first match.
MAPPING = [
    ("Vectorized", "none"),
    ("CantReorderFPOps", "reduction"),
    ("NonReductionValueUsedOutsideLoop", "reduction"),
    ("UnsupportedPhi", "reduction"),
    ("CantVectorizeLibcall", "call-or-unsafe-memop"),
    ("CantVectorizeCall", "call-or-unsafe-memop"),
    ("CantVectorizeIntrinsic", "call-or-unsafe-memop"),
    ("CantVectorizeInstruction", "call-or-unsafe-memop"),
    ("CantVectorizeInstructionReturnType", "call-or-unsafe-memop"),
    ("NonSimpleLoad", "call-or-unsafe-memop"),
    ("CantVectorizeStore*", "call-or-unsafe-memop"),
    ("CantVectorizeNontemporal*", "call-or-unsafe-memop"),
    ("NoCFGForSelect", "control-flow"),
    ("CFGNotUnderstood", "control-flow"),
    ("EarlyExit*", "control-flow"),
    ("*EarlyExitLoop*", "control-flow"),
    ("UncountableEarlyExitLoopsDisabled", "control-flow"),
    ("UncountableEarlyExitUnsupported", "control-flow"),
    ("StructCallVectorizationUnsupported", "call-or-unsafe-memop"),
    ("CantReorderMemOps", "aliasing"),
    ("LowTripCount", "cost"),
    ("NoLatchEarlyExit", "control-flow"),
    ("TooManyUncountableEarlyExits", "control-flow"),
    ("LoopContainsUnsupported*", "control-flow"),
    ("UnsupportedOuterLoop", "control-flow"),
    ("CantComputeNumberOfIterations", "trip-count"),
    ("UnsupportedUncountableLoop", "trip-count"),
    ("UnsafeDep", "loop-carried-dependence"),
    ("CantIdentifyArrayBounds", "aliasing"),
    ("CantCheckMemDepsAtRunTime", "aliasing"),
    ("TooManySCEVRunTimeChecks", "aliasing"),
    ("*NotBeneficial", "cost"),
    ("Interleaved", "cost"),
]
# Remarks that close a loop: LoopVectorize's per-loop verdict. A cost-model
# rejection is reported only as VectorizationNotBeneficial at the loop start
# (no MissedDetails follows), so it is a verdict too (found on TSVC, S19).
# Likewise the processLoop failures reported after legality without
# MissedDetails (LoopVectorize.cpp:10366-10410 in LLVM 20.1.2).
# Interleaved: VF=1 chosen and the loop only interleaved (a !Passed remark),
# i.e. vectorization was legal but not profitable (found on AArch64).
VERDICT_ONLY = {"VectorizationNotBeneficial", "Interleaved",
                "UncountableEarlyExitLoopsDisabled",
                "UncountableEarlyExitUnsupported", "StructCallVectorizationUnsupported"}
PER_LOOP = {"Vectorized", "MissedDetails"} | VERDICT_ONLY
LV = "loop-vectorize"


def category(name):
    for pattern, cat in MAPPING:
        if fnmatch.fnmatchcase(name, pattern):
            return cat
    return "unmapped:" + name


class _Loader(yaml.SafeLoader):
    pass


def _tagged(loader, tag_suffix, node):
    d = loader.construct_mapping(node, deep=True)
    d["_kind"] = tag_suffix  # Passed, Missed, Analysis, AnalysisFPCommute, ...
    return d


_Loader.add_multi_constructor("!", _tagged)


def parse_remarks(path):
    """All remarks of one optimization record, in file order."""
    out = []
    with open(path) as f:
        for doc in yaml.load_all(f, Loader=_Loader):
            if not isinstance(doc, dict):
                continue
            loc = doc.get("DebugLoc") or {}
            out.append({
                "kind": doc.get("_kind", ""),
                "pass": str(doc.get("Pass", "")),
                "name": str(doc.get("Name", "")),
                "file": loc.get("File"),
                "line": loc.get("Line"),
                "col": loc.get("Column"),
                "function": str(doc.get("Function", "")),
            })
    return out


def attribute(remarks):
    """Per-loop LoopVectorize verdicts with the reasons that precede them."""
    loops, pending = [], {}
    for r in remarks:
        if r["pass"] != LV or r["name"].startswith("Interleaving"):  # not "Interleaved"
            continue
        key = r["file"]
        if r["name"] in PER_LOOP:
            reasons = pending.pop(key, [])
            prev = loops[-1] if loops else None
            if (r["name"] == "Interleaved" and not reasons and prev is not None
                    and prev["verdict"] == "Missed" and prev["category"] == "cost"
                    and (prev["file"], prev["line"], prev["col"], prev["function"])
                    == (r["file"], r["line"], r["col"], r["function"])):
                # Same loop: LoopVectorize decided "not beneficial" for vectors and
                # then interleaved the scalar loop (seen on AArch64).
                prev["reasons"].append(r["name"])
                if category(r["name"]) not in prev["categories"]:
                    prev["categories"].append(category(r["name"]))
                continue
            if r["name"] == "Vectorized":
                verdict, cat = "Vectorized", "none"
            elif r["name"] in VERDICT_ONLY:
                # Legality passed (no reasons pending); the cost model said no.
                reasons = reasons + [r["name"]]
                verdict, cat = "Missed", category(reasons[0])
            else:
                verdict = "Missed"
                cat = category(reasons[0]) if reasons else "unmapped:<no reason>"
            loops.append(dict(r, verdict=verdict, reasons=reasons, category=cat))
            cats = []
            for n in reasons or (["Vectorized"] if verdict == "Vectorized" else []):
                c = category(n)
                if c not in cats:
                    cats.append(c)
            loops[-1]["categories"] = cats
        else:
            pending.setdefault(key, []).append(r["name"])
    return loops


def load_loops(path):
    """Innermost LoopLens loops from one JSON Lines file."""
    loops = []
    with open(path) as f:
        for line in f:
            if line.strip():
                j = json.loads(line)
                if j.get("innermost"):
                    loops.append(j)
    return loops


def kernels(raw):
    manifest = os.path.join(raw, "manifest.csv")
    if os.path.exists(manifest):
        with open(manifest) as f:
            return [row["kernel"] for row in csv.DictReader(f)]
    return sorted(os.path.basename(p)[: -len(".opt.yaml")]
                  for p in glob.glob(os.path.join(raw, "*.opt.yaml")))


FIELDS = ["kernel", "file", "line", "col", "function", "lv_verdict", "lv_reasons",
          "lv_category", "looplens_primary", "looplens_rule", "looplens_secondary",
          "match", "agree", "agree_incl_secondary", "lv_categories",
          "all_reasons_covered"]


def agrees(lv_cat, ll_primary):
    # LoopVectorize reports a vectorize(disable)/width(1) loop as a cost verdict
    # (VectorizationNotBeneficial); LoopLens names the pragma (hint).
    return lv_cat == ll_primary or (lv_cat == "cost" and ll_primary in ("stride", "hint"))


def match(kernel, lv_loops, ll_loops):
    rows = []
    ll_by_loc = {}
    for j in ll_loops:
        ll_by_loc.setdefault((j["file"], j["line"], j["col"], j["function"]), []).append(j)
    lv_by_loc = {}
    for lv in lv_loops:
        lv_by_loc.setdefault((lv["file"], lv["line"], lv["col"], lv["function"]), []).append(lv)
    seen = set()
    for lv in lv_loops:
        # Function is part of the key: an inlined kernel puts the same
        # source loop (same file:line:col) into several functions.
        loc = (lv["file"], lv["line"], lv["col"], lv["function"])
        cands = ll_by_loc.get(loc, [])
        same = lv_by_loc[loc]
        row = dict(kernel=kernel, file=lv["file"], line=lv["line"], col=lv["col"],
                   function=lv["function"], lv_verdict=lv["verdict"],
                   lv_reasons=";".join(lv["reasons"]), lv_category=lv["category"],
                   looplens_primary="", looplens_rule="", looplens_secondary="",
                   lv_categories=";".join(lv["categories"]), all_reasons_covered="n/a")
        j, how = None, None
        if len(cands) == 1 and len(same) == 1:
            j, how = cands[0], "both"
        elif len(cands) == len(same) > 1:
            # Several loops share the key: LoopVectorize visits innermost loops
            # in program order (LoopVectorize.cpp:10775-10784, 2179-2202), the
            # order LoopLens reports them in, so pair them by position.
            j, how = cands[same.index(lv)], "both-by-order"
        if j is not None:
            seen.add(id(j))
            sec = j.get("secondary") or []
            row.update(looplens_primary=j["primary"], looplens_rule=j["rule"],
                       looplens_secondary=";".join(sec), match=how)
            row["agree"] = "yes" if agrees(lv["category"], j["primary"]) else "no"
            row["agree_incl_secondary"] = (
                "yes" if any(agrees(lv["category"], c) for c in [j["primary"]] + sec)
                else "no")
            mine = [j["primary"]] + sec
            row["all_reasons_covered"] = (
                "yes" if all(any(agrees(c, m) for m in mine) for c in lv["categories"])
                else "no")
        else:
            for c in cands:
                seen.add(id(c))
            row.update(match="ambiguous" if cands else "lv-only",
                       agree="n/a", agree_incl_secondary="n/a")
        rows.append(row)
    for j in ll_loops:
        if id(j) not in seen:
            rows.append(dict(kernel=kernel, file=j["file"], line=j["line"], col=j["col"],
                             function=j["function"], lv_verdict="", lv_reasons="",
                             lv_category="", looplens_primary=j["primary"],
                             looplens_rule=j["rule"],
                             looplens_secondary=";".join(j.get("secondary") or []),
                             match="looplens-only", agree="n/a",
                             agree_incl_secondary="n/a", lv_categories="",
                             all_reasons_covered="n/a"))
    return rows


def summarise(rows):
    both = [r for r in rows if r["match"] in ("both", "both-by-order")]
    n = len(both)
    agree = sum(r["agree"] == "yes" for r in both)
    agree2 = sum(r["agree_incl_secondary"] == "yes" for r in both)
    pct = lambda a: "%.1f" % (100.0 * a / n) if n else "n/a"
    unmapped = sorted({r["lv_category"][len("unmapped:"):] for r in rows
                       if r["lv_category"].startswith("unmapped:")})
    covered = sum(r["all_reasons_covered"] == "yes" for r in both)
    return dict(loops_both=n, agree=agree, agree_pct=pct(agree),
                agree_incl_secondary=agree2, agree_incl_secondary_pct=pct(agree2),
                looplens_only=sum(r["match"] == "looplens-only" for r in rows),
                lv_only=sum(r["match"] == "lv-only" for r in rows),
                ambiguous=sum(r["match"] == "ambiguous" for r in rows),
                unmapped=";".join(unmapped), all_reasons_covered=covered,
                all_reasons_covered_pct=pct(covered))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--raw", required=True, help="directory with <kernel>.opt.yaml/.jsonl")
    ap.add_argument("--out", help="directory for agreement.csv and agreement_summary.csv")
    ap.add_argument("--prefix", default="",
                    help="prefix for the output file names (e.g. tsvc_)")
    ap.add_argument("--dump-remarks", action="store_true",
                    help="print every parsed remark (debugging aid) and exit")
    a = ap.parse_args(argv)

    if a.dump_remarks:
        for k in kernels(a.raw):
            for r in parse_remarks(os.path.join(a.raw, k + ".opt.yaml")):
                print("%s %s %s %s:%s:%s" % (r["kind"], r["pass"], r["name"],
                                             r["file"], r["line"], r["col"]))
        return 0
    if not a.out:
        ap.error("--out is required")

    rows = []
    for k in kernels(a.raw):
        lv_loops = attribute(parse_remarks(os.path.join(a.raw, k + ".opt.yaml")))
        ll_loops = load_loops(os.path.join(a.raw, k + ".jsonl"))
        rows += match(k, lv_loops, ll_loops)

    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, a.prefix + "agreement.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    s = summarise(rows)
    with open(os.path.join(a.out, a.prefix + "agreement_summary.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(s), lineterminator="\n")
        w.writeheader()
        w.writerow(s)
    # Which compiler produced the raw data (written by scripts/collect.sh).
    tool = os.path.join(a.raw, "toolchain.txt")
    if os.path.exists(tool):
        with open(tool) as src, open(os.path.join(a.out, a.prefix + "agreement_toolchain.txt"), "w") as dst:
            dst.write(src.read())
    print("loops matched: %(loops_both)s, agree: %(agree)s (%(agree_pct)s%%), "
          "incl. secondary: %(agree_incl_secondary)s (%(agree_incl_secondary_pct)s%%)" % s)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
