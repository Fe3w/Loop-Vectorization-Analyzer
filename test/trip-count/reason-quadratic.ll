; The exit compares j, which grows by i every iteration: SCEV {0,+,0,+,1} style
; (second-order) add-recurrence, an addrec of this loop but not affine.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'quadratic'
; CHECK-NEXT:  loop header=loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define void @quadratic(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %j = phi i64 [ 0, %entry ], [ %j.next, %loop ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %j.next = add i64 %j, %i
  %c = icmp ult i64 %j.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
