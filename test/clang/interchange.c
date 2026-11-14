// Column walk over distinct arrays: LoopLens says interchange with the parent
// loop is legal and names the clang flag; with that flag LLVM's loop-interchange
// swaps the loops and LoopVectorize vectorizes the new inner loop.
// RUN: %looplens_clang -O3 -g -Rpass-analysis=looplens -c %s -o /dev/null 2>&1 \
// RUN:   | FileCheck --check-prefix=LENS %s
// RUN: %looplens_clang -O3 -g -mllvm -enable-loopinterchange -Rpass='loop-interchange|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=LLVM %s
#define N 512
void colsum(double A[restrict N][N], const double B[restrict N][N]) {
  for (int j = 0; j < N; j++)
    for (int i = 0; i < N; i++)
      A[i][j] = A[i][j] + B[i][j];
}
// LENS: interchange.c:11:5: remark: Category: stride; Rule: cost-strided;
// LENS-SAME: Fix: interchange this loop with its parent loop (legal: no dependence has direction (<,>))
// LLVM-DAG: remark: Loop interchanged with enclosing loop.
// LLVM-DAG: remark: vectorized loop
