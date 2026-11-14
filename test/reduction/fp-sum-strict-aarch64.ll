; Strict float sum compiled for AArch64: the reduction still needs exact FP order,
; but AArch64's TTI enables ordered (in-order) reductions
; (TargetTransformInfo::enableOrderedReductions; LoopVectorize.cpp:10476-10483), so
; LoopVectorize vectorizes it there. red-exact-fp must not fire for this target.
; Fixture: EXTRA_CFLAGS=--target=aarch64-linux-gnu scripts/make_fixture.sh --o3.
; LLVM 20 on this IR: Vectorized.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s
; CHECK: recur phi={{%[a-z0-9.]+}} kind=fadd exact-fp=yes ordered=yes{{$}}
; CHECK: blocker primary=none rule=none secondary=none{{$}}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

define float @fsum(ptr nocapture noundef readonly %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp4 = icmp sgt i32 %n, 0
  br i1 %cmp4, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  %add.lcssa = phi float [ %add, %for.body ]
  br label %for.cond.cleanup

for.cond.cleanup:
  %s.0.lcssa = phi float [ 0.000000e+00, %entry ], [ %add.lcssa, %for.cond.cleanup.loopexit ]
  ret float %s.0.lcssa

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %s.05 = phi float [ 0.000000e+00, %for.body.preheader ], [ %add, %for.body ]
  %arrayidx = getelementptr inbounds nuw float, ptr %a, i64 %indvars.iv
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add = fadd float %s.05, %0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: read) uwtable "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="generic" "target-features"="+fp-armv8,+neon,+v8a,-fmv" }

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
