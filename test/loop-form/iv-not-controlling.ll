; An IV exists, but the latch compares a LOADED value, so Loop::getInductionVariable
; returns null: controls-exit=no. Single-block loop (latch == header) counts as rotated;
; no guard (entry branches unconditionally into the loop).
; Source: int i = 0; while (a[i] != 0) i++;   (IR shared with trip-count/unknown-data-exit.ll)
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'datadep'
; CHECK-NEXT:  loop header=%while.cond depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%i.0 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%while.cond>] controls-exit=no{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=no{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define i32 @datadep(ptr noundef %a) {
entry:
  br label %while.cond

while.cond:
  %i.0 = phi i32 [ 0, %entry ], [ %inc, %while.cond ]
  %idxprom = sext i32 %i.0 to i64
  %arrayidx = getelementptr inbounds i32, ptr %a, i64 %idxprom
  %0 = load i32, ptr %arrayidx, align 4
  %cmp = icmp ne i32 %0, 0
  %inc = add nsw i32 %i.0, 1
  br i1 %cmp, label %while.cond, label %while.end

while.end:
  %i.0.lcssa = phi i32 [ %i.0, %while.cond ]
  ret i32 %i.0.lcssa
}
