#!/usr/bin/env python3
"""Draw the LoopLens result figures as SVG, from the files in results/ only.

Figures (written to results/plots/ by default); each is skipped when its inputs
are missing, so no figure ever shows a number that is not in results/:
  headline.svg           four result tiles: agreement, fixes verified, repair
                         correctness, measured speedup (each tile needs its CSV)
  agreement.svg          agreement with LoopVectorize per target and suite; the
                         disagreements split by LLVM's reason when the per-loop
                         CSVs exist
  blockers.svg           why LoopVectorize left loops scalar: its first reason
                         per missed loop, per target and suite (per-loop CSVs)
  tsvc_before_after.svg  TSVC on generic x86-64: first, untuned run vs current
  speedup.svg            median(base) / median(repair) per repaired kernel and
                         configuration, with an IQR-based range (timing.csv)
  gcc_compare.svg        what GCC 13 does with the loops LLVM 20 left scalar
  interchange.svg        the LLVM 20.1.2 loop-interchange checksum vs newer LLVM
                         (interchange_newer_llvm.txt)

Standard library only (no matplotlib): nothing to install, and the output is
deterministic text, so `--check` can verify that the committed figures are
exactly what the committed results produce. Colours: a fixed categorical order
(validated for colour-vision deficiency); every colour also has a legend entry
or a printed label, so no figure relies on colour alone.

Usage: scripts/plots.py [results-dir] [--out DIR] [--check]
"""
import csv
import os
import re
import sys
from xml.sax.saxutils import escape

TARGETS = [("x86-64 (generic)", ""), ("x86-64-v4 (AVX-512)", "x86v4_"), ("AArch64", "aarch64_")]
SUITES = [("PolyBench", "", "tuning set"), ("TSVC", "tsvc_", "mostly held out")]

# Categorical slots, always used in this order (never cycled).
SLOT = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
GOOD, CRITICAL = "#0ca30c", "#d03b3b"
SURFACE, INK, INK2, MUTED = "#fcfcfb", "#0b0b0b", "#52514e", "#898781"
GRID, AXIS, BORDER = "#e1e0d9", "#c3c2b7", "#e3e3e1"
FONT = "font-family='system-ui, -apple-system, &quot;Segoe UI&quot;, Helvetica, Arial, sans-serif'"
W = 960
PAD = 28

# Analyzer / LoopVectorize categories, in report order, with display names.
CATEGORIES = [("reduction", "reduction"), ("control-flow", "control flow"),
              ("loop-carried-dependence", "loop-carried dependence"),
              ("call-or-unsafe-memop", "call or unsafe memory op"), ("aliasing", "aliasing"),
              ("trip-count", "trip count"), ("stride", "stride"),
              ("cost", "cost model")]


# ---------------------------------------------------------------- reading

def read_rows(path):
    if not os.path.exists(path):
        return None
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def read_one(path):
    rows = read_rows(path)
    return rows[0] if rows else None


# ---------------------------------------------------------------- drawing

def tw(s, size):
    """Approximate rendered width of s in a sans face (no font metrics here)."""
    return len(s) * size * 0.53


def text(x, y, s, size=12, anchor="start", weight="400", fill=INK, font=None):
    return ("<text x='%.1f' y='%.1f' font-size='%d' text-anchor='%s' font-weight='%s' fill='%s' %s>%s</text>"
            % (x, y, size, anchor, weight, fill, font or FONT, escape(str(s))))


def wrap(s, size, width):
    words, lines, cur = s.split(" "), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if cur and len(t) * size * 0.5 > width:
            lines.append(cur)
            cur = w
        else:
            cur = t
    if cur:
        lines.append(cur)
    return lines


