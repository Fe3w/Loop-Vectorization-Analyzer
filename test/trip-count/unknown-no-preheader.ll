; Unknown trip count: the two predecessors outside the loop bring DIFFERENT start
; values (0 and 1), so the header phi has no single start and is not an
; add-recurrence; %i.next in the exit compare is then not affine. (A missing
; preheader alone is fine: see no-preheader-same-start.ll.)
; Hand-written; must not be run through loop-simplify (that would add a preheader).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nopre'
; CHECK-NEXT:  loop header=loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
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
