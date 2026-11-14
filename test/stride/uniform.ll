; b[0]: the same address every iteration.
; Source: void unif(float *restrict a, float *restrict b, int n) { for (int i = 0; i < n; i++) a[i] = b[0]; }
; Fixture: scripts/make_fixture.sh --tbaa. Oracle: the pointer SCEV in
; opt -passes='print<scalar-evolution>' (AddRec step in bytes / element size).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'unif'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  cfg 
; CHECK-NEXT:  mem 
; CHECK-NEXT:  dep 
; CHECK-NEXT:  access load ptr=%arrayidx kind=uniform stride=0{{$}}
; CHECK-NEXT:  access store ptr=%arrayidx1 kind=unit stride=1{{$}}
; CHECK-NOT:   {{loop header=|access load|access store}}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @unif(ptr noalias noundef %a, ptr noalias noundef %b, i32 noundef %n) {
entry:
  %cmp3 = icmp slt i32 0, %n
  br i1 %cmp3, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.04 = phi i32 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %arrayidx = getelementptr inbounds float, ptr %b, i64 0
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %idxprom = sext i32 %i.04 to i64
  %arrayidx1 = getelementptr inbounds float, ptr %a, i64 %idxprom
  store float %0, ptr %arrayidx1, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.04, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
