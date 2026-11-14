; TSVC's shape (s1232, tsvc.c:1141): a repetition loop around a column
; walk. The store aa[i][j] -> itself across repetitions is DependenceAnalysis
; "[S 0 0]": any direction at the repetition level, '=' at j and i. Swapping j
; and i keeps the repetition loop's order, so interchanging them is legal:
; LoopLens says legal=yes. LLVM 20's loop-interchange refuses, because its
; isLexicographicallyPositive check stops at the first non-'=' entry of the
; whole row -- the '*' of the repetition loop, which the swap does not move.
; LoopLens is more precise here; it does not claim LLVM will do it.
; Source: for (nl) for (j) for (i) aa[i][j] = bb[i][j] + cc[i][j];  (globals)
; Fixture: scripts/make_fixture.sh --o3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s
; RUN: opt -passes='print<da>' -disable-output %s 2>&1 | FileCheck --check-prefix=DA %s
; RUN: opt -passes='loop(loop-interchange)' -pass-remarks-missed=loop-interchange \
; RUN:   -disable-output %s 2>&1 | FileCheck --check-prefix=LLVM %s

; CHECK:      loop header=%for.body8 depth=3
; CHECK:      interchange legal=yes dirs=[(=,=)]{{$}}
; DA:         store double {{.*}} --> Dst:  store double
; DA-NEXT:    da analyze - consistent output [S 0 0]!
; LLVM: Cannot interchange loops due to dependences.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

@bb = dso_local local_unnamed_addr global [256 x [256 x double]] zeroinitializer, align 16
@cc = dso_local local_unnamed_addr global [256 x [256 x double]] zeroinitializer, align 16
@aa = dso_local local_unnamed_addr global [256 x [256 x double]] zeroinitializer, align 16

define void @rep(i32 noundef %reps) local_unnamed_addr #0 {
entry:
  %cmp36 = icmp sgt i32 %reps, 0
  br i1 %cmp36, label %for.cond1.preheader.preheader, label %for.cond.cleanup

for.cond1.preheader.preheader:
  br label %for.cond1.preheader

for.cond1.preheader:
  %nl.037 = phi i32 [ %inc23, %for.cond.cleanup3 ], [ 0, %for.cond1.preheader.preheader ]
  br label %for.cond5.preheader

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.cond5.preheader:
  %indvars.iv39 = phi i64 [ 0, %for.cond1.preheader ], [ %indvars.iv.next40, %for.cond.cleanup7 ]
  br label %for.body8

for.cond.cleanup3:
  %inc23 = add nuw nsw i32 %nl.037, 1
  %exitcond43.not = icmp eq i32 %inc23, %reps
  br i1 %exitcond43.not, label %for.cond.cleanup.loopexit, label %for.cond1.preheader

for.cond.cleanup7:
  %indvars.iv.next40 = add nuw nsw i64 %indvars.iv39, 1
  %exitcond42.not = icmp eq i64 %indvars.iv.next40, 256
  br i1 %exitcond42.not, label %for.cond.cleanup3, label %for.cond5.preheader

for.body8:
  %indvars.iv = phi i64 [ 0, %for.cond5.preheader ], [ %indvars.iv.next, %for.body8 ]
  %arrayidx10 = getelementptr inbounds nuw [256 x [256 x double]], ptr @bb, i64 0, i64 %indvars.iv, i64 %indvars.iv39
  %0 = load double, ptr %arrayidx10, align 8, !tbaa !0
  %arrayidx14 = getelementptr inbounds nuw [256 x [256 x double]], ptr @cc, i64 0, i64 %indvars.iv, i64 %indvars.iv39
  %1 = load double, ptr %arrayidx14, align 8, !tbaa !0
  %add = fadd double %0, %1
  %arrayidx18 = getelementptr inbounds nuw [256 x [256 x double]], ptr @aa, i64 0, i64 %indvars.iv, i64 %indvars.iv39
  store double %add, ptr %arrayidx18, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, 256
  br i1 %exitcond.not, label %for.cond.cleanup7, label %for.body8
}

attributes #0 = { nofree norecurse nosync nounwind memory(readwrite, argmem: none, inaccessiblemem: none) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
