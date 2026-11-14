// A math-library call: LoopVectorize gives its -fno-math-errno hint; LoopLens's fix
// says the same.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s
#include <math.h>

void vsin(float *restrict a, float *restrict b, int n) {
  for (int i = 0; i < n; i++)
    a[i] = sinf(b[i]);
}
// CHECK-DAG: sinf.c:8:3: remark: Category: call-or-unsafe-memop; Rule: call-no-vector-form; Secondary: none; Evidence: call to @sinf has no vector form; Fix: compile with -fno-math-errno
// CHECK-DAG: remark: loop not vectorized: library call cannot be vectorized. Try compiling with -fno-math-errno
