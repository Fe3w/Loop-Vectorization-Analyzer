; Triangular nest (TSVC s1232 shape): the inner loop starts at i = j, so its
; trip count depends on the parent loop (BTC {511,+,-1}<%parent>). The swap
; is legal by dependences (only (=,=)), but the new loops need new bounds
; (j from 0 to i): LLVM 20's loop-interchange cannot do that ("Inner loop
; structure not understood currently"), so the fix must not promise the clang
; flag; it says to rewrite the bounds by hand.
; Source: for (j) for (i = j; i < N; i++) A[i][j] = A[i][j] + B[i][j];  (restrict)
; Fixture: scripts/make_fixture.sh --o3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s
; RUN: opt -passes='loop(loop-interchange)' -pass-remarks-missed=loop-interchange \
; RUN:   -disable-output %s 2>&1 | FileCheck --check-prefix=LLVM %s

; CHECK:      loop header=%for.body4 depth=2
; CHECK:      interchange legal=yes dirs=[(=,=)] bounds=depend-on-parent{{$}}
; CHECK:      fix interchange this loop with its parent loop by hand (legal: no dependence has direction (<,>); the inner bounds depend on the parent's index, so they must be rewritten)
; CHECK-NOT:  enable-loopinterchange
; LLVM: Inner loop structure not understood currently.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @tri(ptr noalias nocapture noundef %A, ptr noalias nocapture noundef readonly %B) local_unnamed_addr #0 {
entry:
  br label %for.cond1.preheader

for.cond1.preheader:
  %indvars.iv = phi i64 [ 0, %entry ], [ %indvars.iv.next, %for.cond.cleanup3 ]
  br label %for.body4

for.cond.cleanup:
  ret void

for.cond.cleanup3:
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond34.not = icmp eq i64 %indvars.iv.next, 512
  br i1 %exitcond34.not, label %for.cond.cleanup, label %for.cond1.preheader

for.body4:
  %indvars.iv30 = phi i64 [ %indvars.iv, %for.cond1.preheader ], [ %indvars.iv.next31, %for.body4 ]
  %arrayidx6 = getelementptr inbounds nuw [512 x double], ptr %A, i64 %indvars.iv30, i64 %indvars.iv
  %0 = load double, ptr %arrayidx6, align 8, !tbaa !0
  %arrayidx10 = getelementptr inbounds nuw [512 x double], ptr %B, i64 %indvars.iv30, i64 %indvars.iv
  %1 = load double, ptr %arrayidx10, align 8, !tbaa !0
  %add = fadd double %0, %1
  store double %add, ptr %arrayidx6, align 8, !tbaa !0
  %indvars.iv.next31 = add nuw nsw i64 %indvars.iv30, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next31, 512
  br i1 %exitcond.not, label %for.cond.cleanup3, label %for.body4
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
