#!/usr/bin/env bash
# Differential test of looplens-repair on every PolyBench kernel
# (-DPOLYBENCH_DUMP_ARRAYS), with and without -mllvm -looplens-repair:
#   strict: -O3. The repair must not change a single output byte
#           (promotion keeps the FP operation order) -> column "strict".
#   fast:   -O3 -ffast-math, where LoopVectorize may now vectorize the
#           repaired loops; reassociation may change the last digits, so the
#           dumped values are compared against a tolerance fixed in advance:
#           a value is within tolerance if its relative error is <= 1e-6, or
#           its absolute error is <= 0.011 and |value| < 1e4 (PolyBench prints
#           %0.2lf: 0.01 is one unit in the last printed digit).
# Also counts repaired loops and vectorized loops per build.
#
# Usage: scripts/differential.sh --bench <polybench root> [--datasets "SMALL MEDIUM"]
#          [--out results/repair_differential.csv]
#        scripts/differential.sh --compare A.out B.out    (tolerance check of two dumps)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

compare() { # prints "values=N differing=N max_abs=X max_rel=X within_tolerance=yes|no"
  python3 -I -c '
import re, sys
v = [[float(x) for x in re.findall(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?", open(f).read())] for f in sys.argv[1:3]]
if len(v[0]) != len(v[1]):
    print("length-mismatch values=%d/%d within_tolerance=no" % (len(v[0]), len(v[1]))); sys.exit(1)
mabs = mrel = 0.0; diff = 0; ok = True
for a, b in zip(*v):
    d = abs(a - b)
    if d == 0: continue
    diff += 1
    rel = d / max(abs(a), abs(b))
    mabs = max(mabs, d); mrel = max(mrel, rel)
    if not (rel <= 1e-6 or (d <= 0.011 and max(abs(a), abs(b)) < 1e4)):
        ok = False
print("values=%d differing=%d max_abs=%.6g max_rel=%.3g within_tolerance=%s"
      % (len(v[0]), diff, mabs, mrel, "yes" if ok else "no"))
sys.exit(0 if ok else 1)' "$1" "$2"
}

if [ "${1:-}" = "--compare" ]; then
  compare "${2:?first dump}" "${3:?second dump}"
  exit $?
fi

BENCH=""; DATASETS="SMALL MEDIUM"; OUT="$ROOT/results/repair_differential.csv"
PLUGIN="$ROOT/build/lib/LoopLens.so"
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --datasets|--dataset) DATASETS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BENCH" ] || { echo "error: --bench is required" >&2; exit 2; }
BENCH="$(cd "$BENCH" && pwd)"
CLANG="${CLANG:-clang-20}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "kernel,dataset,repaired_loops,strict,fast_vectorized_base,fast_vectorized_repair,fast_values,fast_differing,fast_max_abs_diff,fast_max_rel_err,fast_within_tolerance" > "$OUT"
mismatch=0; outside=0
build() { # mode(strict|fast) variant(base|rep) kernel src dataset
  local f=(-O3); [ "$1" = fast ] && f+=(-ffast-math)
  local p=(); [ "$2" = rep ] && p=(-fpass-plugin="$PLUGIN" -Xclang -load -Xclang "$PLUGIN"
                                  -mllvm -looplens-text=false -mllvm -looplens-repair)
  "$CLANG" "${f[@]}" -DPOLYBENCH_DUMP_ARRAYS -D"$5"_DATASET "${inc[@]}" "${p[@]}" \
    -Rpass='loop-vectorize|looplens-repair' \
    "$4" "$BENCH/utilities/polybench.c" -lm -o "$TMP/$3.$1.$2" 2> "$TMP/$3.$1.$2.rem"
  "$TMP/$3.$1.$2" 2> "$TMP/$3.$1.$2.out" > /dev/null
}
for ds in $DATASETS; do
  while IFS= read -r rel || [ -n "$rel" ]; do
    rel="${rel#./}"; [ -z "$rel" ] && continue
    k="$(basename "$rel" .c)"; src="$BENCH/$rel"
    inc=(-I "$BENCH/utilities" -I "$(dirname "$src")")
    for m in strict fast; do for v in base rep; do build $m $v "$k" "$src" "$ds"; done; done
    rep=$(grep -c "promoted the loop-invariant store" "$TMP/$k.strict.rep.rem" || true)
    if cmp -s "$TMP/$k.strict.base.out" "$TMP/$k.strict.rep.out"; then o=identical; else o=DIFFERENT; mismatch=$((mismatch + 1)); fi
    vb=$(grep -c "remark: vectorized loop" "$TMP/$k.fast.base.rem" || true)
    vr=$(grep -c "remark: vectorized loop" "$TMP/$k.fast.rep.rem" || true)
    c=$(compare "$TMP/$k.fast.base.out" "$TMP/$k.fast.rep.out" || true)
    f() { sed -n "s/.*$1=\([^ ]*\).*/\1/p" <<< "$c"; }
    w=$(f within_tolerance); [ "$w" = yes ] || outside=$((outside + 1))
    echo "$k,$ds,$rep,$o,$vb,$vr,$(f values),$(f differing),$(f max_abs),$(f max_rel),$w" >> "$OUT"
  done < "$BENCH/utilities/benchmark_list"
done
echo "differential ($DATASETS): $mismatch kernel run(s) with different strict-FP output, $outside fast-math run(s) outside tolerance; see $OUT"
[ "$mismatch" = 0 ]
