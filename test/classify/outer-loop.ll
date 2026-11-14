; Outer loops are never considered by LoopVectorize's inner-loop path.
; Source: void nest(float *a, int n) { for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) a[j*n+i] = 0; }
; Earlier IR was copied from test/memory/not-innermost.ll.
; LLVM 20 on this IR (opt -passes=loop-vectorize -pass-remarks-output): Vectorized (inner loop)
; Fixture (session 10): scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nest'
; CHECK:       loop header=
; CHECK:       blocker <not-innermost>{{$}}
; CHECK:       loop header=
; CHECK:       blocker primary=none rule=none secondary=none{{$}}
; CHECK-NOT:   {{loop header=|blocker }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @nest(ptr nocapture noundef %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp25 = icmp sgt i32 %n, 0
  br i1 %cmp25, label %for.cond1.preheader.us.preheader, label %for.cond.cleanup

for.cond1.preheader.us.preheader:
  %0 = zext nneg i32 %n to i64
  br label %for.cond1.preheader.us

for.cond1.preheader.us:
  %indvars.iv29 = phi i64 [ 0, %for.cond1.preheader.us.preheader ], [ %indvars.iv.next30, %for.cond1.for.cond.cleanup3_crit_edge.us ]
  %1 = mul nuw nsw i64 %indvars.iv29, %0
  %invariant.gep = getelementptr inbounds nuw float, ptr %a, i64 %1
  br label %for.body4.us

for.body4.us:
  %indvars.iv = phi i64 [ 0, %for.cond1.preheader.us ], [ %indvars.iv.next, %for.body4.us ]
  %gep = getelementptr inbounds nuw float, ptr %invariant.gep, i64 %indvars.iv
  %2 = load float, ptr %gep, align 4, !tbaa !0
  %mul5.us = fmul float %2, 2.000000e+00
  store float %mul5.us, ptr %gep, align 4, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %0
  br i1 %exitcond.not, label %for.cond1.for.cond.cleanup3_crit_edge.us, label %for.body4.us

for.cond1.for.cond.cleanup3_crit_edge.us:
  %indvars.iv.next30 = add nuw nsw i64 %indvars.iv29, 1
  %exitcond34.not = icmp eq i64 %indvars.iv.next30, %0
  br i1 %exitcond34.not, label %for.cond.cleanup.loopexit, label %for.cond1.preheader.us

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
