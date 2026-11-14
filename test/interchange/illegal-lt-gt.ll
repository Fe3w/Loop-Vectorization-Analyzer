; A[j][i] = A[j+1][i-1] + 1 with i outer, j inner: the value written at (i, j)
; is read at (i+1, j-1), direction (<,>). DependenceAnalysis reports the pair
; load -> store as [-1 1]; normalised (Dependence::normalize, as LoopInterchange
; does) it is (<,>). After interchange (j outer) iteration (j-1, i+1) runs
; before (j, i), so the read sees the old value: not legal.
; Counterexample: (i=1, j=1) writes A[1][1]; (i=2, j=0) reads A[1][1].
; Fixture: scripts/make_fixture.sh --o3. Oracle: LLVM refuses with "Cannot
; interchange loops due to dependences".
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -looplens-text=false \
; RUN:   -looplens-json=%t.jsonl -passes=looplens-analyze -disable-output %s
; RUN: FileCheck --check-prefix=JSON %s < %t.jsonl
; RUN: opt -passes='loop(loop-interchange)' -pass-remarks-missed=loop-interchange \
; RUN:   -disable-output %s 2>&1 | FileCheck --check-prefix=LLVM %s

; CHECK:      loop header=%for.body4 depth=2
; CHECK:      interchange legal=no dirs=[(<,>)]{{$}}
; CHECK-NEXT: blocker primary=stride rule=cost-strided
; CHECK:      fix interchange with the parent loop is not legal (a dependence has direction (<,>)); transpose the data
; JSON: "rule":"cost-strided"{{.*}}"interchange":{"legal":false,"dirs":["(<,>)"],"bounds_depend_on_parent":false,"why":null}
; LLVM: Cannot interchange loops due to dependences.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @skew(ptr nocapture noundef %A) local_unnamed_addr #0 {
entry:
  br label %for.cond1.preheader

for.cond1.preheader:
  %indvars.iv25 = phi i64 [ 1, %entry ], [ %indvars.iv.next26, %for.cond.cleanup3 ]
  %0 = add nsw i64 %indvars.iv25, -1
  br label %for.body4

for.cond.cleanup:
  ret void

for.cond.cleanup3:
  %indvars.iv.next26 = add nuw nsw i64 %indvars.iv25, 1
  %exitcond29.not = icmp eq i64 %indvars.iv.next26, 512
  br i1 %exitcond29.not, label %for.cond.cleanup, label %for.cond1.preheader

for.body4:
  %indvars.iv = phi i64 [ 0, %for.cond1.preheader ], [ %indvars.iv.next, %for.body4 ]
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %arrayidx6 = getelementptr inbounds [512 x double], ptr %A, i64 %indvars.iv.next, i64 %0
  %1 = load double, ptr %arrayidx6, align 8, !tbaa !0
  %add7 = fadd double %1, 1.000000e+00
  %arrayidx11 = getelementptr inbounds nuw [512 x double], ptr %A, i64 %indvars.iv, i64 %indvars.iv25
  store double %add7, ptr %arrayidx11, align 8, !tbaa !0
  %exitcond.not = icmp eq i64 %indvars.iv.next, 511
  br i1 %exitcond.not, label %for.cond.cleanup3, label %for.body4
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
