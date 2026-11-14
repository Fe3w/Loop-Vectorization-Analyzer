// The README's worked example (keep the two in sync: README.md "Worked example").
// 1. As written, LoopVectorize refuses the loop; LoopLens names the reason and a fix.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -Rpass-missed=loop-vectorize -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=BEFORE %s
// 2. Applying LoopLens's suggested fix (the pragma) makes LoopVectorize vectorize it.
// RUN: %looplens_clang -O3 -g -DAPPLY_FIX -Rpass=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=AFTER %s

float sum(const float *a, int n) {
  float s = 0.0f;
#ifdef APPLY_FIX
#pragma clang loop vectorize(enable)
#endif
  for (int i = 0; i < n; i++)
    s += a[i];
  return s;
}
// BEFORE-DAG: readme-example.c:14:3: remark: loop not vectorized [-Rpass-missed=loop-vectorize]
// BEFORE-DAG: remark: loop not vectorized: cannot prove it is safe to reorder floating-point operations
// BEFORE-DAG: readme-example.c:14:3: remark: Category: reduction; Rule: red-exact-fp; Secondary: none; Evidence: fadd reduction %{{[0-9]+}} needs exact FP order; Fix: allow reassociation: -ffast-math or -fassociative-math, or #pragma clang loop vectorize(enable) [-Rpass-analysis=looplens]
// AFTER: readme-example.c:14:3: remark: vectorized loop
