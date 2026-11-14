; No preheader, but both outside predecessors bring the same start value (0), so the
; header phi is still an add-recurrence and SCEV computes the trip count: a missing
; preheader is not by itself a reason for an unknown trip count.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nopre_same'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + (1 smax %n))<nsw>] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; The header phi IS an add-recurrence here; asking InductionDescriptor without a
; preheader crashes LLVM 20, so LoopLens does not ask (regression guard, S04).
; CHECK-NEXT:  iv <no-preheader>{{$}}
; CHECK-NEXT:  form simplify=no rotated=yes lcssa=yes exiting=single innermost=yes guarded=no{{$}}
; CHECK-NOT:   loop header=

define void @nopre_same(ptr %a, i64 %n, i1 %b) {
entry:
  br i1 %b, label %x, label %loop

x:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ 0, %x ], [ %i.next, %loop ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
