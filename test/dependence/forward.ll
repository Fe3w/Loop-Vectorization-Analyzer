; a[i] = a[i+1] + 1: the read runs ahead of the write (Forward), safe.
; Source: void fwd(float *a, int n) { for (int i = 0; i < n; i++) a[i] = a[i+1] + 1.0f; }
; Fixture: scripts/make_fixture.sh --tbaa. Oracle: opt -passes='print<access-info>' (kinds, order);
; dist = address(dst) - address(src) in the same iteration, in bytes, checked by hand (float = 4 bytes).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'fwd'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv 
; CHECK-NEXT:  form 
; CHECK-NEXT:  cfg 
; CHECK-NEXT:  mem status=safe checks=0 max-safe-width=any report=none{{$}}
; CHECK-NEXT:  dep kind=Forward src=load:%arrayidx dst=store:%arrayidx3 dist=[-4]{{$}}
; CHECK-NOT:   {{loop header=|dep kind=}}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @fwd(ptr noundef %a, i32 noundef %n) {
entry:
  %cmp5 = icmp slt i32 0, %n
  br i1 %cmp5, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.06 = phi i32 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %add = add nsw i32 %i.06, 1
  %idxprom = sext i32 %add to i64
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom
  %0 = load float, ptr %arrayidx, align 4, !tbaa !0
  %add1 = fadd float %0, 1.000000e+00
  %idxprom2 = sext i32 %i.06 to i64
  %arrayidx3 = getelementptr inbounds float, ptr %a, i64 %idxprom2
  store float %add1, ptr %arrayidx3, align 4, !tbaa !0
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.06, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}

!0 = !{!1, !1, i64 0}
!1 = !{!"float", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
