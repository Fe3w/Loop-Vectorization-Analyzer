; Evidence and fix text for the rule in the blocker line.
; IR copied from test/dependence/backward.ll.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'unsafe1'
; CHECK:       blocker primary=loop-carried-dependence rule=mem-unsafe-dep secondary=none{{$}}
; CHECK-NEXT:  evidence Backward dependence load:%arrayidx -> store:%arrayidx2, distance 4 bytes{{$}}
; CHECK-NEXT:  fix the loop carries a value between iterations; restructure it (e.g. a separate scan), or make the dependence distance at least the vector length{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @unsafe1(ptr noundef %a, i32 noundef %n) {
entry:
  %cmp5 = icmp slt i32 1, %n
  br i1 %cmp5, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.06 = phi i32 [ 1, %for.body.lr.ph ], [ %inc, %for.inc ]
  %sub = sub nsw i32 %i.06, 1
  %idxprom = sext i32 %sub to i64
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add = fadd float %0, 1.000000e+00
  %idxprom1 = sext i32 %i.06 to i64
  %arrayidx2 = getelementptr inbounds float, ptr %a, i64 %idxprom1
  store float %add, ptr %arrayidx2, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.06, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
