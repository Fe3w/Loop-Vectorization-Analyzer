; Two top-level loops one after another: both depth 1, in program order.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'siblings'
; CHECK-NEXT:  loop header=first depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + (1 smax %n))<nsw>] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NEXT:  loop header=second depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + (1 smax %n))<nsw>] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NOT:   loop header=

define void @siblings(ptr %a, i64 %n) {
entry:
  br label %first

first:
  %i = phi i64 [ 0, %entry ], [ %i.next, %first ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c1 = icmp slt i64 %i.next, %n
  br i1 %c1, label %first, label %mid

mid:
  br label %second

second:
  %j = phi i64 [ 0, %mid ], [ %j.next, %second ]
  %q = getelementptr inbounds float, ptr %a, i64 %j
  store float 1.0, ptr %q, align 4
  %j.next = add nuw nsw i64 %j, 1
  %c2 = icmp slt i64 %j.next, %n
  br i1 %c2, label %second, label %exit

exit:
  ret void
}
