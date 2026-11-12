; The exit compare on a loaded value is wrapped in a not (xor true) and a freeze, as
; InstCombine output often is. Still a data-dependent icmp: exit-cond-not-affine.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'notcmp'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define void @notcmp(ptr %a) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %p = getelementptr inbounds i32, ptr %a, i64 %i
  %v = load i32, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp eq i32 %v, 0
  %nc = xor i1 %c, true
  %fc = freeze i1 %nc
  br i1 %fc, label %loop, label %exit

exit:
  ret void
}
