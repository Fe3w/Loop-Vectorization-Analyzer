; Data-dependent exit: trip count unknown (and LAA gives up for the same reason).
; Source: int datadep(int *a) { int i = 0; while (a[i] != 0) i++; return i; }
; Earlier IR was copied from test/memory/uncountable.ll.
; LLVM 20 on this IR (opt -passes=loop-vectorize -pass-remarks-output): UnsupportedUncountableLoop, CantComputeNumberOfIterations
; Fixture (session 10): scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'datadep'
; CHECK:       loop header=
; CHECK:       blocker primary=trip-count rule=trip-uncountable secondary=none{{$}}
; CHECK-NOT:   {{loop header=|blocker }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define i32 @datadep(ptr nocapture noundef readonly %a) local_unnamed_addr #0 {
entry:
  br label %while.cond

while.cond:
  %indvars.iv = phi i64 [ %indvars.iv.next, %while.cond ], [ 0, %entry ]
  %arrayidx = getelementptr inbounds nuw i32, ptr %a, i64 %indvars.iv
  %0 = load i32, ptr %arrayidx, align 4, !tbaa !0
  %cmp.not = icmp eq i32 %0, 0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  br i1 %cmp.not, label %while.end, label %while.cond

while.end:
  %indvars.iv.lcssa = phi i64 [ %indvars.iv, %while.cond ]
  %1 = trunc nuw nsw i64 %indvars.iv.lcssa to i32
  ret i32 %1
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
