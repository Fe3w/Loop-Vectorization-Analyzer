// Strict float sum: LoopVectorize refuses to reorder the fadds; LoopLens names the
// same reason on the same loop.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -Rpass-missed=loop-vectorize -c %s -o /dev/null 2>&1 | FileCheck %s

float fsum(float *a, int n) {
  float s = 0;
  for (int i = 0; i < n; i++)
    s += a[i];
  return s;
}
// CHECK-DAG: fp-sum.c:8:3: remark: Category: reduction; Rule: red-exact-fp;
// CHECK-DAG: fp-sum.c:8:3: remark: loop not vectorized [-Rpass-missed=loop-vectorize]
// CHECK-DAG: remark: loop not vectorized: cannot prove it is safe to reorder floating-point operations
