// Loop pragmas LoopVectorize honours (issue 6).
// RUN: %looplens_clang -O3 -g -Rpass-analysis=looplens -Rpass=loop-vectorize \
// RUN:   -Rpass-missed=loop-vectorize -c %s -o /dev/null 2>&1 | FileCheck %s

// vectorize(disable) is lowered to vectorize_width(1): LoopVectorize keeps the
// loop scalar (reported as "not beneficial"); LoopLens names the pragma.
void dis(float *restrict a, const float *restrict b, int n) {
#pragma clang loop vectorize(disable)
  for (int i = 0; i < n; i++)
    a[i] = b[i] + 1.0f;
}
// CHECK-DAG: hints.c:9:3: remark: Category: hint; Rule: hint-vectorize-disabled;

// vectorize(assume_safety) forces vectorization: the cost model is not consulted,
// so a gather is not a blocker (and LAA treats the accesses as parallel).
void par(float *a, int *idx, int n) {
#pragma clang loop vectorize(assume_safety)
  for (int i = 0; i < n; i++)
    a[idx[i]] += 1.0f;
}
// CHECK-DAG: hints.c:18:3: remark: Category: none; Rule: none; Secondary: none
// CHECK-DAG: hints.c:18:3: remark: vectorized loop
