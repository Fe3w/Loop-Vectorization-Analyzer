; A block name with spaces and quotes: the header string is JSON-escaped, and every
; line parses as JSON (checked with Python's json module).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-analyze \
; RUN:   -looplens-json=%t.jsonl -disable-output %s 2>/dev/null
; RUN: FileCheck %s < %t.jsonl
; RUN: %python -c 'import json,sys; [json.loads(l) for l in sys.stdin]; print("valid")' < %t.jsonl | FileCheck --check-prefix=PY %s
; PY: valid

; CHECK: "header":"%\"loop \\22head\\22\"",

define void @odd(i64 %n) {
entry:
  br label %"loop \22head\22"

"loop \22head\22":
  %i = phi i64 [ 0, %entry ], [ %i.next, %"loop \22head\22" ]
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %"loop \22head\22", label %exit

exit:
  ret void
}
