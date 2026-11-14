// -mllvm -looplens-repair runs the repair inside clang's pipeline: with -ffast-math
// the cholesky accumulation loop is vectorized, which plain -O3 -ffast-math cannot.
// RUN: %looplens_clang -O3 -ffast-math -mllvm -looplens-repair -Rpass='loop-vectorize|looplens-repair' \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=ON %s
// RUN: %looplens_clang -O3 -ffast-math -Rpass=loop-vectorize -Rpass-missed=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=OFF %s

void chol(int n, double A[n][n]) {
  for (int i = 0; i < n; i++)
    for (int j = 0; j < i; j++)
      for (int k = 0; k < j; k++)
        A[i][j] -= A[i][k] * A[j][k];
}
// ON-DAG: repair.c:11:7: remark: versioned loop and promoted the loop-invariant store to a register
// ON-DAG: repair.c:11:7: remark: vectorized loop
// OFF: repair.c:11:7: remark: loop not vectorized
// OFF-NOT: vectorized loop
