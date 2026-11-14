; The outer loop stores s[j] around the inner column walk: not a perfect nest,
; so interchange does not apply as is (LLVM says "not tightly nested").
; Source: for (j) { s[j] = j; for (i) A[i][j] = A[i][j] + B[i][j]; }
; Fixture: scripts/make_fixture.sh --o3.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s
; RUN: opt -passes='loop(loop-interchange)' -pass-remarks-missed=loop-interchange \
; RUN:   -disable-output %s 2>&1 | FileCheck --check-prefix=LLVM %s

; CHECK:      loop header=%for.body5 depth=2
; CHECK:      interchange legal=unknown why=not-perfect-nest{{$}}
; CHECK-NEXT: blocker primary=stride rule=cost-strided
; CHECK:      fix interchange the loops or transpose the data so the innermost loop walks memory contiguously (interchange legality unknown: not-perfect-nest)
; LLVM: Cannot interchange loops because they are not tightly nested.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @imperfect(ptr noalias nocapture noundef %A, ptr noalias nocapture noundef readonly %B, ptr noalias nocapture noundef writeonly %s) local_unnamed_addr #0 {
entry:
  br label %for.body

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv35 = phi i64 [ 0, %entry ], [ %indvars.iv.next36, %for.cond.cleanup4 ]
  %0 = trunc nuw nsw i64 %indvars.iv35 to i32
  %conv = uitofp nneg i32 %0 to double
  %arrayidx = getelementptr inbounds nuw double, ptr %s, i64 %indvars.iv35
  store double %conv, ptr %arrayidx, align 8, !tbaa !0
  br label %for.body5

for.cond.cleanup4:
  %indvars.iv.next36 = add nuw nsw i64 %indvars.iv35, 1
  %exitcond38.not = icmp eq i64 %indvars.iv.next36, 512
  br i1 %exitcond38.not, label %for.cond.cleanup, label %for.body

for.body5:
  %indvars.iv = phi i64 [ 0, %for.body ], [ %indvars.iv.next, %for.body5 ]
  %arrayidx9 = getelementptr inbounds nuw [512 x double], ptr %A, i64 %indvars.iv, i64 %indvars.iv35
  %1 = load double, ptr %arrayidx9, align 8, !tbaa !0
  %arrayidx13 = getelementptr inbounds nuw [512 x double], ptr %B, i64 %indvars.iv, i64 %indvars.iv35
  %2 = load double, ptr %arrayidx13, align 8, !tbaa !0
  %add = fadd double %1, %2
  store double %add, ptr %arrayidx9, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, 512
  br i1 %exitcond.not, label %for.cond.cleanup4, label %for.body5
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
