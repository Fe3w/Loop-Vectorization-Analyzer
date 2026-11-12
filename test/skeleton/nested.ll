; Two-deep loop nest: outer is reported before inner, with correct depths.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nested'
; CHECK-NEXT:  loop header=outer depth=1 loc=<none>{{$}}
; CHECK:       loop header=inner depth=2 loc=<none>{{$}}
; CHECK-NOT:   loop header=

define void @nested(ptr %a, i64 %n) {
entry:
  br label %outer

outer:
  %i = phi i64 [ 0, %entry ], [ %i.next, %outer.latch ]
  br label %inner

inner:
  %j = phi i64 [ 0, %outer ], [ %j.next, %inner ]
  %j.next = add nuw nsw i64 %j, 1
  %c1 = icmp slt i64 %j.next, %n
  br i1 %c1, label %inner, label %outer.latch

outer.latch:
  %i.next = add nuw nsw i64 %i, 1
  %c2 = icmp slt i64 %i.next, %n
  br i1 %c2, label %outer, label %exit

exit:
  ret void
}
