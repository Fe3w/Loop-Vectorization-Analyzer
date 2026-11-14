; A library call in a block that needs predication: if-conversion fails first
; (NoCFGForSelect); the call itself is the secondary reason.
; Source: void condcall(float *restrict a, int n) { for (int i = 0; i < n; i++) if (a[i] < 0) a[i] = __builtin_sqrtf(-a[i]); }
; Fixture: scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
; LLVM 20 on this IR: NoCFGForSelect, then CantVectorizeLibcall
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'condcall'
; CHECK:       loop header=%for.body depth=1 
; CHECK:       form 
; CHECK-NEXT:  cfg blocks=3 predicated=1 switches=0 exits=1 early-exit=none{{$}}
; CHECK:       blocker primary=control-flow rule=cfg-unpredicable secondary=call-or-unsafe-memop{{$}}
; CHECK-NOT:   {{loop header=|cfg }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @condcall(ptr noalias nocapture noundef %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp12 = icmp sgt i32 %n, 0
  br i1 %cmp12, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.inc ]
  %arrayidx = getelementptr inbounds nuw float, ptr %a, i64 %indvars.iv
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %cmp1 = fcmp olt float %0, 0.000000e+00
  br i1 %cmp1, label %if.then, label %for.inc

if.then:
  %fneg = fneg float %0
  %call = tail call float @sqrtf(float noundef %fneg) #2, !tbaa !4
  store float %call, ptr %arrayidx, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

declare float @sqrtf(float noundef) local_unnamed_addr #1

attributes #0 = { nofree nounwind memory(write, argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { mustprogress nofree nounwind willreturn memory(write) "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { nounwind }

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
!4 = !{!5, !5, i64 0}
!5 = !{!"int", !2, i64 0}
