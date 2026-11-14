; Two IVs, printed in header phi order; only %i.06 feeds the latch compare.
; Source: for (long i = 0, j = n; i < n; i++, j--) a[i] = b[j];
; Generated with the fixture recipe in DECISIONS.md (-g0), reduced.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'twoiv'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%j.07 kind=int start=%n step=-1 scev=[{%n,+,-1}<nsw><%for.body>] controls-exit=no{{$}}
; CHECK-NEXT:  iv phi=%i.06 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @twoiv(ptr noundef %a, ptr noundef %b, i64 noundef %n) {
entry:
  %cmp5 = icmp slt i64 0, %n
  br i1 %cmp5, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %j.07 = phi i64 [ %n, %for.body.lr.ph ], [ %dec, %for.inc ]
  %i.06 = phi i64 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %arrayidx = getelementptr inbounds float, ptr %b, i64 %j.07
  %0 = load float, ptr %arrayidx, align 4
  %arrayidx1 = getelementptr inbounds float, ptr %a, i64 %i.06
  store float %0, ptr %arrayidx1, align 4
  br label %for.inc

for.inc:
  %inc = add nsw i64 %i.06, 1
  %dec = add nsw i64 %j.07, -1
  %cmp = icmp slt i64 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}