def rrect(x, y, w, h, fill, r=4, title=None):
    """A block with rounded corners (segmented-bar parts, tiles)."""
    r = min(r, w / 2, h / 2)
    t = "<title>%s</title>" % escape(title) if title else ""
    return ("<rect x='%.1f' y='%.1f' width='%.1f' height='%.1f' rx='%.1f' fill='%s'>%s</rect>"
            % (x, y, w, h, r, fill, t))


def hbar(x, y, w, h, fill, title=None):
    """A bar growing right from a baseline: square at the baseline, 4px rounded data-end."""
    t = "<title>%s</title>" % escape(title) if title else ""
    if w <= 0:
        return ""
    r = min(4.0, w, h / 2)
    d = ("M%.1f,%.1f H%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f V%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f H%.1f Z"
         % (x, y, x + w - r, r, r, x + w, y + r, y + h - r, r, r, x + w - r, y + h, x))
    return "<path d='%s' fill='%s'>%s</path>" % (d, fill, t)


def line(x1, y1, x2, y2, stroke=GRID, width=1):
    return ("<line x1='%.1f' y1='%.1f' x2='%.1f' y2='%.1f' stroke='%s' stroke-width='%s'/>"
            % (x1, y1, x2, y2, stroke, width))


def on_fill(color):
    return INK if color in (SLOT[3],) else "#ffffff"


class Fig:
    def __init__(self, title, subtitle, desc):
        self.parts = []
        self.title, self.desc = title, desc
        self.y = PAD + 6
        self.parts.append(text(PAD, self.y + 14, title, 18, weight="600"))
        self.y += 26
        for ln in wrap(subtitle, 12.5, W - 2 * PAD):
            self.parts.append(text(PAD, self.y + 12, ln, 12.5, fill=INK2))
            self.y += 18
        self.y += 14

    def add(self, *s):
        self.parts.extend(x for x in s if x)

    def legend(self, items, y=None):
        """items: [(color, label)]; wraps onto further rows."""
        y = self.y if y is None else y
        x = PAD
        for color, label in items:
            wdt = 14 + 6 + tw(label, 12) + 22
            if x + wdt > W - PAD:
                x = PAD
                y += 22
            self.add(rrect(x, y, 12, 12, color, 3), text(x + 18, y + 10.5, label, 12, fill=INK2))
            x += wdt
        self.y = y + 26

    def notes(self, lines, size=11.5, fill=INK2):
        for s in lines:
            for ln in wrap(s, size, W - 2 * PAD):
                self.add(text(PAD, self.y + 11, ln, size, fill=fill))
                self.y += 17
        self.y += 2

    def svg(self):
        h = int(self.y + PAD - 6)
        head = ["<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 %d %d' width='%d' height='%d' role='img'>"
                % (W, h, W, h),
                "<title>%s</title><desc>%s</desc>" % (escape(self.title), escape(self.desc)),
                "<rect x='0.5' y='0.5' width='%d' height='%d' rx='10' fill='%s' stroke='%s'/>"
                % (W - 1, h - 1, SURFACE, BORDER)]
        return "\n".join(head + self.parts + ["</svg>"]) + "\n"


def segmented(fig, x, y, width, h, parts, total):
    """parts: [(count, color, name)]; widths proportional to count/total; 2px gaps;
    each part prints its count inside when the count fits."""
    cx = x
    for count, color, name in parts:
        if count <= 0:
            continue
        w = width * count / total
        fig.add(rrect(cx + 1, y, max(w - 2, 1.5), h, color, 4, "%s: %d" % (name, count)))
        lab = str(count)
        if w - 2 >= tw(lab, 11) + 10:
            fig.add(text(cx + 7, y + h / 2 + 4, lab, 11, weight="600", fill=on_fill(color)))
        cx += w


# ---------------------------------------------------------------- figures

NAME = "Loop Vectorization Analyzer"
MONO = "font-family='ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'"


