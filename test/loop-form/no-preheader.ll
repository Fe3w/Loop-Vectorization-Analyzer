; No preheader (two predecessors outside the loop): not in simplify form, and
; InductionDescriptor is not asked at all -- in LLVM 20 isInductionPHI dereferences the
; preheader without a check (crash; see trip-count/no-preheader-same-start.ll, where the
; phi IS an add-recurrence). Hand-written; IR shared with trip-count/unknown-no-preheader.ll.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nopre'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv <no-preheader>{{$}}
; CHECK-NEXT:  form simplify=no rotated=yes lcssa=yes exiting=single innermost=yes guarded=no{{$}}
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
