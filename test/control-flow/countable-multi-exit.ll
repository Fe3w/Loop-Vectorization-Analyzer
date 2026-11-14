; Two exits, both countable: the early exit compares the IV with a second bound m.
; LLVM 20 accepts this on legality (it reaches the cost model: VectorizationNotBeneficial),
; so several exiting blocks alone are NOT a blocker; only uncountable early exits are.
; Hand-written. Oracle: print<scalar-evolution> gives an exit count for both exits.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'twobound'
; CHECK:       cfg blocks=2 predicated=0 switches=0 exits=2 early-exit=countable{{$}}
; CHECK:       blocker primary=none rule=none secondary=none{{$}}

; CHECK-NOT:   evidence


define void @twobound(ptr %a, i64 %n, i64 %m) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %latch ]
  %c1 = icmp sge i64 %i, %m
  br i1 %c1, label %exit, label %latch

latch:
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c2 = icmp slt i64 %i.next, %n
  br i1 %c2, label %loop, label %exit

exit:
  ret void
}