def agreement_plot(d):
    rows = []
    for tname, tpre in TARGETS:
        for sname, spre, role in SUITES:
            s = read_one(os.path.join(d, spre + tpre + "agreement_summary.csv"))
            if s is not None:
                loops = read_rows(os.path.join(d, spre + tpre + "agreement.csv"))
                rows.append((tname, sname, role, s, loops))
    if not rows:
        return None
    fig = Fig("Agreement with LLVM’s vectorizer",
              "Loops where the %s gives the same reason as LoopVectorize. clang-20 -O3, LLVM 20.1.2." % NAME,
              "Agreement with LoopVectorize per target and benchmark suite.")
    lx, bx, bw, rx = PAD, PAD + 200, W - 2 * PAD - 200 - 210, W - PAD
    cost_dis = other_dis = 0
    kinds = [("same reason", SLOT[0], "same reason"),
             ("differs: LLVM cost model", SLOT[1], "differs: LLVM cost model"),
             ("differs: other", SLOT[2], "differs: other"),
             ("differs", SLOT[3], "differs")]
    used = set()
    last = None
    for tname, sname, role, s, loops in rows:
        if tname != last:
            fig.add(text(lx, fig.y + 14, tname, 13.5, weight="600"))
            fig.y += 24
            last = tname
        n, agree = int(s["loops_both"]), int(s["agree"])
        y = fig.y
        fig.add(text(lx + 12, y + 14, sname, 12.5), text(lx + 12 + tw(sname, 12.5) + 8, y + 14, role, 11.5, fill=MUTED))
        if loops is not None:
            dis = [r for r in loops if r["agree"] == "no"]
            c = sum(1 for r in dis if r["lv_category"] == "cost")
            cost_dis += c
            other_dis += len(dis) - c
            counts = {"same reason": agree, "differs: LLVM cost model": c, "differs: other": len(dis) - c}
            total = max(n, agree + len(dis))
        else:
            counts = {"same reason": agree, "differs": n - agree}
            total = n
        used |= {k for k, v in counts.items() if v > 0}
        segmented(fig, bx, y, bw, 20, [(counts.get(k, 0), col, k) for k, col, _ in kinds], total)
        pct = 100.0 * agree / n if n else 0.0
        fig.add(text(rx - 210 + 16, y + 14, "%d / %d" % (agree, n), 13, weight="600"),
                text(rx - 210 + 16 + tw("%d / %d" % (agree, n), 13) + 10, y + 14, "%.1f%%" % pct, 12, fill=INK2))
        cov = s.get("all_reasons_covered")
        if cov and int(cov) != agree:
            fig.add(text(rx - 210 + 16, y + 30, "all reasons covered: %s / %d" % (cov, n), 10.5, fill=MUTED))
        fig.y += 40
    fig.y += 4
    fig.legend([(col, lab) for k, col, lab in kinds if k in used or k == "same reason"])
    total_dis = cost_dis + other_dis
    note = []
    if total_dis:
        note.append("%d of %d differences are cost-model decisions, which the %s does not model."
                    % (cost_dis, total_dis, NAME))
    if any(r[0] == "AArch64" for r in rows):
        note.append("AArch64 is compile-only.")
    if note:
        fig.notes([" ".join(note)])
    return fig.svg()


