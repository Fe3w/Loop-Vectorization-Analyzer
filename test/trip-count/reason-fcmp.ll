; The exit condition is a floating-point compare: outside what SCEV models.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'fexit'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-icmp count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define void @fexit(ptr %a) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  %v = load float, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = fcmp une float %v, 0.0
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
