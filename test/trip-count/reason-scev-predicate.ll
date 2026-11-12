; i32 IV without no-wrap flags, compared after sext: the exact count is unknown, but
; SCEV can compute it under a no-wrap predicate (print<scalar-evolution> shows a
; 'Predicated backedge-taken count'), i.e. with a runtime check LoopVectorize can add.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'castiv'
; CHECK-NEXT:  loop header=loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=needs-scev-predicate count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define void @castiv(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %loop ]
  %i64 = sext i32 %i to i64
  %p = getelementptr inbounds float, ptr %a, i64 %i64
  store float 0.0, ptr %p, align 4
  %i.next = add i32 %i, 1
  %w = sext i32 %i.next to i64
  %c = icmp slt i64 %w, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
