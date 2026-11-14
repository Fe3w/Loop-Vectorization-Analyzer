; a[i] = a[i-1] + 1: loop-carried dependence of distance 1.
; Source: void unsafe1(float *a, int n) { for (int i = 1; i < n; i++) a[i] = a[i-1] + 1.0f; }
; Earlier IR was copied from test/dependence/backward.ll.
; LLVM 20 on this IR (opt -passes=loop-vectorize -pass-remarks-output): UnsafeDep
; Fixture (session 10): scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'unsafe1'
; CHECK:       loop header=
; CHECK:       blocker primary=loop-carried-dependence rule=mem-unsafe-dep secondary=none{{$}}
; CHECK-NOT:   {{loop header=|blocker }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @unsafe1(ptr nocapture noundef %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp7 = icmp sgt i32 %n, 1
  br i1 %cmp7, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 1, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %0 = getelementptr float, ptr %a, i64 %indvars.iv
  %arrayidx = getelementptr i8, ptr %0, i64 -4
  %1 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add = fadd float %1, 1.000000e+00
  store float %add, ptr %0, align 4, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
