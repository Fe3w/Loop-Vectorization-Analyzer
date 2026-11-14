; Same loop without -ffast-math: the repair still applies (the dependence is gone in
; the fast copy), but the promoted value is a strict FP reduction, so LoopVectorize
; now stops at CantReorderFPOps instead of UnsafeDep. The repair moves the blocker
; to one the programmer can lift (-ffast-math or #pragma clang loop vectorize(enable)).
; Fixture: scripts/make_fixture.sh --o3 of chol.c.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes='looplens-repair,loop-vectorize' \
; RUN:   -pass-remarks-analysis=loop-vectorize -disable-output %s 2>&1 | FileCheck %s
; The fast copy now stops at FP reordering; the original copy (taken only when the
; ranges overlap) keeps its UnsafeDep -- LoopVectorize reports both loops.
; CHECK-DAG: cannot prove it is safe to reorder floating-point operations
; CHECK-DAG: unsafe dependent memory operations

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @chol(i32 noundef %n, ptr nocapture noundef %A) local_unnamed_addr #0 {
entry:
  %0 = zext i32 %n to i64
  %cmp44 = icmp sgt i32 %n, 0
  br i1 %cmp44, label %for.cond1.preheader.preheader, label %for.cond.cleanup

for.cond1.preheader.preheader:
  br label %for.cond1.preheader

for.cond1.preheader:
  %indvars.iv52 = phi i64 [ %indvars.iv.next53, %for.cond.cleanup3 ], [ 0, %for.cond1.preheader.preheader ]
  %cmp242.not = icmp eq i64 %indvars.iv52, 0
  br i1 %cmp242.not, label %for.cond.cleanup3, label %for.cond5.preheader.lr.ph

for.cond5.preheader.lr.ph:
  %1 = mul nuw nsw i64 %indvars.iv52, %0
  %arrayidx = getelementptr inbounds nuw double, ptr %A, i64 %1
  br label %for.cond5.preheader

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.cond5.preheader:
  %indvars.iv47 = phi i64 [ 0, %for.cond5.preheader.lr.ph ], [ %indvars.iv.next48, %for.cond.cleanup7 ]
  %cmp640.not = icmp eq i64 %indvars.iv47, 0
  br i1 %cmp640.not, label %for.cond.cleanup7, label %for.body8.lr.ph

for.body8.lr.ph:
  %2 = mul nuw nsw i64 %indvars.iv47, %0
  %arrayidx12 = getelementptr inbounds nuw double, ptr %A, i64 %2
  %arrayidx18 = getelementptr inbounds nuw double, ptr %arrayidx, i64 %indvars.iv47
  %arrayidx18.promoted = load double, ptr %arrayidx18, align 8, !tbaa !0
  br label %for.body8

for.cond.cleanup3.loopexit:
  br label %for.cond.cleanup3

for.cond.cleanup3:
  %indvars.iv.next53 = add nuw nsw i64 %indvars.iv52, 1
  %exitcond55.not = icmp eq i64 %indvars.iv.next53, %0
  br i1 %exitcond55.not, label %for.cond.cleanup.loopexit, label %for.cond1.preheader

for.cond.cleanup7.loopexit:
  br label %for.cond.cleanup7

for.cond.cleanup7:
  %indvars.iv.next48 = add nuw nsw i64 %indvars.iv47, 1
  %exitcond51.not = icmp eq i64 %indvars.iv.next48, %indvars.iv52
  br i1 %exitcond51.not, label %for.cond.cleanup3.loopexit, label %for.cond5.preheader

for.body8:
  %indvars.iv = phi i64 [ 0, %for.body8.lr.ph ], [ %indvars.iv.next, %for.body8 ]
  %3 = phi double [ %arrayidx18.promoted, %for.body8.lr.ph ], [ %6, %for.body8 ]
  %arrayidx10 = getelementptr inbounds nuw double, ptr %arrayidx, i64 %indvars.iv
  %4 = load double, ptr %arrayidx10, align 8, !tbaa !0
  %arrayidx14 = getelementptr inbounds nuw double, ptr %arrayidx12, i64 %indvars.iv
  %5 = load double, ptr %arrayidx14, align 8, !tbaa !0
  %neg = fneg double %4
  %6 = tail call double @llvm.fmuladd.f64(double %neg, double %5, double %3)
  store double %6, ptr %arrayidx18, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %indvars.iv47
  br i1 %exitcond.not, label %for.cond.cleanup7.loopexit, label %for.body8
}

declare double @llvm.fmuladd.f64(double, double, double) #1

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
