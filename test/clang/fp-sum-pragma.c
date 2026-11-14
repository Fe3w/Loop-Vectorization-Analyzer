// With #pragma clang loop vectorize(enable) LoopVectorize may reorder the FP sum
// (LoopVectorizeHints::allowReordering) and vectorizes it. LoopLens reads the
// llvm.loop.vectorize.enable hint and does not report red-exact-fp.
// RUN: %looplens_clang -O3 -g -Rpass-analysis=looplens -Rpass=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s

float fsum(float *a, int n) {
  float s = 0;
#pragma clang loop vectorize(enable)
  for (int i = 0; i < n; i++)
    s += a[i];
  return s;
}
// CHECK-DAG: fp-sum-pragma.c:10:3: remark: Category: none; Rule: none; Secondary: none
// CHECK-DAG: fp-sum-pragma.c:10:3: remark: vectorized loop
