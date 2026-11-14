#!/usr/bin/env bash
# Time original vs repaired builds of the PolyBench kernels looplens-repair
# transforms. Baseline and repaired builds always share their flags (fairness
# rule): a repair speedup is never measured against a baseline without the
# flags the repaired build had.
#
#   config          flags                              shows
#   O3              -O3                                strict FP: what the repair alone gains or costs
#   O3-fast         -O3 -ffast-math                    the speedup that belongs to the repair
#   O3-native       -O3 -march=native                  as above, for this machine's vector ISA
#   O3-fast-native  -O3 -ffast-math -march=native
#
# Each build: --warmup unrecorded runs, then --runs timed runs pinned with
# taskset; the time is PolyBench's own (-DPOLYBENCH_TIME prints seconds). One
# CSV row per kernel x config x variant (base | repair) with median, min, max and
# quartiles, CPU model, governor, pinned CPU, compiler versions and date.
# Speedups are not stored: the plot script computes them from these rows.
#
# Usage: bench/timing/time.sh --bench <polybench root> [--runs 10] [--warmup 1]
#          [--dataset LARGE] [--cpu 2] [--out results/timing.csv] [--kernels "a b"]
#          [--plugin build/lib/LoopLens.so] [--smoke] [--allow-cloud]
#
# --smoke: 2 runs, no warm-up, MINI dataset; checks the pipeline and CSV format
#   only. Smoke output may not be written under results/.
# A real run is refused in a Claude Code cloud session (noisy shared machines)
#   unless --allow-cloud is given; cloud timings must never be committed.
# AArch64 is not timed: there is no AArch64 hardware in this project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH=""; RUNS=10; WARMUP=1; DATASET=LARGE; CPU=2; OUT="$ROOT/results/timing.csv"
KERNELS=""; PLUGIN="$ROOT/build/lib/LoopLens.so"; SMOKE=0; ALLOW_CLOUD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    --dataset) DATASET="$2"; shift 2 ;;
    --cpu) CPU="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --kernels) KERNELS="$2"; shift 2 ;;
    --plugin) PLUGIN="$2"; shift 2 ;;
    --smoke) SMOKE=1; shift ;;
    --allow-cloud) ALLOW_CLOUD=1; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$BENCH" ] || { echo "error: --bench is required" >&2; exit 2; }
BENCH="$(cd "$BENCH" && pwd)"
OUT_ABS="$(realpath -m "$OUT")"
if [ "$SMOKE" = 1 ]; then
  RUNS=2; WARMUP=0; DATASET=MINI
  case "$OUT_ABS" in
    "$ROOT"/results/*) echo "error: smoke timings must not be written under results/ (use --out <other path>)" >&2; exit 2 ;;
  esac
elif [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && [ "$ALLOW_CLOUD" = 0 ]; then
  echo "error: refusing a real timing run in a cloud session (shared, noisy machines); run it on the laptop, or pass --allow-cloud and do not commit the result" >&2
  exit 2
fi
[ -f "$PLUGIN" ] || { echo "error: plugin $PLUGIN not found (build first)" >&2; exit 2; }
PLUGIN="$(realpath "$PLUGIN")"
CLANG="${CLANG:-clang-20}"

# Kernels: those the repair transforms (results/repair_differential.csv), unless given.
if [ -z "$KERNELS" ]; then
  D="$ROOT/results/repair_differential.csv"
  [ -f "$D" ] || { echo "error: $D not found; run scripts/differential.sh or pass --kernels" >&2; exit 2; }
  KERNELS="$(awk -F, 'NR>1 && $3>0 {print $1}' "$D" | sort -u | tr '\n' ' ')"
fi

cpu_model="$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1 | tr ',' ' ')"
gov_file="/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor"
governor="unknown"; [ -r "$gov_file" ] && governor="$(cat "$gov_file")"
PIN=(); pinned="none"
if command -v taskset >/dev/null 2>&1 && taskset -c "$CPU" true 2>/dev/null; then
  PIN=(taskset -c "$CPU"); pinned="$CPU"
else
  echo "warning: cannot pin to CPU $CPU with taskset; running unpinned" >&2
fi
clang_v="$("$CLANG" --version | head -1 | tr ',' ' ')"
opt_v="$("${OPT:-opt-20}" --version | grep -i 'llvm version' | head -1 | sed 's/^ *//' | tr ',' ' ')"
date_s="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$governor" = performance ] || [ "$SMOKE" = 1 ] || \
  echo "warning: CPU governor is '$governor', not 'performance'; timings will be noisier" >&2

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT_ABS")"
echo "kernel,dataset,config,variant,flags,runs,median_s,min_s,max_s,q1_s,q3_s,cpu_model,governor,pinned_cpu,clang,opt,date" > "$OUT_ABS"

stats() { # times on stdin -> "median,min,max,q1,q3"
  python3 -I -c '
import sys, statistics
t = sorted(float(x) for x in sys.stdin.read().split())
q = statistics.quantiles(t, n=4, method="inclusive") if len(t) > 1 else [t[0]] * 3
print("%.6f,%.6f,%.6f,%.6f,%.6f" % (statistics.median(t), t[0], t[-1], q[0], q[2]))'
}

for k in $KERNELS; do
  rel="$(sed 's|^\./||' "$BENCH/utilities/benchmark_list" | grep -E "(^|/)$k\.c$" | head -1)"
  [ -n "$rel" ] || { echo "error: kernel $k not in $BENCH/utilities/benchmark_list" >&2; exit 2; }
  src="$BENCH/$rel"
  for cfg in "O3|-O3" "O3-fast|-O3 -ffast-math" "O3-native|-O3 -march=native" "O3-fast-native|-O3 -ffast-math -march=native"; do
    name="${cfg%%|*}"; flags="${cfg#*|}"
    for variant in base repair; do
      extra=()
      [ "$variant" = repair ] && extra=(-fpass-plugin="$PLUGIN" -Xclang -load -Xclang "$PLUGIN"
                                        -mllvm -looplens-text=false -mllvm -looplens-repair)
      exe="$TMP/$k.$name.$variant"
      # shellcheck disable=SC2086
      "$CLANG" $flags -DPOLYBENCH_TIME -D"${DATASET}"_DATASET -I "$BENCH/utilities" -I "$(dirname "$src")" \
        "${extra[@]}" "$src" "$BENCH/utilities/polybench.c" -lm -o "$exe"
      for _ in $(seq 1 "$WARMUP"); do "${PIN[@]}" "$exe" > /dev/null; done
      : > "$TMP/times"
      for _ in $(seq 1 "$RUNS"); do "${PIN[@]}" "$exe" | tail -1 >> "$TMP/times"; done
      echo "$k,$DATASET,$name,$variant,$flags,$RUNS,$(stats < "$TMP/times"),$cpu_model,$governor,$pinned,$clang_v,$opt_v,$date_s" >> "$OUT_ABS"
    done
  done
done
echo "timing: $(($(wc -l < "$OUT_ABS") - 1)) rows in $OUT_ABS (dataset $DATASET, $RUNS runs, governor $governor, pinned CPU $pinned)"
