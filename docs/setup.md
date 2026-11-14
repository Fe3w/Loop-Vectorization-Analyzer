# Setup and usage

## Names

The repository is called *Loop-Vectorization-Analyzer*; inside it the project keeps its original
name, **LoopLens**. The plugin builds as `build/lib/LoopLens.so`, the passes are `looplens-analyze`
and `looplens-repair`, options start with `-looplens-`, and remarks use the pass name `looplens`.
The old URL `github.com/Fe3w/looplens` redirects to this repository.

## Requirements

Ubuntu 24.04 with LLVM 20.1.2 from `noble-updates` (the same packages CI installs):

```bash
sudo apt-get install -y -t noble-updates llvm-20 llvm-20-dev llvm-20-tools libpolly-20-dev \
  clang-20 zlib1g-dev libzstd-dev ninja-build cmake python3-yaml
```

## Build and test

```bash
git clone https://github.com/Fe3w/Loop-Vectorization-Analyzer.git
cd Loop-Vectorization-Analyzer
cmake -S . -B build -G Ninja
cmake --build build
cmake --build build --target check     # lit + FileCheck tests
```

## Explain the loops in a file

```bash
P=build/lib/LoopLens.so
clang-20 -O3 -g -fpass-plugin=$P -Xclang -load -Xclang $P -mllvm -looplens-text=false \
  -Rpass-analysis='looplens|loop-vectorize' -Rpass-missed=loop-vectorize \
  -c test/clang/readme-example.c -o /dev/null
```

Expected: LLVM's `loop not vectorized` and, on the same line, the analyzer's
`Category: reduction; Rule: red-exact-fp; … Fix: …`. Replace the file with your own `.c` file to
analyze your loops. Remarks need debug information (`-g`). Only innermost loops are classified.

## Run the repair pass

```bash
clang-20 -O3 -ffast-math -fpass-plugin=$P -Xclang -load -Xclang $P -mllvm -looplens-text=false \
  -mllvm -looplens-repair -Rpass='loop-vectorize|looplens-repair' \
  -c test/clang/repair.c -o /dev/null
```

Expected: `versioned loop and promoted the loop-invariant store to a register`, then
`vectorized loop`.

What it repairs and what it does not: [repair-limits.md](repair-limits.md). Correctness evidence:
[correctness.md](correctness.md).

## Reproduce the results

```bash
scripts/reproduce.sh          # build, test, download (checksummed), collect, score, update README
scripts/reproduce.sh --dry-run
python3 scripts/plots.py      # redraw the figures in results/plots/ from results/
```

The `reproduce` GitHub workflow (manual and weekly) runs the same script and fails if any committed
result changes. Timing (`bench/timing/time.sh`) needs a quiet machine and is not part of it.

## Layout

| Path | Contents |
| --- | --- |
| `lib/` | Pass sources |
| `test/` | lit/FileCheck regression tests |
| `bench/` | PolyBench/C and TSVC harness, timing |
| `results/` | CSVs and figures; the only source of reported numbers |
| `scripts/` | Data collection, scoring, figures |
| `docs/` | Write-up, reference, methodology, correctness |

Options, remarks, the JSON report and the text output: [reference.md](reference.md).
Design decisions: [DECISIONS.md](../DECISIONS.md). Releases: [CHANGELOG.md](../CHANGELOG.md).
