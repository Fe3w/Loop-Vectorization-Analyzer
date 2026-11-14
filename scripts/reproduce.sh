#!/usr/bin/env bash
# Rebuild LoopLens and regenerate every committed number from scratch:
# build + tests, PolyBench/C 4.2.1 and TSVC_2 (checksum-verified downloads),
# remark collection, agreement tables, codegen checks, README results table.
#
# Usage: scripts/reproduce.sh [--dry-run]
# Needs: clang-20/opt-20 (LLVM 20), cmake, ninja, python3 + PyYAML, network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
S="$ROOT/scripts"; R="$ROOT/results"
PB="$ROOT/bench/polybench/polybench-c-4.2.1-beta"; TS="$ROOT/bench/tsvc"

run() {
  echo "step: $*"
  [ "$DRY" = 1 ] || "$@"
}

start=$(date +%s)
run cmake -S "$ROOT" -B "$ROOT/build" -G Ninja
run cmake --build "$ROOT/build"
run cmake --build "$ROOT/build" --target check
run "$S/fetch_polybench.sh"
run "$S/collect.sh" --bench "$PB" --out "$R/raw" --summary "$R/collect_summary.csv"
run python3 "$S/agreement.py" --raw "$R/raw" --out "$R"
run python3 "$S/gcc_compare.py" --agreement "$R/agreement.csv" --suite polybench --include "$PB/utilities" --out "$R/gcc_compare_polybench.csv" --summary "$R/gcc_compare_polybench_summary.csv"
run "$S/codegen_unchanged.sh" --bench "$PB" --out "$R/codegen_check.txt"
run "$S/fetch_tsvc.sh"
run "$S/collect.sh" --bench "$TS" --list "$TS/benchmark_list" --out "$R/raw-tsvc" --summary "$R/tsvc_collect_summary.csv"
run python3 "$S/agreement.py" --raw "$R/raw-tsvc" --out "$R" --prefix tsvc_
run "$S/codegen_unchanged.sh" --bench "$TS" --list "$TS/benchmark_list" --out "$R/tsvc_codegen_check.txt"
run python3 "$S/interchange_oracle.py" --raw "$R/raw-tsvc" --src "$TS/tsvc.c" --cflags "-I $TS" --out "$R/interchange_tsvc.csv"
run python3 "$S/gcc_compare.py" --agreement "$R/tsvc_agreement.csv" --suite tsvc --include "$TS" --out "$R/gcc_compare_tsvc.csv" --summary "$R/gcc_compare_tsvc_summary.csv"
# Other targets (compile-only; AArch64 headers from Ubuntu's cross libc).
SR="$ROOT/bench/sysroot-aarch64/root/usr/aarch64-linux-gnu"
run "$S/fetch_aarch64_sysroot.sh"
for cfg in "x86v4|-march=x86-64-v4" "aarch64|--target=aarch64-linux-gnu --sysroot=$SR"; do
  n="${cfg%%|*}"; f="${cfg#*|}"
  run "$S/collect.sh" --bench "$PB" --out "$R/raw-$n" --cflags "$f" --summary "$R/${n}_collect_summary.csv"
  run python3 "$S/agreement.py" --raw "$R/raw-$n" --out "$R" --prefix "${n}_"
  run "$S/collect.sh" --bench "$TS" --list "$TS/benchmark_list" --out "$R/raw-tsvc-$n" --cflags "$f" --summary "$R/tsvc_${n}_collect_summary.csv"
  run python3 "$S/agreement.py" --raw "$R/raw-tsvc-$n" --out "$R" --prefix "tsvc_${n}_"
done
run "$S/differential.sh" --bench "$PB"
run "$S/verify_fixes.sh"
run python3 "$S/fix_mca.py"
run python3 "$S/plots.py" "$R"
run python3 "$S/results_table.py" "$R" --update-readme "$ROOT/README.md"
[ "$DRY" = 1 ] || echo "done in $(( $(date +%s) - start )) s; review 'git diff results/ README.md'"