def blockers_plot(d):
    rows = []
    for tname, tpre in TARGETS:
        for sname, spre, role in SUITES:
            loops = read_rows(os.path.join(d, spre + tpre + "agreement.csv"))
            if loops is not None:
                rows.append((tname, sname, loops))
    if not rows:
        return None
    fig = Fig("Why LLVM didn’t vectorize",
              "Missed loops, by LLVM’s first reason. clang-20 -O3, LLVM 20.1.2.",
              "Missed-vectorization reasons per target and suite.")
    cats = [c for c, _ in CATEGORIES]
    used = set()
    counted = []
    for tname, sname, loops in rows:
        missed = [r for r in loops if r["lv_verdict"] == "Missed"]
        cnt = {c: sum(1 for r in missed if r["lv_category"] == c) for c in cats}
        used |= {c for c in cats if cnt[c]}
        counted.append((tname, sname, len(missed), len(loops), cnt))
    order = [c for c in cats if c in used]
    color = {c: SLOT[i] for i, c in enumerate(order)}
    names = dict(CATEGORIES)
    top = max(m for _, _, m, _, _ in counted) or 1
    lx, bx, bw = PAD, PAD + 200, W - 2 * PAD - 200 - 150
    last = None
    for tname, sname, m, n, cnt in counted:
        if tname != last:
            fig.add(text(lx, fig.y + 14, tname, 13.5, weight="600"))
            fig.y += 24
            last = tname
        fig.add(text(lx + 12, fig.y + 14, sname, 12.5))
        segmented(fig, bx, fig.y, bw * m / top, 20, [(cnt[c], color[c], names[c]) for c in order], m)
        fig.add(text(bx + bw * m / top + 12, fig.y + 14, "%d" % m, 13, weight="600"),
                text(bx + bw * m / top + 12 + tw("%d" % m, 13) + 6, fig.y + 14, "of %d loops" % n, 11.5, fill=INK2))
        fig.y += 34
    fig.y += 6
    fig.legend([(color[c], names[c]) for c in order])
    if "cost" in used:
        fig.notes(["Cost-model rejections depend on the target."])
    return fig.svg()


def tsvc_plot(d):
    before = read_one(os.path.join(d, "tsvc_agreement_summary_before.csv"))
    after = read_one(os.path.join(d, "tsvc_agreement_summary.csv"))
    if before is None or after is None:
        return None
    fig = Fig("TSVC: first run vs final",
              "Loops paired with an LLVM verdict, and how many agree. Generic x86-64.",
              "TSVC agreement before and after tuning.")
    rows = []
    for label, s in (("First run", before), ("Final", after)):
        n, a = int(s["loops_both"]), int(s["agree"])
        rows.append((label, n, a, int(s.get("looplens_only") or 0)))
    top = max(n + u for _, n, _, u in rows) or 1
    lx, bx, bw = PAD, PAD + 120, W - 2 * PAD - 120 - 250
    for label, n, a, u in rows:
        fig.add(text(lx, fig.y + 14, label, 12.5))
        span = bw * (n + u) / top
        segmented(fig, bx, fig.y, span, 20,
                  [(a, SLOT[0], "same reason"), (n - a, SLOT[1], "differs"), (u, SLOT[2], "not paired")], n + u)
        x = bx + span + 12
        fig.add(text(x, fig.y + 14, "%d / %d agree" % (a, n), 13, weight="600"),
                text(x + tw("%d / %d agree" % (a, n), 13) + 8, fig.y + 14,
                     "%.1f%%" % (100.0 * a / n if n else 0), 12, fill=INK2))
        fig.y += 36
    fig.y += 4
    fig.legend([(SLOT[0], "same reason"), (SLOT[1], "differs"), (SLOT[2], "not paired")])
    return fig.svg()


CONFIG_ORDER = ["O3", "O3-native", "O3-fast", "O3-fast-native"]


def speedups(rows):
    by = {(r["kernel"], r["config"], r["variant"]): r for r in rows}
    data = {}
    for (k, c, v), r in by.items():
        rep = by.get((k, c, "repair"))
        if v != "base" or rep is None or float(rep["median_s"]) <= 0:
            continue
        data[(k, c)] = (float(r["median_s"]) / float(rep["median_s"]),
                        float(r["q1_s"]) / float(rep["q3_s"]), float(r["q3_s"]) / float(rep["q1_s"]))
    return data


def no_gain(data):
    ks = sorted({k for k, _ in data})
    return [k for k in ks if max(v[0] for (kk, _), v in data.items() if kk == k) < 1.02]


