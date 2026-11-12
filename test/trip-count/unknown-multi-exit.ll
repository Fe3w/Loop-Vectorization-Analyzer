; Unknown exact trip count with two exits (early return), but the symbolic max is known from the i < n exit.
;
; Source (brk.c):
;    1 int brk(int *a, int n, int k) {
;    2   for (int i = 0; i < n; i++)
;    3     if (a[i] == k)
;    4       return i;
;    5   return -1;
;    6 }
; Generated with the fixture recipe in DECISIONS.md (-g0: location not under test), reduced.
; Oracle: opt -passes='print<scalar-evolution>' on this file (constants print as 'iN K' there).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'brk'
; CHECK-NEXT:  loop header=for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=multiple-exits count=none btc=[***COULDNOTCOMPUTE***] max-btc=[2147483646] symbolic-max-btc=[(-1 + %n)]{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define i32 @brk(ptr noundef %a, i32 noundef %n, i32 noundef %k) {
entry:
  %cmp6 = icmp slt i32 0, %n
  br i1 %cmp6, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  %split = phi i32 [ %inc, %for.inc ]
  br label %for.cond.cleanup

for.cond.cleanup:
  %i.0.lcssa = phi i32 [ %split, %for.cond.for.cond.cleanup_crit_edge ], [ 0, %entry ]
  br label %cleanup

for.body:
  %i.07 = phi i32 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %idxprom = sext i32 %i.07 to i64
  %arrayidx = getelementptr inbounds i32, ptr %a, i64 %idxprom
  %0 = load i32, ptr %arrayidx, align 4
  %cmp1 = icmp eq i32 %0, %k
  br i1 %cmp1, label %if.then, label %if.end

if.then:
  %i.0.lcssa4 = phi i32 [ %i.07, %for.body ]
  br label %cleanup

if.end:
  br label %for.inc

for.inc:
  %inc = add nsw i32 %i.07, 1
  %cmp = icmp slt i32 %inc, %n
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

cleanup:
  %i.05 = phi i32 [ %i.0.lcssa4, %if.then ], [ %i.0.lcssa, %for.cond.cleanup ]
  %cleanup.dest.slot.0 = phi i32 [ 1, %if.then ], [ 2, %for.cond.cleanup ]
  switch i32 %cleanup.dest.slot.0, label %unreachable [
    i32 2, label %for.end
    i32 1, label %return
  ]

for.end:
  br label %return

return:
  %retval.1 = phi i32 [ %i.05, %cleanup ], [ -1, %for.end ]
  ret i32 %retval.1

unreachable:
  unreachable
}
