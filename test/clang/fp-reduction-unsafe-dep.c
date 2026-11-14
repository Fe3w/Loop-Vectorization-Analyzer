// From PolyBench cholesky.c:93 (S18). The k-loop accumulates into A[i][j], an
// address that may alias the A[i][k] / A[j][k] loads: LoopVectorize's legality
// check fails on the dependence (UnsafeDep) *before* it ever asks whether the FP
// reduction may be reordered (CantReorderFPOps is checked after legality, in
// LoopVectorizePass::processLoop). So the primary is the dependence.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s

void chol(int n, double A[n][n]) {
  for (int i = 0; i < n; i++)
    for (int j = 0; j < i; j++)
      for (int k = 0; k < j; k++)
        A[i][j] -= A[i][k] * A[j][k];
}
// CHECK-DAG: fp-reduction-unsafe-dep.c:12:7: remark: Category: loop-carried-dependence; Rule: mem-unsafe-dep; Secondary: reduction;
// CHECK-DAG: remark: loop not vectorized: unsafe dependent memory operations in loop
