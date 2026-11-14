// Positive test without -ffast-math: the pragma allows FP reordering, so after the
// repair the cholesky accumulation vectorizes; without the repair it does not.
// RUN: %looplens_clang -O3 -g -mllvm -looplens-repair -Rpass='loop-vectorize|looplens-repair' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=ON %s
// RUN: %looplens_clang -O3 -g -Rpass=loop-vectorize -Rpass-missed=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=OFF %s

void chol(int n, double A[n][n]) {
  for (int i = 0; i < n; i++)
    for (int j = 0; j < i; j++)
#pragma clang loop vectorize(enable)
      for (int k = 0; k < j; k++)
        A[i][j] -= A[i][k] * A[j][k];
}
// ON-DAG: repair-pragma.c:12:7: remark: versioned loop and promoted the loop-invariant store to a register
// ON-DAG: repair-pragma.c:12:7: remark: vectorized loop
// OFF: repair-pragma.c:12:7: remark: loop not vectorized
// OFF-NOT: vectorized loop
