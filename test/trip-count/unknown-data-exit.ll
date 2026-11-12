; Unknown trip count: the exit compares a loaded value (LoopVectorize: 'could not determine number of loop iterations').
;
; Source (datadep.c):
;    1 int datadep(int *a) {
;    2   int i = 0;
;    3   while (a[i] != 0)
;    4     i++;
;    5   return i;
;    6 }
; Generated with the fixture recipe in DECISIONS.md (-g0: location not under test), reduced.
; Oracle: opt -passes='print<scalar-evolution>' on this file (constants print as 'iN K' there).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'datadep'
; CHECK-NEXT:  loop header=%while.cond depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
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
