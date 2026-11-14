; Down-counting IV: symbolic start %n, step -1.
; Source: for (long i = n; i > 0; i--) a[i] = 0;
; Generated with the fixture recipe in DECISIONS.md (-g0), reduced.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'down'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%i.04 kind=int start=%n step=-1 scev=[{%n,+,-1}<nsw><%for.body>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @down(ptr noundef %a, i64 noundef %n) {
entry:
  %cmp3 = icmp sgt i64 %n, 0
  br i1 %cmp3, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.04 = phi i64 [ %n, %for.body.lr.ph ], [ %dec, %for.inc ]
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %i.04
  store float 0.000000e+00, ptr %arrayidx, align 4
  br label %for.inc

for.inc:
  %dec = add nsw i64 %i.04, -1
  %cmp = icmp sgt i64 %dec, 0
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}
