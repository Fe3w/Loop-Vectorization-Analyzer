; Triangular nest: the inner trip count depends on the outer IV, so the inner BTC is an
; add-recurrence of the OUTER loop ({-1,+,1}<nsw><%for.body>).
;
; Source (tri.c):
;    1 void tri(float *a, long n) {
;    2   for (long i = 0; i < n; i++)
;    3     for (long j = 0; j < i; j++)
;    4       a[i * n + j] = 0;
;    5 }
; Generated with the fixture recipe in DECISIONS.md (-g0), reduced.
; Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'tri'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + %n)] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + %n)]{{$}}
; CHECK-NEXT:  iv phi=%i.010 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=no guarded=yes{{$}}
; CHECK-NEXT:  mem <not-innermost>{{$}}
; CHECK-NEXT:  blocker <not-innermost>{{$}}
; CHECK-NEXT:  loop header=%for.body4 depth=2 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[{-1,+,1}<nsw><%for.body>] max-btc=[9223372036854775805] symbolic-max-btc=[{-1,+,1}<nsw><%for.body>]{{$}}
; CHECK-NEXT:  iv phi=%j.08 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body4>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes{{$}}
; CHECK-NEXT:  cfg blocks=2 predicated=0 switches=0 exits=1 early-exit=none{{$}}
; CHECK-NEXT:  mem status=safe checks=0 max-safe-width=any report=none{{$}}
; CHECK-NEXT:  dep <none>{{$}}
; CHECK-NEXT:  access store ptr=%arrayidx kind=unit stride=1{{$}}
; CHECK-NEXT:  blocker primary=none rule=none secondary=none{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @tri(ptr noundef %a, i64 noundef %n) {
entry:
  %cmp9 = icmp slt i64 0, %n
  br i1 %cmp9, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end7

for.body:
  %i.010 = phi i64 [ 0, %for.body.lr.ph ], [ %inc6, %for.inc5 ]
  %cmp27 = icmp slt i64 0, %i.010
  br i1 %cmp27, label %for.body4.lr.ph, label %for.cond.cleanup3

for.body4.lr.ph:
  br label %for.body4

for.cond1.for.cond.cleanup3_crit_edge:
  br label %for.cond.cleanup3

for.cond.cleanup3:
  br label %for.end

for.body4:
  %j.08 = phi i64 [ 0, %for.body4.lr.ph ], [ %inc, %for.inc ]
  %mul = mul nsw i64 %i.010, %n
  %add = add nsw i64 %mul, %j.08
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %add
  store float 0.000000e+00, ptr %arrayidx, align 4
  br label %for.inc

for.inc:
  %inc = add nsw i64 %j.08, 1
  %cmp2 = icmp slt i64 %inc, %i.010
  br i1 %cmp2, label %for.body4, label %for.cond1.for.cond.cleanup3_crit_edge

for.end:
  br label %for.inc5

for.inc5:
  %inc6 = add nsw i64 %i.010, 1
  %cmp = icmp slt i64 %inc6, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end7:
  ret void
}
