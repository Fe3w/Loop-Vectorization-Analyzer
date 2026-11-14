; -looplens-json=<path with %p>: %p becomes the process ID, so parallel compiler
; processes (or LTO backends) each write their own JSON Lines file instead of
; interleaving lines in one. (lit: %%p is a literal %p.)
; RUN: rm -rf %t && mkdir -p %t
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-analyze \
; RUN:   -looplens-json=%t/out.%%p.jsonl -disable-output %s 2>/dev/null
; RUN: ls %t | FileCheck --check-prefix=LS %s
; RUN: cat %t/out.*.jsonl | FileCheck %s
; LS: {{^out\.[0-9]+\.jsonl$}}
; LS-NOT: %p
; CHECK: {"function":"f1",

define void @f1(i64 %n) {
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