def speedup_plot(d):
    rows = read_rows(os.path.join(d, "timing.csv"))
    if not rows:
        return None
    data = speedups(rows)
    if not data:
        return None
    flags = {r["config"]: r["flags"] for r in rows}
    configs = [c for c in CONFIG_ORDER if c in flags] + sorted(c for c in flags if c not in CONFIG_ORDER)
    kernels = sorted({k for k, _ in data}, key=lambda k: (-max(v[0] for (kk, _), v in data.items() if kk == k), k))
    cpu = ", ".join(sorted({r["cpu_model"].split()[-1] for r in rows}))
    ds = ", ".join(sorted({r["dataset"] for r in rows}))
    runs = ", ".join(sorted({r["runs"] for r in rows}))
    fig = Fig("Speedup from the repair pass",
              "Same flags with and without repair · median of %s runs · %s · PolyBench %s · "
              "whiskers: run spread (IQR)" % (runs, cpu, ds),
              "Measured speedup of the repair pass per kernel and compiler configuration.")
    fig.legend([(SLOT[i], flags[c]) for i, c in enumerate(configs)])
    vmax = max(max(v[0], v[2]) for v in data.values())
    xmax = float(int(vmax) + 1)
    lx, ax, aw = PAD, PAD + 110, W - 2 * PAD - 110 - 70
    sx = lambda v: ax + aw * min(v, xmax) / xmax
    bh, gap = 14, 3
    group_h = len(configs) * (bh + gap) + 18
    y0 = fig.y + 22
    plot_h = len(kernels) * group_h
    for i in range(int(xmax) + 1):
        fig.add(line(sx(i), y0 - 4, sx(i), y0 + plot_h, GRID),
                text(sx(i), y0 + plot_h + 16, "%d×" % i, 11, "middle", fill=MUTED))
    for gi, k in enumerate(kernels):
        gy = y0 + gi * group_h
        fig.add(text(lx, gy + (len(configs) * (bh + gap)) / 2 + 4, k, 13, weight="600"))
        for ci, c in enumerate(configs):
            if (k, c) not in data:
                continue
            sp, lo, hi = data[(k, c)]
            y = gy + ci * (bh + gap)
            fig.add(hbar(ax, y, sx(sp) - ax, bh, SLOT[ci],
                         "%s, %s (%s): %.2f×, IQR range %.2f–%.2f×" % (k, c, flags[c], sp, lo, hi)))
            fig.add(line(sx(lo), y + bh / 2, sx(hi), y + bh / 2, INK2, 1.2),
                    line(sx(lo), y + 3, sx(lo), y + bh - 3, INK2, 1.2),
                    line(sx(hi), y + 3, sx(hi), y + bh - 3, INK2, 1.2))
            fig.add(text(max(sx(sp), sx(hi)) + 6, y + bh - 3, "%.2f×" % sp, 11.5,
                         weight="600" if sp >= 1.5 else "400", fill=INK if sp >= 1.5 else INK2))
    fig.add(line(sx(1), y0 - 8, sx(1), y0 + plot_h, INK2, 1.5),
            text(sx(1) + 4, y0 - 10, "1.00× = no change", 10.5, fill=INK2))
    fig.add(line(ax, y0 - 4, ax, y0 + plot_h, AXIS, 1))
    fig.y = y0 + plot_h + 32
    note = "Strict FP gains are small. With -ffast-math the repaired loop vectorizes."
    flat = no_gain(data)
    if flat:
        note += " %s gain%s nothing." % (", ".join(flat), "" if len(flat) > 1 else "s")
    fig.notes([note])
    return fig.svg()


