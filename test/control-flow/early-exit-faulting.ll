; Search loop with an early return: the exit from %for.body depends on loaded data.
; Source: int earlybrk(int *a, int n, int k) { for (int i = 0; i < n; i++) if (a[i] == k) return i; return -1; }
; Fixture: scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
; LLVM 20 on this IR: PotentiallyFaultingEarlyExitLoop
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'earlybrk'
; CHECK:       loop header=%for.body depth=1 
; CHECK:       form 
; CHECK-NEXT:  cfg blocks=2 predicated=0 switches=0 exits=2 early-exit=uncountable{{$}}
; CHECK:       blocker primary=control-flow rule=cfg-uncountable-early-exit secondary=trip-count{{$}}
; CHECK-NOT:   {{loop header=|cfg }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define i32 @earlybrk(ptr nocapture noundef readonly %a, i32 noundef %n, i32 noundef %k) local_unnamed_addr #0 {
entry:
  %cmp.not5 = icmp sgt i32 %n, 0
  br i1 %cmp.not5, label %for.body.preheader, label %cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.inc ]
  %arrayidx = getelementptr inbounds nuw i32, ptr %a, i64 %indvars.iv
  %0 = load i32, ptr %arrayidx, align 4, !tbaa !0
  %cmp1 = icmp eq i32 %0, %k
  br i1 %cmp1, label %cleanup.loopexit.split.loop.exit, label %for.inc

for.inc:
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %cleanup.loopexit, label %for.body

cleanup.loopexit.split.loop.exit:
  %indvars.iv.lcssa = phi i64 [ %indvars.iv, %for.body ]
  %1 = trunc nuw nsw i64 %indvars.iv.lcssa to i32
  br label %cleanup

cleanup.loopexit:
  br label %cleanup

cleanup:
  %spec.select = phi i32 [ -1, %entry ], [ %1, %cleanup.loopexit.split.loop.exit ], [ -1, %cleanup.loopexit ]
  ret i32 %spec.select
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: read) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"int", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
