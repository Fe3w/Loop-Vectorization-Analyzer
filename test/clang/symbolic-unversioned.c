// A symbolic stride LoopAccessAnalysis does not version (the stride s*t is a
// product, not one runtime value it could test for 1): no versioned=yes, so it is
// a strided gather; LoopVectorize rejects it on cost. (Coverage test, issue 9.)
// RUN: %looplens_clang -O3 -g -mllvm -looplens-text=true -Rpass-analysis=looplens \
// RUN:   -Rpass-analysis=loop-vectorize -c %s -o /dev/null 2>&1 | FileCheck %s
void f(float *restrict a, const float *restrict b, long s, long t, int n) {
  for (int i = 0; i < n; i++)
    a[i] = b[i * s * t];
}
// CHECK: access load ptr={{%[0-9]+}} kind=symbolic stride=[(4 * {{%[0-9]+}} * {{%[0-9]+}})]{{$}}
// CHECK: blocker primary=stride rule=stride-gather secondary=none
