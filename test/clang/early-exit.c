// Search loop with an early return.
// RUN: %looplens_clang -O3 -g -Rpass-analysis='looplens|loop-vectorize' \
// RUN:   -Rpass-missed=loop-vectorize -c %s -o /dev/null 2>&1 | FileCheck %s

int find(int *a, int n, int k) {
  for (int i = 0; i < n; i++)
    if (a[i] == k)
      return i;
  return -1;
}
// CHECK-DAG: early-exit.c:6:3: remark: Category: control-flow; Rule: cfg-uncountable-early-exit;
// CHECK-DAG: early-exit.c:6:3: remark: loop not vectorized [-Rpass-missed=loop-vectorize]
