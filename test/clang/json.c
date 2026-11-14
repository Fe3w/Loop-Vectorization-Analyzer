// JSON Lines from inside clang: file and line of both loops. (The first body is not a
// plain copy: LoopIdiomRecognize would turn a[i] = b[i] into memcpy, leaving no loop.)
// The file name is the DILocation's, i.e. the path as given to clang.
// RUN: %looplens_clang -O3 -g -mllvm -looplens-json=%t.jsonl -c %s -o /dev/null
// RUN: FileCheck %s < %t.jsonl

void two(float *restrict a, float *restrict b, int n) {
  for (int i = 0; i < n; i++)
    a[i] = b[i] + 1;
  for (int i = 0; i < n; i++)
    b[i] = 2 * a[i];
}
// CHECK:      {"function":"two",{{.*}}"file":"{{.*}}json.c","line":8,"col":3,
// CHECK-NEXT: {"function":"two",{{.*}}"file":"{{.*}}json.c","line":10,"col":3,
