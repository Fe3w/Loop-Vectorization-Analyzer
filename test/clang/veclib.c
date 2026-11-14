// Vector math library (-fveclib=libmvec): sinf now has a vector variant
// (vector=tli), but with errno semantics the call may write memory, so
// LoopAccessAnalysis still refuses the loop ("instruction cannot be vectorized").
// With -fno-math-errno it vectorizes through libmvec.
// RUN: %looplens_clang -O3 -g -fveclib=libmvec -mllvm -looplens-text=true -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=ERRNO %s
// RUN: %looplens_clang -O3 -g -fveclib=libmvec -fno-math-errno -Rpass-analysis=looplens -Rpass=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=NOERRNO %s
#include <math.h>

void vsin(float *restrict a, const float *restrict b, int n) {
  for (int i = 0; i < n; i++)
    a[i] = sinf(b[i]);
}
// ERRNO-DAG: call callee=@sinf vector=tli mem=write
// ERRNO-DAG: veclib.c:12:3: remark: Category: call-or-unsafe-memop; Rule: mem-call-writes; Secondary: none; Evidence: call to @sinf has a vector variant (tli) but may write memory; Fix: compile with -fno-math-errno
// ERRNO-DAG: remark: loop not vectorized: instruction cannot be vectorized
// NOERRNO-DAG: veclib.c:12:3: remark: Category: none; Rule: none
// NOERRNO-DAG: veclib.c:12:3: remark: vectorized loop
