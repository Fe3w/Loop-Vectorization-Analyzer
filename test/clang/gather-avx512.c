// A gather is a cost problem only where the target has no (cheap) gather: on
// generic x86-64 LoopVectorize rejects b[idx[i]] as not beneficial; with AVX-512
// (x86-64-v4) gathers are legal and it vectorizes. LoopLens asks TTI
// (isLegalMaskedGather) before reporting stride-gather.
// RUN: %looplens_clang -O3 -g -march=x86-64-v4 -Rpass-analysis=looplens -Rpass=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=V4 %s
// RUN: %looplens_clang -O3 -g -Rpass-analysis=looplens -Rpass-missed=loop-vectorize \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck --check-prefix=GEN %s

void gather(float *restrict a, const float *restrict b, const int *restrict idx, int n) {
  for (int i = 0; i < n; i++)
    a[i] = b[idx[i]];
}
// V4-DAG: gather-avx512.c:11:3: remark: Category: none; Rule: none; Secondary: none
// V4-DAG: gather-avx512.c:11:3: remark: vectorized loop
// GEN: gather-avx512.c:11:3: remark: Category: stride; Rule: stride-gather;
