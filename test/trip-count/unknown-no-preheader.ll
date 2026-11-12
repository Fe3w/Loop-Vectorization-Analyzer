; Unknown trip count because the loop has no preheader (two predecessors outside
; the loop): ScalarEvolution builds no add-recurrence, so nothing is computable.
; Hand-written; must not be run through loop-simplify (that would add a preheader).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nopre'
; CHECK-NEXT:  loop header=loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=not-simplify-form count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

define void @nopre(ptr %a, i64 %n, i1 %b) {
entry:
  br i1 %b, label %x, label %loop

x:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ 1, %x ], [ %i.next, %loop ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
