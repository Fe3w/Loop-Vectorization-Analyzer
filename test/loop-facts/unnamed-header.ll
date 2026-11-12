; An unnamed header block is printed as its slot number (%1), the same form
; `opt -passes='print<loops>'` uses, instead of an empty name.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'u'
; CHECK-NEXT:  loop header=%1 depth=1 loc=<none>{{$}}
; CHECK-NOT:   loop header=

define void @u(i64 %n) {
  br label %1

1:
  %i = phi i64 [ 0, %0 ], [ %i.next, %1 ]
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %1, label %2

2:
  ret void
}
