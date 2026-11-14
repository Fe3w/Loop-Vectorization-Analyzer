; Evidence and fix text for the rule in the blocker line.
; IR copied from test/stride/indirect.ll.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'ind'
; CHECK:       blocker primary=stride rule=stride-gather secondary=none{{$}}
; CHECK-NEXT:  evidence load %arrayidx2 is indirect and the target has no legal gather{{$}}
; CHECK-NEXT:  fix make the access contiguous (sort or transpose the data); gathers may pay off with -march=native{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @ind(ptr noalias noundef %a, ptr noalias noundef %b, ptr noalias noundef %idx, i32 noundef %n) {
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
  %arrayidx = getelementptr inbounds i32, ptr %idx, i64 %idxprom
  %0 = load i32, ptr %arrayidx, align 4, !tbaa !0
  %idxprom1 = sext i32 %0 to i64
  %arrayidx2 = getelementptr inbounds float, ptr %b, i64 %idxprom1
  %1 = load float, ptr %arrayidx2, align 4, !tbaa !4
  %idxprom3 = sext i32 %i.05 to i64
  %arrayidx4 = getelementptr inbounds float, ptr %a, i64 %idxprom3
  store float %1, ptr %arrayidx4, align 4, !tbaa !4
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.05, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
!4 = !{!5, !5, i64 0}
!5 = !{!"float", !2, i64 0}
