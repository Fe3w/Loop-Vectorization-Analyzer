; Not rotated: the header tests the condition and the latch (%body) branches back
; unconditionally, so the latch is not the exiting block (Loop::isRotatedForm is false)
; and getInductionVariable finds no latch compare.
; Hand-written; must not be run through loop-rotate (that would rotate it).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'notrot'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%i kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%loop>] controls-exit=no{{$}}
; CHECK-NEXT:  form simplify=yes rotated=no lcssa=yes exiting=single innermost=yes guarded=no{{$}}
; CHECK-NOT:   loop header=

define void @notrot(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %body ]
  %c = icmp slt i64 %i, %n
  br i1 %c, label %body, label %exit

body:
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  br label %loop

exit:
  ret void
}
