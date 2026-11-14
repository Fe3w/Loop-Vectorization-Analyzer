; b[idx[i]]: legal, but a gather; the cost model rejects it on generic x86-64.
; Source: void ind(float *restrict a, float *restrict b, int *restrict idx, int n) { for (int i = 0; i < n; i++) a[i] = b[idx[i]]; }
; Earlier IR was copied from test/stride/indirect.ll.
; LLVM 20 on this IR (opt -passes=loop-vectorize -pass-remarks-output): VectorizationNotBeneficial
; Fixture (session 10): scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'ind'
; CHECK:       loop header=
; CHECK:       blocker primary=stride rule=stride-gather secondary=none{{$}}
; CHECK-NOT:   {{loop header=|blocker }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @ind(ptr noalias nocapture noundef writeonly %a, ptr noalias nocapture noundef readonly %b, ptr noalias nocapture noundef readonly %idx, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp8 = icmp sgt i32 %n, 0
  br i1 %cmp8, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %arrayidx = getelementptr inbounds nuw i32, ptr %idx, i64 %indvars.iv
  %0 = load i32, ptr %arrayidx, align 4, !tbaa !0
  %idxprom1 = sext i32 %0 to i64
  %arrayidx2 = getelementptr inbounds float, ptr %b, i64 %idxprom1
  %1 = load float, ptr %arrayidx2, align 4, !tbaa !4
  %arrayidx4 = getelementptr inbounds nuw float, ptr %a, i64 %indvars.iv
  store float %1, ptr %arrayidx4, align 4, !tbaa !4
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
!4 = !{!5, !5, i64 0}
!5 = !{!"float", !2, i64 0}
