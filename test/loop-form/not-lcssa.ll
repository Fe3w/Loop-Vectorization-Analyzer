; Not in LCSSA form: %i.next is used after the loop without an LCSSA phi.
; Hand-written; must not be run through lcssa (that would add the phi).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nolcssa'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%i kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%loop>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=no exiting=single innermost=yes guarded=no{{$}}
; CHECK-NOT:   loop header=

define i64 @nolcssa(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret i64 %i.next
}
