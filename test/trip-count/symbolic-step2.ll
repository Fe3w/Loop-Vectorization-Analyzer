; Symbolic trip count with step 2 and a != exit: BTC is an unsigned division; 64-bit max.
;
; Source (step2ne.c):
;    1 void step2ne(float *a, long n) {
;    2   for (long i = 0; i != n; i += 2)
;    3     a[i] = 0;
;    4 }
; Generated with the fixture recipe in DECISIONS.md (-g0: location not under test), reduced.
; Oracle: opt -passes='print<scalar-evolution>' on this file (constants print as 'iN K' there).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'step2ne'
; CHECK-NEXT:  loop header=for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[((-2 + %n) /u 2)] max-btc=[9223372036854775807] symbolic-max-btc=[((-2 + %n) /u 2)]{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @step2ne(ptr noundef %a, i64 noundef %n) {
entry:
  %cmp3 = icmp ne i64 0, %n
  br i1 %cmp3, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.04 = phi i64 [ 0, %for.body.lr.ph ], [ %add, %for.inc ]
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %i.04
  store float 0.000000e+00, ptr %arrayidx, align 4
  br label %for.inc

for.inc:
  %add = add nsw i64 %i.04, 2
  %cmp = icmp ne i64 %add, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}
