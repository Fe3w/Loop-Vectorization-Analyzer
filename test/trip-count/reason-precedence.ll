; Exit conditions that mix an fcmp and an icmp, in both operand orders. All leaves are
; inspected; precedence is exit-cond-not-affine > exit-cond-not-icmp, independent of order.
; Hand-written. Oracle: opt -passes='print<scalar-evolution>' on this file.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'mixed_fi'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

; CHECK-LABEL: looplens: function 'mixed_if'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-affine count=none btc=[***COULDNOTCOMPUTE***] max-btc=[***COULDNOTCOMPUTE***] symbolic-max-btc=[***COULDNOTCOMPUTE***]{{$}}
; CHECK-NOT:   loop header=

; CHECK-LABEL: looplens: function 'affine_f'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-icmp count=none btc=[***COULDNOTCOMPUTE***] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NOT:   loop header=

; CHECK-LABEL: looplens: function 'f_affine'
; CHECK-NEXT:  loop header=%loop depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip kind=unknown reason=exit-cond-not-icmp count=none btc=[***COULDNOTCOMPUTE***] max-btc=[9223372036854775806] symbolic-max-btc=[(-1 + (1 smax %n))<nsw>]{{$}}
; CHECK-NOT:   loop header=

define void @mixed_fi(ptr %f, ptr %a) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %pf = getelementptr inbounds float, ptr %f, i64 %i
  %vf = load float, ptr %pf, align 4
  %pa = getelementptr inbounds i32, ptr %a, i64 %i
  %va = load i32, ptr %pa, align 4
  %i.next = add nuw nsw i64 %i, 1
  %fc = fcmp une float %vf, 0.0
  %ic = icmp ne i32 %va, 0
  %c = select i1 %fc, i1 %ic, i1 false
  br i1 %c, label %loop, label %exit

exit:
  ret void
}

define void @mixed_if(ptr %f, ptr %a) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %pf = getelementptr inbounds float, ptr %f, i64 %i
  %vf = load float, ptr %pf, align 4
  %pa = getelementptr inbounds i32, ptr %a, i64 %i
  %va = load i32, ptr %pa, align 4
  %i.next = add nuw nsw i64 %i, 1
  %fc = fcmp une float %vf, 0.0
  %ic = icmp ne i32 %va, 0
  %c = select i1 %ic, i1 %fc, i1 false
  br i1 %c, label %loop, label %exit

exit:
  ret void
}

define void @affine_f(ptr %f, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %pf = getelementptr inbounds float, ptr %f, i64 %i
  %vf = load float, ptr %pf, align 4
  %i.next = add nuw nsw i64 %i, 1
  %fc = fcmp une float %vf, 0.0
  %ic = icmp slt i64 %i.next, %n
  %c = select i1 %fc, i1 %ic, i1 false
  br i1 %c, label %loop, label %exit

exit:
  ret void
}

define void @f_affine(ptr %f, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
  %pf = getelementptr inbounds float, ptr %f, i64 %i
  %vf = load float, ptr %pf, align 4
  %i.next = add nuw nsw i64 %i, 1
  %fc = fcmp une float %vf, 0.0
  %ic = icmp slt i64 %i.next, %n
  %c = select i1 %ic, i1 %fc, i1 false
  br i1 %c, label %loop, label %exit

exit:
  ret void
}
