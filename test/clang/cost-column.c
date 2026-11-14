// Column walk: every access in the inner loop has a constant stride of 256
// elements. Without a legal gather (generic x86-64, AArch64 NEON) the accesses
// are scalarised and LoopVectorize's cost model rejects the loop; LoopLens reports
// rule cost-strided (category stride). With AVX-512 gathers it vectorizes.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' -Rpass-missed=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=GEN %s
// RUN: %looplens_clang -O3 -g -march=x86-64-v4 -Rpass-analysis=looplens -Rpass=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=V4 %s

float A[256][256], B[256][256];
void col(int j) {
  for (int i = 0; i < 256; i++)
    A[i][j] = A[i][j] * B[i][j];
}
// GEN-DAG: cost-column.c:12:3: remark: Category: stride; Rule: cost-strided;
// GEN-DAG: remark: the cost-model indicates that vectorization is not beneficial
// V4-DAG: cost-column.c:12:3: remark: Category: none; Rule: none
// V4-DAG: cost-column.c:12:3: remark: vectorized loop
