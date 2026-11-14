; Threshold: the accumulator must be checked against 9 address ranges. That is over
; the limit (-looplens-repair-max-checks, default 8, the value of LLVM's own
; -runtime-memory-check-threshold), so nothing is versioned. Raising the limit to 9
; repairs it.
; Source: void acc9(double *A, long r, long n, long c0, long c1, long c2, long c3, long c4, long c5, long c6, long c7, long c8) { for (long k = 0; k < n; k++) A[r] += A[c0 + k] + A[c1 + k] + A[c2 + k] + A[c3 + k] + A[c4 + k] + A[c5 + k] + A[c6 + k] + A[c7 + k] + A[c8 + k]; }
; Fixture: EXTRA_CFLAGS=-ffast-math scripts/make_fixture.sh --o3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-repair -pass-remarks=looplens-repair -S %s 2>&1 \
; RUN:   | FileCheck --implicit-check-not=lr.conflict --implicit-check-not=remark: %s
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-repair -looplens-repair-max-checks=9 \
; RUN:   -pass-remarks=looplens-repair -disable-output %s 2>&1 | FileCheck --check-prefix=NINE %s
; CHECK: define void @acc9(
; NINE: (9 address ranges checked at run time)

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @acc9(ptr nocapture noundef %A, i64 noundef %r, i64 noundef %n, i64 noundef %c0, i64 noundef %c1, i64 noundef %c2, i64 noundef %c3, i64 noundef %c4, i64 noundef %c5, i64 noundef %c6, i64 noundef %c7, i64 noundef %c8) local_unnamed_addr #0 {
entry:
  %cmp46 = icmp sgt i64 %n, 0
  br i1 %cmp46, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  %0 = getelementptr double, ptr %A, i64 %c0
  %1 = getelementptr double, ptr %A, i64 %c1
  %2 = getelementptr double, ptr %A, i64 %c2
  %3 = getelementptr double, ptr %A, i64 %c3
  %4 = getelementptr double, ptr %A, i64 %c4
  %5 = getelementptr double, ptr %A, i64 %c5
  %6 = getelementptr double, ptr %A, i64 %c6
  %7 = getelementptr double, ptr %A, i64 %c7
  %8 = getelementptr double, ptr %A, i64 %c8
  %arrayidx25 = getelementptr inbounds double, ptr %A, i64 %r
  %arrayidx25.promoted = load double, ptr %arrayidx25, align 8, !tbaa !0
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %add2648 = phi double [ %arrayidx25.promoted, %for.body.lr.ph ], [ %add26, %for.body ]
  %k.047 = phi i64 [ 0, %for.body.lr.ph ], [ %inc, %for.body ]
  %arrayidx = getelementptr double, ptr %0, i64 %k.047
  %9 = load double, ptr %arrayidx, align 8, !tbaa !0
  %arrayidx2 = getelementptr double, ptr %1, i64 %k.047
  %10 = load double, ptr %arrayidx2, align 8, !tbaa !0
  %add3 = fadd fast double %10, %9
  %arrayidx5 = getelementptr double, ptr %2, i64 %k.047
  %11 = load double, ptr %arrayidx5, align 8, !tbaa !0
  %add6 = fadd fast double %add3, %11
  %arrayidx8 = getelementptr double, ptr %3, i64 %k.047
  %12 = load double, ptr %arrayidx8, align 8, !tbaa !0
  %add9 = fadd fast double %add6, %12
  %arrayidx11 = getelementptr double, ptr %4, i64 %k.047
  %13 = load double, ptr %arrayidx11, align 8, !tbaa !0
  %add12 = fadd fast double %add9, %13
  %arrayidx14 = getelementptr double, ptr %5, i64 %k.047
  %14 = load double, ptr %arrayidx14, align 8, !tbaa !0
  %add15 = fadd fast double %add12, %14
  %arrayidx17 = getelementptr double, ptr %6, i64 %k.047
  %15 = load double, ptr %arrayidx17, align 8, !tbaa !0
  %add18 = fadd fast double %add15, %15
  %arrayidx20 = getelementptr double, ptr %7, i64 %k.047
  %16 = load double, ptr %arrayidx20, align 8, !tbaa !0
  %add21 = fadd fast double %add18, %16
  %arrayidx23 = getelementptr double, ptr %8, i64 %k.047
  %17 = load double, ptr %arrayidx23, align 8, !tbaa !0
  %add24 = fadd fast double %add21, %17
  %add26 = fadd fast double %add24, %add2648
  store double %add26, ptr %arrayidx25, align 8, !tbaa !0
  %inc = add nuw nsw i64 %k.047, 1
  %exitcond.not = icmp eq i64 %inc, %n
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "approx-func-fp-math"="true" "min-legal-vector-width"="0" "no-infs-fp-math"="true" "no-nans-fp-math"="true" "no-signed-zeros-fp-math"="true" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" "unsafe-fp-math"="true" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
