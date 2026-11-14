// The optimization record holds the LoopLens and LoopVectorize remarks for the same
// loop with the same DebugLoc.
// RUN: %looplens_clang -O3 -g -fsave-optimization-record \
// RUN:   -foptimization-record-file=%t.yaml -c %s -o /dev/null
// RUN: FileCheck %s < %t.yaml

float fsum(float *a, int n) {
  float s = 0;
  for (int i = 0; i < n; i++)
    s += a[i];
  return s;
}
// CHECK:      Pass: looplens
// CHECK-NEXT: Name: red-exact-fp
// CHECK-NEXT: DebugLoc: { File: '{{.*}}yaml.c', Line: 9, Column: 3 }
// CHECK:      --- !Missed
// CHECK-NEXT: Pass: loop-vectorize
// CHECK-NEXT: Name: MissedDetails
// CHECK-NEXT: DebugLoc: { File: '{{.*}}yaml.c', Line: 9, Column: 3 }
