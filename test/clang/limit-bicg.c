// PolyBench bicg.c:88 shape: one accumulator (q[i]) plus a second store to a varying
// address (s[j]). looplens-repair handles exactly one store, to a loop-invariant
// address, so it does not apply; LoopVectorize keeps its UnsafeDep.
// RUN: %looplens_clang -O3 -ffast-math -g -mllvm -looplens-repair \
// RUN:   -Rpass='looplens-repair' -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --implicit-check-not='versioned loop' %s
void bicg(int m, int n, double A[n][m], double *s, double *q, double *p, double *r) {
  for (int i = 0; i < n; i++) {
    q[i] = 0.0;
    for (int j = 0; j < m; j++) {
      s[j] = s[j] + r[i] * A[i][j];
      q[i] = q[i] + A[i][j] * p[j];
    }
  }
}
// CHECK-DAG: limit-bicg.c:10:5: remark: Category: loop-carried-dependence; Rule: mem-unsafe-dep;
// CHECK-DAG: remark: loop not vectorized: unsafe dependent memory operations in loop
