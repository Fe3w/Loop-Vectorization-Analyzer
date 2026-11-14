; restrict pointers: no runtime checks needed, no dependences.
; Source: void safe(float *restrict a, float *restrict b, int n) { for (int i = 0; i < n; i++) a[i] = b[i] + 1.0f; }
; Generated with the fixture recipe in DECISIONS.md (-g0), reduced; TBAA kept (LAA uses it).
; Oracle: opt -passes='print<access-info>'; remark name from -passes=loop-vectorize -pass-remarks-output.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'safe'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  cfg 
; CHECK-NEXT:  mem status=safe checks=0 max-safe-width=any report=none{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @safe(ptr noalias noundef %a, ptr noalias noundef %b, i32 noundef %n) {
entry:
  %cmp4 = icmp slt i32 0, %n
  br i1 %cmp4, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.05 = phi i32 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %idxprom = sext i32 %i.05 to i64
  %arrayidx = getelementptr inbounds float, ptr %b, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add = fadd float %0, 1.000000e+00
  %idxprom1 = sext i32 %i.05 to i64
  %arrayidx2 = getelementptr inbounds float, ptr %a, i64 %idxprom1
  store float %add, ptr %arrayidx2, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.05, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
