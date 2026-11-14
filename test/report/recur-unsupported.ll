; Evidence and fix text for the rule in the blocker line.
; IR copied from test/reduction/unsupported.ll.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nonred'
; CHECK:       blocker primary=reduction rule=recur-unsupported secondary=none{{$}}
; CHECK-NEXT:  evidence %s.06 is neither an induction, a reduction nor a recurrence{{$}}
; CHECK-NEXT:  fix rewrite the update of %s.06 as a sum/min/max of independent terms, or split it into its own loop{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define float @nonred(ptr nocapture noundef readonly %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp5 = icmp sgt i32 %n, 0
  br i1 %cmp5, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  %.lcssa = phi float [ %1, %for.body ]
  br label %for.cond.cleanup

for.cond.cleanup:
  %s.0.lcssa = phi float [ 1.000000e+00, %entry ], [ %.lcssa, %for.cond.cleanup.loopexit ]
  ret float %s.0.lcssa

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %s.06 = phi float [ 1.000000e+00, %for.body.preheader ], [ %1, %for.body ]
  %arrayidx = getelementptr inbounds nuw float, ptr %a, i64 %indvars.iv
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %1 = tail call float @llvm.fmuladd.f32(float %s.06, float %s.06, float %0)
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

declare float @llvm.fmuladd.f32(float, float, float) #1

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
