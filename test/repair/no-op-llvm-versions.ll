; No-op: a loop that only needs runtime pointer checks. LoopAccessAnalysis accepts
; it (needs-checks) and LoopVectorize versions it itself (vector.memcheck), so
; looplens-repair leaves it alone.
; Source: void rtcheck(float *a, float *b, int n) { for (int i = 0; i < n; i++) a[i] = b[i] + 1.0f; }
; Fixture: EXTRA_CFLAGS=-ffast-math scripts/make_fixture.sh --o3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-repair -pass-remarks=looplens-repair -S %s 2>&1 \
; RUN:   | FileCheck --implicit-check-not=lr.conflict --implicit-check-not=remark: %s
; RUN: opt -passes=loop-vectorize -S %s | FileCheck --check-prefix=LV %s
; CHECK: define void @rtcheck(
; LV: vector.memcheck:

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @rtcheck(ptr nocapture noundef writeonly %a, ptr nocapture noundef readonly %b, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp6 = icmp sgt i32 %n, 0
  br i1 %cmp6, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %arrayidx = getelementptr inbounds nuw float, ptr %b, i64 %indvars.iv
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add = fadd fast float %0, 1.000000e+00
  %arrayidx2 = getelementptr inbounds nuw float, ptr %a, i64 %indvars.iv
  store float %add, ptr %arrayidx2, align 4, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "approx-func-fp-math"="true" "min-legal-vector-width"="0" "no-infs-fp-math"="true" "no-nans-fp-math"="true" "no-signed-zeros-fp-math"="true" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" "unsafe-fp-math"="true" }

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
