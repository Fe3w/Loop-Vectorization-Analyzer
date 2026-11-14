// PolyBench nussinov.c:102 shape. The repair applies, but one read walks a row and
// the other a column of the table; LoopVectorize's cost model rejects the fast copy.
// LoopLens has no cost rule for a mix of unit and strided reads, so it reports no
// blocker for the fast copy (a documented gap, docs/repair-limits.md).
// RUN: %looplens_clang -O3 -ffast-math -g -mllvm -looplens-repair \
// RUN:   -Rpass='looplens-repair' -Rpass-missed=loop-vectorize -Rpass-analysis=looplens \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s
#define N 2500
static inline int max_score(int a, int b) { return a >= b ? a : b; }
void nussinov(int table[N][N]) {
  for (int i = N - 1; i >= 0; i--)
    for (int j = i + 1; j < N; j++)
      for (int k = i + 1; k < j; k++)
        table[i][j] = max_score(table[i][j], table[i][k] + table[k + 1][j]);
}
// CHECK-DAG: limit-nussinov.c:13:7: remark: versioned loop and promoted the loop-invariant store to a register
// CHECK-DAG: limit-nussinov.c:13:7: remark: the cost-model indicates that vectorization is not beneficial
// CHECK-DAG: limit-nussinov.c:13:7: remark: Category: none; Rule: none; Secondary: none
