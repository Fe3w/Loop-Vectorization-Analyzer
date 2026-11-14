; break on data, with a store in the loop.
; Source: void whilebrk(int *restrict a, int *restrict b, int n) { for (int i = 0; i < n; i++) { if (b[i] < 0) break; a[i] = b[i]; } }
; Fixture: scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
; LLVM 20 on this IR: WritesInEarlyExitLoop
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'whilebrk'
; CHECK:       loop header=%for.body depth=1 
; CHECK:       form 
; CHECK-NEXT:  cfg blocks=2 predicated=0 switches=0 exits=2 early-exit=uncountable{{$}}
; CHECK:       blocker primary=control-flow rule=cfg-uncountable-early-exit secondary=trip-count{{$}}
; CHECK-NOT:   {{loop header=|cfg }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

@g = dso_local local_unnamed_addr global [1024 x i32] zeroinitializer, align 16

define void @whilebrk(ptr noalias nocapture noundef writeonly %a, ptr noalias nocapture noundef readonly %b, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp11 = icmp sgt i32 %n, 0
  br i1 %cmp11, label %for.body.preheader, label %cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %if.end ]
  %arrayidx = getelementptr inbounds nuw i32, ptr %b, i64 %indvars.iv
  %0 = load i32, ptr %arrayidx, align 4, !tbaa !0
  %cmp1 = icmp slt i32 %0, 0
  br i1 %cmp1, label %cleanup.loopexit, label %if.end

if.end:
  %arrayidx5 = getelementptr inbounds nuw i32, ptr %a, i64 %indvars.iv
  store i32 %0, ptr %arrayidx5, align 4, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %cleanup.loopexit, label %for.body

cleanup.loopexit:
  br label %cleanup

cleanup:
  ret void
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
