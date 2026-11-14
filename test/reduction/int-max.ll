; Integer max via ?: -- a select after SimplifyCFG/InstCombine, recognised as smax.
; Source: int imax(int *a, int n) { int m = a[0]; for (int i = 0; i < n; i++) m = a[i] > m ? a[i] : m; return m; }
; Fixture: scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
; LLVM 20 on this IR: Vectorized
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'imax'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%indvars.iv 
; CHECK-NEXT:  recur phi=%m.013 kind=smax{{$}}
; CHECK-NEXT:  form 
; CHECK:       blocker primary=none rule=none secondary=none{{$}}
; CHECK-NOT:   {{loop header=|recur }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define i32 @imax(ptr nocapture noundef readonly %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %0 = load i32, ptr %a, align 4, !tbaa !0
  %cmp12 = icmp sgt i32 %n, 0
  br i1 %cmp12, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  %.m.0.lcssa = phi i32 [ %.m.0, %for.body ]
  br label %for.cond.cleanup

for.cond.cleanup:
  %m.0.lcssa = phi i32 [ %0, %entry ], [ %.m.0.lcssa, %for.cond.cleanup.loopexit ]
  ret i32 %m.0.lcssa

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %m.013 = phi i32 [ %0, %for.body.preheader ], [ %.m.0, %for.body ]
  %arrayidx1 = getelementptr inbounds nuw i32, ptr %a, i64 %indvars.iv
  %1 = load i32, ptr %arrayidx1, align 4, !tbaa !0
  %.m.0 = tail call i32 @llvm.smax.i32(i32 %1, i32 %m.013)
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

declare i32 @llvm.smax.i32(i32, i32) #1

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
