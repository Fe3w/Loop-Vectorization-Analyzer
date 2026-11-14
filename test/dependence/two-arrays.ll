; Two independent dependence chains: b (Forward, safe) and a (Backward, blocks).
; Source: void twodeps(float *a, float *b, int n) { for (int i = 1; i < n; i++) { a[i] = a[i-1] + 1.0f; b[i] = b[i+1]; } }
; Fixture: scripts/make_fixture.sh --tbaa. Oracle: opt -passes='print<access-info>' (kinds, order);
; dist = address(dst) - address(src) in the same iteration, in bytes, checked by hand (float = 4 bytes).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'twodeps'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  cfg 
; CHECK-NEXT:  mem status=unsafe checks=1 max-safe-width=n/a report=UnsafeDep{{$}}
; CHECK-NEXT:  dep kind=Forward src=load:%arrayidx5 dst=store:%arrayidx7 dist=[-4]{{$}}
; CHECK-NEXT:  dep kind=Backward src=load:%arrayidx dst=store:%arrayidx2 dist=[4]{{$}}
; CHECK-NOT:   {{loop header=|dep kind=}}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @twodeps(ptr noundef %a, ptr noundef %b, i32 noundef %n) {
entry:
  %cmp8 = icmp slt i32 1, %n
  br i1 %cmp8, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.09 = phi i32 [ 1, %for.body.lr.ph ], [ %inc, %for.inc ]
  %sub = sub nsw i32 %i.09, 1
  %idxprom = sext i32 %sub to i64
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add = fadd float %0, 1.000000e+00
  %idxprom1 = sext i32 %i.09 to i64
  %arrayidx2 = getelementptr inbounds float, ptr %a, i64 %idxprom1
  store float %add, ptr %arrayidx2, align 4, !tbaa !0
  %add3 = add nsw i32 %i.09, 1
  %idxprom4 = sext i32 %add3 to i64
  %arrayidx5 = getelementptr inbounds float, ptr %b, i64 %idxprom4
  %1 = load float, ptr %arrayidx5, align 4, !tbaa !0
  %idxprom6 = sext i32 %i.09 to i64
  %arrayidx7 = getelementptr inbounds float, ptr %b, i64 %idxprom6
  store float %1, ptr %arrayidx7, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.09, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
