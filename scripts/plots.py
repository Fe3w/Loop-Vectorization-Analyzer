#!/usr/bin/env python3
"""Draw the LoopLens result plots as SVG, from the CSVs in results/ only.

Plots (written to results/plots/ by default):
  agreement.svg          agreement with LoopVectorize by target and suite, two
                         metrics: primary reason, and all reasons covered
  tsvc_before_after.svg  TSVC on generic x86-64: first, untuned run vs current
  speedup.svg            median(base) / median(repair) per repaired kernel and
                         configuration -- only if timing.csv exists

Standard library only (no matplotlib): nothing to install, and the output is
deterministic text, so `--check` can verify that the committed plots are
exactly what the committed CSVs produce.

Usage: scripts/plots.py [results-dir] [--out DIR] [--check]
"""
import csv
import os
import sys
from xml.sax.saxutils import escape

TARGETS = [("x86-64 (generic)", ""), ("x86-64-v4 (AVX-512)", "x86v4_"), ("AArch64", "aarch64_")]
SUITES = [("PolyBench", ""), ("TSVC", "tsvc_")]
COLORS = ["#1f6f5c", "#8fbfb0"]          # primary, all-reasons
FONT = "font-family='Helvetica, Arial, sans-serif'"


def read_one(path):
    if not os.path.exists(path):
        return None
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    return rows[0] if rows else None


def text(x, y, s, size=12, anchor="middle", weight="normal", fill="#1b2420"):
    return ("<text x='%.1f' y='%.1f' font-size='%d' text-anchor='%s' font-weight='%s' fill='%s' %s>%s</text>"
            % (x, y, size, anchor, weight, fill, FONT, escape(str(s))))


def bar_chart(title, subtitle, groups, series, ymax, yfmt, width=900, height=420):
    """groups: [(label, [(value, value_label) | None per series])]."""
    left, right, top, bottom = 60, 20, 70, 70
    pw, ph = width - left - right, height - top - bottom
    out = ["<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 %d %d' width='%d' height='%d'>"
           % (width, height, width, height),
           "<rect width='%d' height='%d' fill='#ffffff'/>" % (width, height),
           text(left, 26, title, 16, "start", "bold"),
           text(left, 46, subtitle, 12, "start", fill="#5b6862")]
    ticks = 5
    for i in range(ticks + 1):
        v = ymax * i / ticks
        y = top + ph - ph * i / ticks
        out.append("<line x1='%d' y1='%.1f' x2='%d' y2='%.1f' stroke='#d8ded9' stroke-width='1'/>"
                   % (left, y, left + pw, y))
        out.append(text(left - 8, y + 4, yfmt(v), 11, "end", fill="#5b6862"))
    gw = pw / max(len(groups), 1)
    bw = min(48.0, gw * 0.8 / max(len(series), 1))
    for gi, (label, values) in enumerate(groups):
        gx = left + gw * gi + gw / 2
        total = bw * len(series)
        for li, part in enumerate(label.split("\n")):
            out.append(text(gx, top + ph + 18 + 14 * li, part, 11))
        for si, v in enumerate(values):
            if v is None:
                continue
            value, vlabel = v
            h = ph * min(value, ymax) / ymax
            x = gx - total / 2 + bw * si
            out.append("<rect x='%.1f' y='%.1f' width='%.1f' height='%.1f' fill='%s'/>"
                       % (x + 2, top + ph - h, bw - 4, h, COLORS[si % len(COLORS)]))
            out.append(text(x + bw / 2, top + ph - h - 5, vlabel, 10))
    lx = left
    for si, name in enumerate(series):
        out.append("<rect x='%d' y='%d' width='12' height='12' fill='%s'/>"
                   % (lx, height - 20, COLORS[si % len(COLORS)]))
        out.append(text(lx + 18, height - 10, name, 11, "start"))
        lx += 30 + 7 * len(name)
    out.append("</svg>")
    return "\n".join(out) + "\n"


def agreement_plot(d):
    groups = []
    for tname, tpre in TARGETS:
        for sname, spre in SUITES:
            s = read_one(os.path.join(d, spre + tpre + "agreement_summary.csv"))
            if s is None:
                continue
            n = int(s["loops_both"])
            vals = [(100.0 * int(s["agree"]) / n, "%s / %d" % (s["agree"], n))]
            if s.get("all_reasons_covered"):
                c = int(s["all_reasons_covered"])
                vals.append((100.0 * c / n, "%d / %d" % (c, n)))
            else:
                vals.append(None)
            groups.append(("%s\n%s" % (tname, sname), vals))
    if not groups:
        return None
    return bar_chart("Agreement with LoopVectorize",
                     "loops where LoopLens matches LoopVectorize / loops matched (clang-20 -O3 -g); source: results/*agreement_summary.csv",
                     groups, ["primary reason", "all reasons covered"], 100.0, lambda v: "%d%%" % v)


def tsvc_plot(d):
    before = read_one(os.path.join(d, "tsvc_agreement_summary_before.csv"))
    after = read_one(os.path.join(d, "tsvc_agreement_summary.csv"))
    if before is None or after is None:
        return None
    groups = []
    for label, s in (("first run\n(untuned)", before), ("current", after)):
        n = int(s["loops_both"])
        groups.append((label, [(100.0 * int(s["agree"]) / n, "%s / %d" % (s["agree"], n)), None]))
    return bar_chart("TSVC (generic x86-64): first untuned run vs current",
                     "agree / loops matched; the first run matched fewer loops (results/tsvc_disagreements.md)",
                     groups, ["primary reason"], 100.0, lambda v: "%d%%" % v, width=640)


def speedup_plot(d):
    path = os.path.join(d, "timing.csv")
    if not os.path.exists(path):
        return None
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    med = {(r["kernel"], r["config"], r["variant"]): float(r["median_s"]) for r in rows}
    groups, top = [], 1.0
    for (k, c, v) in sorted(med):
        if v != "base" or (k, c, "repair") not in med or med[(k, c, "repair")] <= 0:
            continue
        sp = med[(k, c, "base")] / med[(k, c, "repair")]
        top = max(top, sp)
        groups.append(("%s\n%s" % (k, c), [(sp, "%.2fx" % sp)]))
    if not groups:
        return None
    cpu = sorted({r["cpu_model"] for r in rows})
    gov = sorted({r["governor"] for r in rows})
    ds = sorted({r["dataset"] for r in rows})
    sub = ("median(base) / median(repair), equal flags; %s; governor %s; dataset %s; source: results/timing.csv"
           % (", ".join(cpu), ", ".join(gov), ", ".join(ds)))
    ymax = float(int(top * 2 + 1)) / 2 + 0.5
    return bar_chart("Repair speedup per kernel and configuration", sub, groups,
                     ["speedup (1.00x = no change)"], ymax, lambda v: "%.1fx" % v,
                     width=max(900, 70 * len(groups) + 80))


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
    plots = {"agreement.svg": agreement_plot(d), "tsvc_before_after.svg": tsvc_plot(d),
             "speedup.svg": speedup_plot(d)}
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
