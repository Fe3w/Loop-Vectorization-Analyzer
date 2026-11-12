; while (i < n && a[i] != 0): one exiting block whose condition is a select-based
; logical and. The loaded operand inside the and makes the exit data-dependent; the
; i < n half still gives a symbolic max.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'land'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NOT:   loop header=

define void @land(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %i.next = add nuw nsw i64 %i, 1
  %p = getelementptr inbounds i32, ptr %a, i64 %i.next
  %v = load i32, ptr %p, align 4
  %c1 = icmp slt i64 %i.next, %n
  %c2 = icmp ne i32 %v, 0
  %c = select i1 %c1, i1 %c2, i1 false
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
