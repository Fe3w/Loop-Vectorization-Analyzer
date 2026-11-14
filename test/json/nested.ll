; Two loops, two lines in report order; the outer loop is not classified.
; IR copied from test/skeleton/nested.ll.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-analyze \
; RUN:   -looplens-json=%t.jsonl -disable-output %s 2>/dev/null
; RUN: FileCheck %s < %t.jsonl

; CHECK:      {"function":"nested","header":"%outer","depth":1,{{.*}}"innermost":false,"primary":null,"trip":{{.*}}}}{{$}}
; CHECK-NEXT: {"function":"nested","header":"%inner","depth":2,{{.*}}"innermost":true,"primary":"none",

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
