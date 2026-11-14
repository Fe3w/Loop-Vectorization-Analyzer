// PolyBench gesummv.c:87 shape: two accumulators (tmp[i] and y[i]) in one loop, i.e.
// two stores to loop-invariant addresses. looplens-repair handles exactly one, so it
// does not apply; LoopVectorize keeps its UnsafeDep.
// RUN: %looplens_clang -O3 -ffast-math -g -mllvm -looplens-repair \
// RUN:   -Rpass='looplens-repair' -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --implicit-check-not='versioned loop' %s
void gesummv(int n, double A[n][n], double B[n][n], double *tmp, double *x, double *y) {
  for (int i = 0; i < n; i++) {
    tmp[i] = 0.0;
    y[i] = 0.0;
    for (int j = 0; j < n; j++) {
      tmp[i] = A[i][j] * x[j] + tmp[i];
      y[i] = B[i][j] * x[j] + y[i];
    }
  }
}
// CHECK-DAG: limit-gesummv.c:11:5: remark: Category: loop-carried-dependence; Rule: mem-unsafe-dep;
// CHECK-DAG: remark: loop not vectorized: unsafe dependent memory operations in loop