def gcc_plot(d):
    suites = []
    for sname, f in (("PolyBench", "gcc_compare_polybench_summary.csv"), ("TSVC", "gcc_compare_tsvc_summary.csv")):
        rows = read_rows(os.path.join(d, f))
        if rows:
            g = {r["group"]: r for r in rows}
            if "llvm-missed" in g:
                suites.append((sname, g))
    if not suites:
        return None
    fig = Fig("GCC 13 on loops LLVM 20 left scalar", "x86-64, -O3.",
              "GCC 13 verdicts on loops LLVM 20 did not vectorize.")
    parts_def = [("gcc_vectorized", "GCC vectorizes"),
                 ("gcc_missed_same_category", "GCC misses, same reason"),
                 ("gcc_missed_other_category", "GCC misses, other reason"),
                 ("gcc_no_verdict", "no GCC verdict")]
    top = max(int(g["llvm-missed"]["loops"]) for _, g in suites) or 1
    lx, bx, bw = PAD, PAD + 120, W - 2 * PAD - 120 - 240
    shares = []
    for sname, g in suites:
        m = g["llvm-missed"]
        n = int(m["loops"])
        fig.add(text(lx, fig.y + 14, sname, 13, weight="600"))
        segmented(fig, bx, fig.y, bw * n / top, 20,
                  [(int(m[k]), SLOT[i], lab) for i, (k, lab) in enumerate(parts_def)], n)
        v = int(m["gcc_vectorized"])
        x = bx + bw * n / top + 12
        fig.add(text(x, fig.y + 14, "%d of %d" % (v, n), 13, weight="600"),
                text(x + tw("%d of %d" % (v, n), 13) + 8, fig.y + 14, "vectorized by GCC", 12, fill=INK2))
        red = g.get("looplens:reduction")
        if red and v:
            shares.append("%s %s of %d" % (sname, red["gcc_vectorized"], v))
        fig.y += 36
    fig.y += 2
    fig.legend([(SLOT[i], lab) for i, (_, lab) in enumerate(parts_def)])
    msg = "GCC keeps the source order; on x86, LLVM needs -ffast-math."
    if shares:
        msg = "Most are floating-point sums (%s). " % ", ".join(shares) + msg
    fig.notes([msg])
    return fig.svg()


