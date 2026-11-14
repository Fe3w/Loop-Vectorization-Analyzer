// PolyBench trmm.c:88 shape. The repair applies (the store to B[i][j] no longer
// conflicts in the fast copy), but both reads walk down a column (constant stride
// m), so LoopVectorize's cost model rejects the fast copy and LoopLens reports
// cost-strided. Versioning + promotion cannot change the access pattern.
// RUN: %looplens_clang -O3 -ffast-math -g -mllvm -looplens-repair \
// RUN:   -Rpass='looplens-repair' -Rpass-missed=loop-vectorize -Rpass-analysis=looplens \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s
#define M 1000
#define N 1200
void trmm(double alpha, double A[M][M], double B[M][N]) {
  for (int i = 0; i < M; i++)
    for (int j = 0; j < N; j++) {
      for (int k = i + 1; k < M; k++)
        B[i][j] += A[k][i] * B[k][j];
      B[i][j] = alpha * B[i][j];
    }
}
// CHECK-DAG: limit-trmm.c:13:7: remark: versioned loop and promoted the loop-invariant store to a register
// CHECK-DAG: limit-trmm.c:13:7: remark: the cost-model indicates that vectorization is not beneficial
// CHECK-DAG: limit-trmm.c:13:7: remark: Category: stride; Rule: cost-strided;
