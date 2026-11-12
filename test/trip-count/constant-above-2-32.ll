; Constant trip count above 2^32: getSmallConstantTripCount returns 0 here, so the count comes from getTripCountFromExitCount.
;
; Source (big.c):
;    1 void big(float *a) {
;    2   for (long i = 0; i < 5000000000L; i++)
;    3     a[i] = 0;
;    4 }
; Generated with the fixture recipe in DECISIONS.md (-g0: location not under test), reduced.
; Oracle: opt -passes='print<scalar-evolution>' on this file (constants print as 'iN K' there).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'big'
; CHECK-NEXT:  loop header=for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=constant count=5000000000 btc=[4999999999] max-btc=[4999999999] symbolic-max-btc=[4999999999]{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @big(ptr noundef %a) {
entry:
  br label %for.body

for.cond.cleanup:
  br label %for.end

for.body:
  %i.03 = phi i64 [ 0, %entry ], [ %inc, %for.inc ]
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %i.03
  store float 0.000000e+00, ptr %arrayidx, align 4
  br label %for.inc

for.inc:
  %inc = add nsw i64 %i.03, 1
  %cmp = icmp slt i64 %inc, 5000000000
  br i1 %cmp, label %for.body, label %for.cond.cleanup

for.end:
  ret void
}
