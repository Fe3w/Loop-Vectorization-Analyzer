// End to end: LoopLens runs inside clang -O3 right before LoopVectorize, and its
// remark lands on the same line:col as LoopVectorize's per-loop remark.
// RUN: %looplens_clang -O3 -g -Rpass-analysis=looplens -Rpass=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s

void saxpy(float *a, float *b, float s, int n) {
  for (int i = 0; i < n; i++)
    a[i] += s * b[i];
}
// CHECK-DAG: saxpy.c:7:3: remark: Category: none; Rule: none; Secondary: none [-Rpass-analysis=looplens]
// CHECK-DAG: saxpy.c:7:3: remark: vectorized loop
