// From PolyBench ludcmp.c:108 (S18). At the VectorizerStart extension point the
// innermost loop has no preheader yet (LoopVectorizePass simplifies loops itself,
// later), so without canonicalisation LoopLens could not ask InductionDescriptor /
// RecurrenceDescriptor and missed the strict FP reduction. LoopLens adds
// LoopSimplify + LCSSA in front of itself at the extension point.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s

void lu_lower(int n, double A[n][n]) {
  for (int i = 0; i < n; i++)
    for (int j = 0; j < i; j++) {
      double w = A[i][j];
      for (int k = 0; k < j; k++)
        w -= A[i][k] * A[k][j];
      A[i][j] = w / A[j][j];
    }
}
// CHECK-DAG: no-preheader-at-ep.c:13:7: remark: Category: reduction; Rule: red-exact-fp;
// CHECK-DAG: remark: loop not vectorized: cannot prove it is safe to reorder floating-point operations