def interchange_plot(d):
    path = os.path.join(d, "interchange_newer_llvm.txt")
    if not os.path.exists(path):
        return None
    vers, cur = [], None
    for ln in open(path):
        m = re.match(r"== LLVM version (\S+)", ln)
        if m:
            cur = {"v": m.group(1), "remarks": []}
            vers.append(cur)
        elif cur is not None:
            m = re.match(r"(reference|after interchange):\s+checksum=([0-9.eE+-]+)", ln)
            if m:
                cur[m.group(1)] = float(m.group(2))
            elif ln.startswith("remark:"):
                cur["remarks"].append(ln[len("remark:"):].strip())
    vers = [v for v in vers if "reference" in v and "after interchange" in v]
    if not vers:
        return None
    bad = [v["v"] for v in vers if v["after interchange"] != v["reference"]]
    good = [v["v"] for v in vers if v["after interchange"] == v["reference"]]
    title = "LLVM loop-interchange bug"
    if bad and good:
        title = "LLVM %s loop-interchange bug, fixed in LLVM %s" % (bad[0], good[0].split(".")[0])
    fig = Fig(title, "The same loop nest, run through loop-interchange in each LLVM release.",
              "A loop nest whose arrays overlap; checksum after loop-interchange per LLVM release.")
    # Panel 1: the loop (test/interchange/Inputs/overlap-colsum.c).
    y = fig.y
    pw = (W - 2 * PAD - 16) / 2
    ph = 164
    fig.add("<rect x='%.1f' y='%.1f' width='%.1f' height='%d' rx='8' fill='#ffffff' stroke='%s'/>"
            % (PAD, y, pw, ph, BORDER))
    fig.add(text(PAD + 16, y + 26, "The loop", 13, weight="600"))
    code = ["for (j = 0; j < 64; j++)", "  for (i = 0; i < 64; i++)", "    A[i][j] = A[i][j] + B[i][j];"]
    for i, c in enumerate(code):
        fig.add(text(PAD + 16 + 7.8 * (len(c) - len(c.lstrip())), y + 56 + 21 * i, c.strip(), 13, font=MONO))
    fig.add(text(PAD + 16, y + ph - 18, "B points into A:  B[i][j] is A[i+1][j−1]", 12, fill=INK2))
    # Panel 2: why the swap is illegal (dependence direction).
    x2 = PAD + pw + 16
    fig.add("<rect x='%.1f' y='%.1f' width='%.1f' height='%d' rx='8' fill='#ffffff' stroke='%s'/>"
            % (x2, y, pw, ph, BORDER))
    fig.add(text(x2 + 16, y + 26, "Why swapping the loops is illegal", 13, weight="600"))
    why = [("A[i+1][j−1] is written at iteration (j−1, i+1)", INK),
           ("and read later, at iteration (j, i).", INK),
           ("Direction (j, i) = (<, >): with i outside, the read", INK2),
           ("would run before the write.", INK2)]
    for i, (c, f) in enumerate(why):
        fig.add(text(x2 + 16, y + 56 + 20 * i, c, 12.5, fill=f))
    fig.add(text(x2 + 16, y + ph - 18, "LLVM cannot see the overlap: the dependence is “confused”.",
                 12, fill=INK2))
    fig.y = y + ph + 20
    # Panel 3: one card per release.
    n = len(vers)
    gap = 12
    cw = (W - 2 * PAD - gap * (n - 1)) / n
    ch = 112
    y = fig.y
    for i, v in enumerate(vers):
        x = PAD + i * (cw + gap)
        ok = v["after interchange"] == v["reference"]
        col = GOOD if ok else CRITICAL
        fig.add("<rect x='%.1f' y='%.1f' width='%.1f' height='%d' rx='8' fill='#ffffff' stroke='%s' stroke-width='%s'/>"
                % (x, y, cw, ch, col if not ok else BORDER, 1.5 if not ok else 1))
        fig.add(text(x + 14, y + 26, "LLVM " + v["v"], 13.5, weight="600"))
        fig.add("<circle cx='%.1f' cy='%.1f' r='9' fill='%s'/>" % (x + cw - 22, y + 21, col),
                text(x + cw - 22, y + 25.5, "✓" if ok else "✗", 12, "middle", "700", "#ffffff"))
        swapped = any("interchanged" in r for r in v["remarks"])
        fig.add(text(x + 14, y + 52, "swapped the loops" if swapped else "refused the swap", 12, fill=INK2))
        fig.add(text(x + 14, y + 80, "%.1f" % v["after interchange"], 18, weight="600"))
        fig.add(text(x + 14, y + 99, "correct result" if ok else "wrong result", 11.5, weight="600", fill=col))
    fig.y = y + ch + 14
    fig.notes(["Correct checksum: %.1f. The pass is off by default in LLVM %s." % (vers[0]["reference"], vers[0]["v"].split(".")[0])])
    return fig.svg()


