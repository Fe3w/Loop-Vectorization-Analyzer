; Symbolic trip count: BTC is a SCEV in n; constant max from the i32 range of n.
;
; Source (sym.c):
;    1 void sym(float *a, int n) {
;    2   for (int i = 0; i < n; i++)
;    3     a[i] = 0;
;    4 }
; Generated with the fixture recipe in DECISIONS.md (-g0: location not under test), reduced.
; Oracle: opt -passes='print<scalar-evolution>' on this file (constants print as 'iN K' there).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'sym'
; CHECK-NEXT:  loop header=for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + %n)] max-btc=[2147483646] symbolic-max-btc=[(-1 + %n)]{{$}}
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
