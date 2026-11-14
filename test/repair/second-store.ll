; Not a candidate: besides the invariant accumulation (*s) the loop also stores to
; a[i], so promotion alone would not remove every dependence. Left unchanged.
; Hand-written.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-repair -S %s \
; RUN:   | FileCheck --implicit-check-not=lr.conflict %s
; CHECK: define void @two(

define void @two(ptr %a, ptr %s, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %p = getelementptr inbounds double, ptr %a, i64 %i
  %x = load double, ptr %p, align 8
  %acc = load double, ptr %s, align 8
  %sum = fadd fast double %acc, %x
  store double %sum, ptr %s, align 8
  store double 0.0, ptr %p, align 8
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
