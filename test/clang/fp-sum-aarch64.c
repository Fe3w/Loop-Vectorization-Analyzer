// The x86 strict-FP verdict does not carry over: on AArch64 LoopVectorize does the
// float sum as an ordered reduction, and LoopLens (asking TTI) agrees.
// RUN: %looplens_clang --target=aarch64-linux-gnu -O3 -g -Rpass-analysis=looplens \
// RUN:   -Rpass=loop-vectorize -c %s -o /dev/null 2>&1 | FileCheck %s

float fsum(float *a, int n) {
  float s = 0;
  for (int i = 0; i < n; i++)
    s += a[i];
  return s;
}
// CHECK-DAG: fp-sum-aarch64.c:8:3: remark: Category: none; Rule: none; Secondary: none
// CHECK-DAG: fp-sum-aarch64.c:8:3: remark: vectorized loop
