#!/usr/bin/env bash
# Check LoopLens's suggested fixes against LLVM 20: for each example directory
# (bench/fixes/<name>/ with before.c, optional before.flags (used for both
# compiles), after.c and after.flags), record
# the rule LoopLens reports on before.c, whether LoopVectorize vectorizes
# before.c, and whether it vectorizes after.c (the fix applied).
#
# Usage: scripts/verify_fixes.sh [--examples bench/fixes] [--plugin build/lib/LoopLens.so]
#          [--out results/fix_verification.csv] [--cflags "<flags>"]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EX="$ROOT/bench/fixes"; PLUGIN="$ROOT/build/lib/LoopLens.so"
OUT="$ROOT/results/fix_verification.csv"; EXTRA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --examples) EX="$2"; shift 2 ;;
    --plugin) PLUGIN="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --cflags) EXTRA="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
CLANG="${CLANG:-clang-20}"
# shellcheck disable=SC2206
X=($EXTRA)
vectorized() { # file [flags...]: "yes" if LoopVectorize vectorized a loop
  local f="$1" out; shift
  # Capture first: with pipefail, `| grep -q` can SIGPIPE clang and report a
  # failed pipeline although the remark was printed.
  out=$("$CLANG" -O3 "${X[@]}" "$@" -Rpass=loop-vectorize -c "$f" -o /dev/null 2>&1 || true)
  if grep -q "remark: vectorized loop" <<< "$out"; then echo yes; else echo no; fi
}
echo "example,looplens_rule_before,lv_vectorized_before,fix_flags,lv_vectorized_after,fix_verified" > "$OUT"
for d in "$EX"/*/; do
  n="$(basename "$d")"
  bf=""; [ -f "$d/before.flags" ] && bf="$(cat "$d/before.flags")"
  # shellcheck disable=SC2206
  B=($bf)
  rule=$("$CLANG" -O3 "${X[@]}" "${B[@]}" -fpass-plugin="$PLUGIN" -Xclang -load -Xclang "$PLUGIN" \
           -mllvm -looplens-text=false -Rpass-analysis=looplens -c "$d/before.c" -o /dev/null 2>&1 \
         | sed -n 's/.*Rule: \([a-z-]*\);.*/\1/p' | head -1)
  vb=$(vectorized "$d/before.c" "${B[@]}")
  if [ -f "$d/after.c" ]; then
    flags=""; [ -f "$d/after.flags" ] && flags="$(cat "$d/after.flags")"
    # shellcheck disable=SC2086
    va=$(vectorized "$d/after.c" "${B[@]}" $flags)
    ok=no; [ "$vb" = no ] && [ "$va" = yes ] && ok=yes
  else
    flags=""; va="n/a"; ok="no automatic fix"
  fi
  echo "$n,${rule:-none},$vb,${bf:+$bf }$flags,$va,$ok" >> "$OUT"
done
cat "$OUT"