def headline_plot(d):
    tiles = []
    poly = read_one(os.path.join(d, "agreement_summary.csv"))
    tsvc = read_one(os.path.join(d, "tsvc_agreement_summary.csv"))
    if poly and tsvc:
        tiles.append(("Matches LLVM’s reason", "%s / %s" % (tsvc["agree"], tsvc["loops_both"]),
                      ["TSVC loops, mostly held out",
                       "PolyBench %s / %s (tuning set)" % (poly["agree"], poly["loops_both"])]))
    fixes = read_rows(os.path.join(d, "fix_verification.csv"))
    if fixes:
        ok = [r for r in fixes if r["fix_verified"] == "yes"]
        rest = len(fixes) - len(ok)
        tiles.append(("Suggested fixes that work", "%d / %d" % (len(ok), len(fixes)),
                      ["LLVM vectorizes after the fix"] +
                      (["%d has no mechanical fix" % rest if rest == 1 else "%d have no mechanical fix" % rest]
                       if rest else [])))
    diff = read_rows(os.path.join(d, "repair_differential.csv"))
    if diff:
        same = sum(1 for r in diff if r["strict"] == "identical")
        tol = sum(1 for r in diff if r["fast_within_tolerance"] == "yes")
        tiles.append(("Repaired code, same output", "%d / %d" % (same, len(diff)),
                      ["strict-FP runs, byte-identical", "fast-math: %d / %d within tolerance" % (tol, len(diff))]))
    timing = read_rows(os.path.join(d, "timing.csv"))
    if timing:
        data = speedups(timing)
        flags = {r["config"]: r["flags"] for r in timing}
        if data:
            (bk, bc), best = max(data.items(), key=lambda kv: kv[1][0])
            ctx = ["%s, %s" % (bk, flags[bc].replace("-O3 ", ""))]
            if (bk, "O3") in data and bc != "O3":
                ctx.append("strict FP: %.2f×" % data[(bk, "O3")][0])
            flat = no_gain(data)
            if flat:
                ctx.append("no gain: %s" % ", ".join(flat))
            tiles.append(("Best repair speedup", "%.2f×" % best[0], ctx))
    if not tiles:
        return None
    fig = Fig("%s — results" % NAME, "LLVM 20.1.2 · x86-64 unless stated",
              "Headline results of the %s." % NAME)
    n = len(tiles)
    gap = 14
    tw_ = (W - 2 * PAD - gap * (n - 1)) / n

    def body_h(label, ctx):
        h = 17 * len(wrap(label, 12.5, tw_ - 28)[:2]) + 52
        return h + 16 * sum(len(wrap(c, 11.5, tw_ - 28)) for c in ctx)
    th = int(max(body_h(t[0], t[2]) for t in tiles) + 26)
    y = fig.y
    for i, (label, value, ctx) in enumerate(tiles):
        x = PAD + i * (tw_ + gap)
        fig.add("<rect x='%.1f' y='%.1f' width='%.1f' height='%d' rx='8' fill='#ffffff' stroke='%s'/>"
                % (x, y, tw_, th, BORDER))
        cy = y + 24
        for ln in wrap(label, 12.5, tw_ - 28)[:2]:
            fig.add(text(x + 14, cy, ln, 12.5, weight="500", fill=INK2))
            cy += 17
        fig.add(text(x + 14, cy + 30, value, 34, weight="600"))
        cy += 52
        for c in ctx:
            for ln in wrap(c, 11.5, tw_ - 28):
                fig.add(text(x + 14, cy, ln, 11.5, fill=INK2))
                cy += 16
    fig.y = y + th + 6
    return fig.svg()


# ---------------------------------------------------------------- main

def main(argv):
    check = "--check" in argv
    argv = [a for a in argv if a != "--check"]
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    d = argv[0] if argv else os.path.join(os.path.dirname(__file__), "..", "results")
    out = out or os.path.join(d, "plots")
    plots = {"headline.svg": headline_plot(d), "agreement.svg": agreement_plot(d),
             "blockers.svg": blockers_plot(d), "tsvc_before_after.svg": tsvc_plot(d),
             "speedup.svg": speedup_plot(d), "gcc_compare.svg": gcc_plot(d),
             "interchange.svg": interchange_plot(d)}
    if plots["speedup.svg"] is None:
        print("timing.csv not found: speedup plot skipped (it needs the measured laptop run)")
    stale = []
    os.makedirs(out, exist_ok=True)
    for name, svg in plots.items():
        path = os.path.join(out, name)
        if svg is None:
            if check and os.path.exists(path):
                stale.append(name)
            continue
        if check:
            if not os.path.exists(path) or open(path).read() != svg:
                stale.append(name)
            continue
        with open(path, "w") as f:
            f.write(svg)
        print("wrote", path)
    for name in stale:
        print("out of date: %s (re-run scripts/plots.py)" % name)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
