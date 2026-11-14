// At -O0 LoopVectorize never runs. LLVM 20 still invokes the VectorizerStart
// extension point in its -O0 pipeline, so LoopLens skips OptimizationLevel::O0
// itself (without that it reported this loop on unoptimised alloca code).
// RUN: %looplens_clang -O0 -g -Rpass-analysis=looplens -c %s -o /dev/null 2>&1 \
// RUN:   | FileCheck --allow-empty %s

void f(float *a, int n) {
  for (int i = 0; i < n; i++)
    a[i] = 0;
}
// CHECK-NOT: remark:
