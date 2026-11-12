; The exit block is also reached from outside the loop (no dedicated exit, so not
; loop-simplify form), and the loop leaves on a loaded value. The reason must name the
; data-dependent exit, not the shape: LoopVectorize sees this loop after loop-simplify.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'shared'
; CHECK-NEXT:  loop header=loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define i32 @shared(ptr %a, i1 %b) {
entry:
  br i1 %b, label %exit, label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %p = getelementptr inbounds i32, ptr %a, i64 %i
  %v = load i32, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp ne i32 %v, 0
  br i1 %c, label %loop, label %exit

exit:
  %r = phi i32 [ 0, %entry ], [ 1, %loop ]
  ret i32 %r
}
