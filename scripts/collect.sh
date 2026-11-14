#!/usr/bin/env bash
# Compile every PolyBench kernel with clang -O3 -g and the LoopLens plugin;
# keep LLVM's optimization record (LoopVectorize + LoopLens remarks) and
# LoopLens's JSON Lines per kernel.
#
# Usage: scripts/collect.sh --bench <polybench root> [--out results/raw]
#          [--plugin build/lib/LoopLens.so] [--summary results/collect_summary.csv]
#          [--kernels "name1 name2"] [--list <file>] [--cflags "<flags>"]
#
# --list: compile the sources named in <file> (paths relative to --bench, one
# per line) instead of <bench>/utilities/benchmark_list (e.g. TSVC).
# --cflags: extra clang flags, e.g. "-march=x86-64-v4" or
# "--target=aarch64-linux-gnu --sysroot=<dir>" (recorded in toolchain.txt).
#
# Outputs in --out: <kernel>.opt.yaml, <kernel>.jsonl, manifest.csv,
# toolchain.txt. Kernel sources are only passed to clang as paths (the bench
# tree is downloaded data). Exits non-zero if any kernel fails to compile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH=""; OUT="$ROOT/results/raw"; PLUGIN="$ROOT/build/lib/LoopLens.so"
SUMMARY=""; ONLY=""; LIST=""; CFLAGS_EXTRA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --plugin) PLUGIN="$2"; shift 2 ;;
    --summary) SUMMARY="$2"; shift 2 ;;
    --kernels) ONLY="$2"; shift 2 ;;
    --list) LIST="$2"; shift 2 ;;
    --cflags) CFLAGS_EXTRA="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BENCH" ] || { echo "error: --bench is required" >&2; exit 2; }
BENCH="$(cd "$BENCH" && pwd)"
[ -n "$LIST" ] || LIST="$BENCH/utilities/benchmark_list"
[ -f "$LIST" ] || { echo "error: $LIST not found" >&2; exit 2; }
[ -f "$PLUGIN" ] || { echo "error: plugin $PLUGIN not found (build first)" >&2; exit 2; }
PLUGIN="$(cd "$(dirname "$PLUGIN")" && pwd)/$(basename "$PLUGIN")"
CLANG="${CLANG:-clang-20}"
FLAGS=(-O3 -g)
# shellcheck disable=SC2206
[ -n "$CFLAGS_EXTRA" ] && FLAGS+=($CFLAGS_EXTRA)
mkdir -p "$OUT"

{
  "$CLANG" --version | head -1
  "${OPT:-opt-20}" --version | grep -i 'llvm version' | head -1
  echo "extra flags: ${CFLAGS_EXTRA:-none}"
  echo "flags: ${FLAGS[*]} -I <bench>/utilities -I <kernel dir> -fsave-optimization-record"
  echo "plugin: -fpass-plugin=LoopLens.so -Xclang -load -Xclang LoopLens.so -mllvm -looplens-text=false"
  echo "host-cpu: $(llc-20 --version 2>/dev/null | sed -n 's/.*Host CPU: //p')"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/toolchain.txt"

echo "kernel,path,exit,seconds,jsonl_lines,yaml_bytes" > "$OUT/manifest.csv"
failed=0
while IFS= read -r rel || [ -n "$rel" ]; do
  rel="${rel#./}"; [ -z "$rel" ] && continue
  k="$(basename "$rel" .c)"
  if [ -n "$ONLY" ] && [[ " $ONLY " != *" $k "* ]]; then continue; fi
  src="$BENCH/$rel"
  : > "$OUT/$k.jsonl"   # the plugin truncates on first write; empty if no loops
  start=$(date +%s.%N)
  set +e
  "$CLANG" "${FLAGS[@]}" -I "$BENCH/utilities" -I "$(dirname "$src")" \
    -fpass-plugin="$PLUGIN" -Xclang -load -Xclang "$PLUGIN" \
    -mllvm -looplens-text=false -mllvm -looplens-json="$OUT/$k.jsonl" \
    -fsave-optimization-record -foptimization-record-file="$OUT/$k.opt.yaml" \
    -c "$src" -o /dev/null 2> "$OUT/$k.stderr"
  rc=$?
  set -e
  secs=$(echo "$(date +%s.%N) - $start" | bc)
  [ "$rc" = 0 ] || { failed=$((failed + 1)); echo "FAILED: $k (see $OUT/$k.stderr)" >&2; }
  lines=$(wc -l < "$OUT/$k.jsonl"); bytes=$(stat -c %s "$OUT/$k.opt.yaml" 2>/dev/null || echo 0)
  printf '%s,%s,%s,%.2f,%s,%s\n' "$k" "$rel" "$rc" "$secs" "$lines" "$bytes" >> "$OUT/manifest.csv"
done < "$LIST"

if [ -n "$SUMMARY" ]; then
  echo "kernel,looplens_innermost,lv_vectorized,lv_missed" > "$SUMMARY"
  tail -n +2 "$OUT/manifest.csv" | while IFS=, read -r k _; do
    inner=$(grep -c '"innermost":true' "$OUT/$k.jsonl" || true)
    # Per-loop LoopVectorize remarks: Name follows the Pass line.
    read -r vec miss < <(awk '/^Pass: *loop-vectorize/{lv=1; next}
        lv && /^Name:/{ if ($2=="Vectorized") v++; else if ($2=="MissedDetails") m++; lv=0 }
        END{print v+0, m+0}' "$OUT/$k.opt.yaml")
    echo "$k,$inner,$vec,$miss" >> "$SUMMARY"
  done
  # Committed next to the summary: which toolchain produced it.
  cp "$OUT/toolchain.txt" "${SUMMARY%.csv}_toolchain.txt"
fi
echo "compiled $(($(wc -l < "$OUT/manifest.csv") - 1)) kernel(s), $failed failed; outputs in $OUT"
[ "$failed" = 0 ]
