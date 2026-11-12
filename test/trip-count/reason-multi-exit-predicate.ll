; Two exits, both on an i32 IV compared after sext without no-wrap flags. SCEV has a
; predicated BTC ((m-bound) umin_seq (n-bound)), so the loop is countable with a runtime
; check: the predicate question is asked before the multiple-exits shape.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'multipred'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=needs-scev-predicate count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define void @multipred(ptr %a, i64 %n, i64 %m) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %i.next = add i32 %i, 1
  %w = sext i32 %i.next to i64
  %c1 = icmp slt i64 %w, %m
  br i1 %c1, label %latch, label %exit

latch:
  %i64 = sext i32 %i to i64
  %p = getelementptr inbounds float, ptr %a, i64 %i64
  store float 0.0, ptr %p, align 4
  %c2 = icmp slt i64 %w, %n
  br i1 %c2, label %loop, label %exit

exit:
  ret void
}
