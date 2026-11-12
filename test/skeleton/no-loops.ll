; A function with no loops prints its header line and nothing else.
; Also checks that declarations (@ext) are skipped entirely.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK:     looplens: function 'straight'
; CHECK-NOT: loop header=
; CHECK-NOT: function 'ext'

declare i32 @ext(i32)

define i32 @straight(i32 %x) {
entry:
  %c = icmp sgt i32 %x, 0
  br i1 %c, label %pos, label %done

pos:
  %y = call i32 @ext(i32 %x)
  br label %done

done:
  %r = phi i32 [ %y, %pos ], [ 0, %entry ]
  ret i32 %r
}
