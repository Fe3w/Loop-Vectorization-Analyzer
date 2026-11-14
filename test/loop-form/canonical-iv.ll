; Canonical counted loop: one integer IV {0,+,1} that feeds the latch compare;
; all loop-form facts hold, and the loop is guarded by `0 < n` in the entry block.
; Source: for (int i = 0; i < n; i++) a[i] = 0;   (IR shared with trip-count/symbolic.ll)
; Oracle: opt -passes='print<scalar-evolution>' shows %i.04 --> {0,+,1}<nuw><nsw><%for.body>.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'sym'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%i.04 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @sym(ptr noundef %a, i32 noundef %n) {
entry:
  %cmp3 = icmp slt i32 0, %n
  br i1 %cmp3, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %i.04 = phi i32 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %idxprom = sext i32 %i.04 to i64
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom
  store float 0.000000e+00, ptr %arrayidx, align 4
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.04, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}
