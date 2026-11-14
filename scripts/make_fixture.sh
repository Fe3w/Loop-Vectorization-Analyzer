#!/usr/bin/env bash
# Make a lit-test fixture from C.
#
# Default: the recipe in DECISIONS.md -- canonical loop IR (sroa, loop-simplify,
# LCSSA, rotate), no debug info, attributes / loop metadata / module flags /
# lifetime intrinsics stripped. TBAA is stripped unless --tbaa is given
# (memory and dependence tests need it: LoopAccessAnalysis uses TBAA to tell
# int index loads from float stores).
#
# --o3: the IR exactly as LoopVectorize sees it in `clang -O3` (dumped with
# -print-before=loop-vectorize). SimplifyCFG/InstCombine have already turned
# conditional updates into selects, which decides whether min/max/any-of
# reductions and recurrences are recognised. TBAA and function attributes
# (fast-math attributes matter for FP reductions) are kept.
#
# --g: the default recipe with debug info (-g) and nothing stripped except
# comments: module flags ("Debug Info Version"), loop metadata and TBAA stay,
# so !dbg locations survive opt (remark tests need them).
#
# Extra clang flags: EXTRA_CFLAGS="-ffast-math" scripts/make_fixture.sh ...
#
# Usage: scripts/make_fixture.sh [--tbaa | --o3 | --g] in.c out.ll
set -euo pipefail
MODE=plain
case "${1:-}" in
  --tbaa) MODE=tbaa; shift ;;
  --o3) MODE=o3; shift ;;
  --g) MODE=g; shift ;;
esac
[ $# -eq 2 ] || { sed -n '2,24p' "$0"; exit 2; }
IN="$1"; OUT="$2"
CLANG="${CLANG:-clang-20}"; OPT="${OPT:-opt-20}"
# shellcheck disable=SC2086
read -r -a EXTRA <<< "${EXTRA_CFLAGS:-}"

if [ "$MODE" = o3 ]; then
  RAW="$(mktemp)"; trap 'rm -f "$RAW"' EXIT
  "$CLANG" -O3 -g0 -fno-discard-value-names "${EXTRA[@]}" -S -emit-llvm \
    -mllvm -print-before=loop-vectorize -mllvm -print-module-scope "$IN" -o /dev/null 2> "$RAW"
  # One module dump per function; the first one holds the whole module.
  awk '/^; \*\*\* IR Dump Before/{n++} n==1' "$RAW" | sed -n '/^; ModuleID/,$p' \
    | sed -E 's/, !llvm\.loop ![0-9]+//g' \
    | grep -vE '^!llvm\.(module\.flags|ident)' \
    | "$OPT" -S -o - \
    | grep -vE '^(; |source_filename)' \
    | sed -E 's/[[:space:]]+;.*preds = .*$//; s/define dso_local/define/' \
    | cat -s > "$OUT"
elif [ "$MODE" = g ]; then
  "$CLANG" -O1 -g -fno-discard-value-names "${EXTRA[@]}" -Xclang -disable-llvm-passes -S -emit-llvm "$IN" -o - \
    | "$OPT" -passes='sroa,loop-simplify,lcssa,loop(loop-rotate)' -S -o - \
    | grep -vE '^(; |source_filename)' \
    | sed -E 's/[[:space:]]+;.*preds = .*$//; s/define dso_local/define/' \
    | cat -s > "$OUT"
else
  STRIP_TBAA='s/, !tbaa ![0-9]+//g'
  [ "$MODE" = tbaa ] && STRIP_TBAA='s/^$//'
  "$CLANG" -O1 -g0 -fno-discard-value-names "${EXTRA[@]}" -Xclang -disable-llvm-passes -S -emit-llvm "$IN" -o - \
    | "$OPT" -passes='sroa,loop-simplify,lcssa,loop(loop-rotate)' -S -o - \
    | sed -E -e "$STRIP_TBAA" -e 's/, !llvm\.loop ![0-9]+//g; s/ #[0-9]+ \{/ {/; s/ #[0-9]+$//' \
    | grep -vE '^(!llvm\.(module\.flags|ident)|attributes #)' \
    | grep -v 'llvm\.lifetime' \
    | "$OPT" -S -o - \
    | grep -vE '^(; |source_filename|attributes #)' \
    | sed -E 's/[[:space:]]+;.*preds = .*$//; s/define dso_local/define/' \
    | cat -s > "$OUT"
fi
"$OPT" -passes=verify -disable-output "$OUT"
