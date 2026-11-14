; Two-deep loop nest: outer is reported before inner, with correct depths.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'nested'
; CHECK-NEXT:  loop header=%outer depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + (1 smax %n))<nsw>] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NEXT:  iv phi=%i kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%outer>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=no guarded=no{{$}}
; CHECK-NEXT:  mem <not-innermost>{{$}}
; CHECK-NEXT:  blocker <not-innermost>{{$}}
; CHECK-NEXT:  loop header=%inner depth=2 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + (1 smax %n))<nsw>] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NEXT:  iv phi=%j kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%inner>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=no{{$}}
; CHECK-NEXT:  cfg blocks=1 predicated=0 switches=0 exits=1 early-exit=none{{$}}
; CHECK-NEXT:  mem status=safe checks=0 max-safe-width=any report=none{{$}}
; CHECK-NEXT:  dep <none>{{$}}
; CHECK-NEXT:  blocker primary=none rule=none secondary=none{{$}}
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
