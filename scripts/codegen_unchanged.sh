#!/usr/bin/env bash
# Check that loading LoopLens into clang does not change generated code: compile
# every PolyBench kernel to assembly with and without the plugin (-O3 -g0) and
# compare. LoopLens is an analysis, but at the VectorizerStart extension point
# it runs LoopSimplify + LCSSA in front of itself (-looplens-canonicalize).
#
# Usage: scripts/codegen_unchanged.sh --bench <root> [--list <file>] [--out results/codegen_check.txt]
#   --list: sources relative to --bench (default <bench>/utilities/benchmark_list)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST=""; BENCH=""; OUT="$ROOT/results/codegen_check.txt"; PLUGIN="$ROOT/build/lib/LoopLens.so"
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --list) LIST="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BENCH" ] || { echo "error: --bench is required" >&2; exit 2; }
BENCH="$(cd "$BENCH" && pwd)"
[ -n "$LIST" ] || LIST="$BENCH/utilities/benchmark_list"
CLANG="${CLANG:-clang-20}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
same=0; diff=0; list=""
while IFS= read -r rel || [ -n "$rel" ]; do
  rel="${rel#./}"; [ -z "$rel" ] && continue
  k="$(basename "$rel" .c)"; src="$BENCH/$rel"
  inc=(-I "$BENCH/utilities" -I "$(dirname "$src")")
  "$CLANG" -O3 -g0 "${inc[@]}" -S "$src" -o "$TMP/$k.base.s"
  "$CLANG" -O3 -g0 "${inc[@]}" -fpass-plugin="$PLUGIN" -Xclang -load -Xclang "$PLUGIN" \
    -mllvm -looplens-text=false -S "$src" -o "$TMP/$k.ll.s"
  if cmp -s "$TMP/$k.base.s" "$TMP/$k.ll.s"; then same=$((same + 1)); else diff=$((diff + 1)); list="$list $k"; fi
done < "$LIST"
{
  echo "codegen check: clang -O3 -g0 -S, with vs without the LoopLens plugin"
  "$CLANG" --version | head -1
  echo "kernels identical: $same"
  echo "kernels different: $diff${list:+ ($list )}"
} | tee "$OUT"
[ "$diff" = 0 ]
