; p[i].y in an array of 12-byte structs: step 12 bytes = 3 floats.
; Source: struct P { float x, y, z; }; void structf(float *restrict a, struct P *restrict p, int n) { for (int i = 0; i < n; i++) a[i] = p[i].y; }
; Fixture: scripts/make_fixture.sh --tbaa. Oracle: the pointer SCEV in
; opt -passes='print<scalar-evolution>' (AddRec step in bytes / element size).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'structf'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  cfg 
; CHECK-NEXT:  mem 
; CHECK-NEXT:  dep 
; CHECK-NEXT:  access load ptr=%y kind=constant stride=3{{$}}
; CHECK-NEXT:  access store ptr=%arrayidx2 kind=unit stride=1{{$}}
; CHECK-NOT:   {{loop header=|access load|access store}}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

%struct.P = type { float, float, float }

define void @structf(ptr noalias noundef %a, ptr noalias noundef %p, i32 noundef %n) {
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
  %arrayidx = getelementptr inbounds %struct.P, ptr %p, i64 %idxprom
  %y = getelementptr inbounds nuw %struct.P, ptr %arrayidx, i32 0, i32 1
  %0 = load float, ptr %y, align 4, !tbaa !0
  %idxprom1 = sext i32 %i.05 to i64
  %arrayidx2 = getelementptr inbounds float, ptr %a, i64 %idxprom1
  store float %0, ptr %arrayidx2, align 4, !tbaa !5
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.05, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !2, i64 4}
!1 = !{!"P", !2, i64 0, !2, i64 4, !2, i64 8}
!2 = !{!"float", !3, i64 0}
!3 = !{!"omnipotent char", !4, i64 0}
!4 = !{!"Simple C/C++ TBAA"}
!5 = !{!2, !2, i64 0}
