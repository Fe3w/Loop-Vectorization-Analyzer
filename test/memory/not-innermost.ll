; Outer loop: LAA is not queried (LoopVectorize's inner-loop path only analyses innermost loops).
; Inner loop: a[j*n+i] = 0, a single store, safe.
; Source: void nest(float *a, int n) { for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) a[j*n+i] = 0; }
; Generated with the fixture recipe in DECISIONS.md (-g0), reduced; TBAA kept (LAA uses it).
; Oracle: opt -passes='print<access-info>'; remark name from -passes=loop-vectorize -pass-remarks-output.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nest'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  mem <not-innermost>{{$}}
; CHECK-NEXT:  blocker <not-innermost>{{$}}
; CHECK-NEXT:  loop header=%for.body4 depth=2 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  cfg 
; CHECK-NEXT:  mem status=safe checks=0 max-safe-width=any report=none{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @nest(ptr noundef %a, i32 noundef %n) {
entry:
  %cmp9 = icmp slt i32 0, %n
  br i1 %cmp9, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end7

for.body:
  %j.010 = phi i32 [ 0, %for.body.lr.ph ], [ %inc6, %for.inc5 ]
  %cmp27 = icmp slt i32 0, %n
  br i1 %cmp27, label %for.body4.lr.ph, label %for.cond.cleanup3

for.body4.lr.ph:
  br label %for.body4

for.cond1.for.cond.cleanup3_crit_edge:
  br label %for.cond.cleanup3

for.cond.cleanup3:
  br label %for.end

for.body4:
  %i.08 = phi i32 [ 0, %for.body4.lr.ph ], [ %inc, %for.inc ]
  %mul = mul nsw i32 %j.010, %n
  %add = add nsw i32 %mul, %i.08
  %idxprom = sext i32 %add to i64
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom
  store float 0.000000e+00, ptr %arrayidx, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.08, 1
  %cmp2 = icmp slt i32 %inc, %n
  br i1 %cmp2, label %for.body4, label %for.cond1.for.cond.cleanup3_crit_edge

for.end:
  br label %for.inc5

for.inc5:
  %inc6 = add nsw i32 %j.010, 1
  %cmp = icmp slt i32 %inc6, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end7:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
