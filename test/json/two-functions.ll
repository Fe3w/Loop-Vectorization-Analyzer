; Two functions in one run: the file is opened once and both loops are appended.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-analyze \
; RUN:   -looplens-json=%t.jsonl -disable-output %s 2>/dev/null
; RUN: FileCheck %s < %t.jsonl

; CHECK:      {"function":"f1",
; CHECK-NEXT: {"function":"f2",
; CHECK-NOT:  "function":

define void @f1(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}

define void @f2(ptr %a, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
