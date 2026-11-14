; A switch with stores in every case: LLVM 20 if-converts it.
; Source: void sw(int *restrict a, int *restrict b, int n) { for (int i = 0; i < n; i++) { switch (b[i]) { case 0: a[i] = 1; break; case 1: a[i] = 5; break; case 7: a[i] = 9; break; default: a[i] = 2; } } }
; Fixture: scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
; LLVM 20 on this IR: Vectorized
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'sw'
; CHECK:       loop header=%for.body depth=1 
; CHECK:       form 
; CHECK-NEXT:  cfg blocks=5 predicated=3 switches=1 exits=1 early-exit=none{{$}}
; CHECK:       blocker primary=none rule=none secondary=none{{$}}
; CHECK-NOT:   {{loop header=|cfg }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @sw(ptr noalias nocapture noundef writeonly %a, ptr noalias nocapture noundef readonly %b, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp20 = icmp sgt i32 %n, 0
  br i1 %cmp20, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.inc ]
  %arrayidx = getelementptr inbounds nuw i32, ptr %b, i64 %indvars.iv
  %0 = load i32, ptr %arrayidx, align 4, !tbaa !0
  %arrayidx10 = getelementptr inbounds nuw i32, ptr %a, i64 %indvars.iv
  switch i32 %0, label %sw.default [
    i32 0, label %for.inc
    i32 1, label %sw.bb3
    i32 7, label %sw.bb6
  ]

sw.bb3:
  br label %for.inc

sw.bb6:
  br label %for.inc

sw.default:
  br label %for.inc

for.inc:
  %.sink = phi i32 [ 5, %sw.bb3 ], [ 9, %sw.bb6 ], [ 2, %sw.default ], [ 1, %for.body ]
  store i32 %.sink, ptr %arrayidx10, align 4, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
