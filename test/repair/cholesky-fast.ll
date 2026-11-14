; looplens-repair on the PolyBench cholesky pattern (A[i][j] -= A[i][k] * A[j][k]):
; the loop is versioned on "A[i][j] is not in the ranges read" and, in the fast copy,
; (LICM already keeps A[i][j] in a phi but could not sink the store)
; A[i][j] lives in a register. Compiled with -ffast-math, LoopVectorize then
; vectorizes the fast copy; without the repair it reports UnsafeDep.
; Source: docs/plans/S21.md (chol.c). Fixture: EXTRA_CFLAGS=-ffast-math scripts/make_fixture.sh --o3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes='looplens-repair,verify' -S %s | FileCheck --check-prefix=IR %s
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes='looplens-repair,loop-vectorize' -S %s | FileCheck --check-prefix=VEC %s
; RUN: opt -passes=loop-vectorize -S %s | FileCheck --check-prefix=NOVEC %s
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-repair -pass-remarks=looplens-repair -disable-output %s 2>&1 \
; RUN:   | FileCheck --check-prefix=REM %s

; IR:      {{^}}{{.*}}.lr.check:
; IR:        br i1 %lr.conflict, label %{{.*}}.lr.orig, label %{{.*}}
; IR:        store double %lr.final, ptr
; VEC:     vector.body:
; NOVEC-NOT: vector.body:
; REM: remark: <unknown>:0:0: versioned loop and promoted the loop-invariant store to a register (2 address ranges checked at run time)

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @chol(i32 noundef %n, ptr nocapture noundef %A) local_unnamed_addr #0 {
entry:
  %0 = zext i32 %n to i64
  %cmp45 = icmp sgt i32 %n, 0
  br i1 %cmp45, label %for.cond1.preheader.preheader, label %for.cond.cleanup

for.cond1.preheader.preheader:
  br label %for.cond1.preheader

for.cond1.preheader:
  %indvars.iv53 = phi i64 [ %indvars.iv.next54, %for.cond.cleanup3 ], [ 0, %for.cond1.preheader.preheader ]
  %cmp243.not = icmp eq i64 %indvars.iv53, 0
  br i1 %cmp243.not, label %for.cond.cleanup3, label %for.cond5.preheader.lr.ph

for.cond5.preheader.lr.ph:
  %1 = mul nuw nsw i64 %indvars.iv53, %0
  %arrayidx = getelementptr inbounds nuw double, ptr %A, i64 %1
  br label %for.cond5.preheader

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.cond5.preheader:
  %indvars.iv48 = phi i64 [ 0, %for.cond5.preheader.lr.ph ], [ %indvars.iv.next49, %for.cond.cleanup7 ]
  %cmp640.not = icmp eq i64 %indvars.iv48, 0
  br i1 %cmp640.not, label %for.cond.cleanup7, label %for.body8.lr.ph

for.body8.lr.ph:
  %2 = mul nuw nsw i64 %indvars.iv48, %0
  %arrayidx12 = getelementptr inbounds nuw double, ptr %A, i64 %2
  %arrayidx18 = getelementptr inbounds nuw double, ptr %arrayidx, i64 %indvars.iv48
  %arrayidx18.promoted = load double, ptr %arrayidx18, align 8, !tbaa !0
  br label %for.body8

for.cond.cleanup3.loopexit:
  br label %for.cond.cleanup3

for.cond.cleanup3:
  %indvars.iv.next54 = add nuw nsw i64 %indvars.iv53, 1
  %exitcond56.not = icmp eq i64 %indvars.iv.next54, %0
  br i1 %exitcond56.not, label %for.cond.cleanup.loopexit, label %for.cond1.preheader

for.cond.cleanup7.loopexit:
  br label %for.cond.cleanup7

for.cond.cleanup7:
  %indvars.iv.next49 = add nuw nsw i64 %indvars.iv48, 1
  %exitcond52.not = icmp eq i64 %indvars.iv.next49, %indvars.iv53
  br i1 %exitcond52.not, label %for.cond.cleanup3.loopexit, label %for.cond5.preheader

for.body8:
  %indvars.iv = phi i64 [ 0, %for.body8.lr.ph ], [ %indvars.iv.next, %for.body8 ]
  %sub42 = phi double [ %arrayidx18.promoted, %for.body8.lr.ph ], [ %sub, %for.body8 ]
  %arrayidx10 = getelementptr inbounds nuw double, ptr %arrayidx, i64 %indvars.iv
  %3 = load double, ptr %arrayidx10, align 8, !tbaa !0
  %arrayidx14 = getelementptr inbounds nuw double, ptr %arrayidx12, i64 %indvars.iv
  %4 = load double, ptr %arrayidx14, align 8, !tbaa !0
  %mul = fmul fast double %4, %3
  %sub = fsub fast double %sub42, %mul
  store double %sub, ptr %arrayidx18, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %indvars.iv48
  br i1 %exitcond.not, label %for.cond.cleanup7.loopexit, label %for.body8
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "approx-func-fp-math"="true" "min-legal-vector-width"="0" "no-infs-fp-math"="true" "no-nans-fp-math"="true" "no-signed-zeros-fp-math"="true" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" "unsafe-fp-math"="true" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
