; Overlap test for the second promotion shape: the load of the accumulator is still
; inside the loop (clang -O3 usually hoists it, so overlap.c only covers the
; "store only" shape). Hand-written. acc(A, r, 8, 16) adds A[8..23] into A[r]; main
; calls it with r before, at the start of, inside, at the end of, just past and far
; from that range. The program is run under lli unrepaired and repaired; both must
; print the same exact values (the unrepaired run is the reference).
;
; RUN: lli %s | FileCheck %s
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes='looplens-repair,verify' -S %s -o %t.ll
; RUN: FileCheck --check-prefix=IR %s < %t.ll
; RUN: lli %t.ll | FileCheck %s
; Mutation: without the runtime check the overlapping calls go wrong.
; RUN: sed 's/br i1 %lr.conflict, label/br i1 false, label/' %t.ll | lli | not FileCheck %s
; IR: %lr.conflict =
; IR: %lr.acc = phi double
; CHECK:      r=7 acc=0x1.fep+5 s=0x1.1bp+9
; CHECK-NEXT: r=8 acc=0x1p+6 s=0x1.1bp+9
; CHECK-NEXT: r=15 acc=0x1.54p+6 s=0x1.24ap+9
; CHECK-NEXT: r=23 acc=0x1.fp+6 s=0x1.372p+9
; CHECK-NEXT: r=24 acc=0x1.1p+6 s=0x1.1bp+9
; CHECK-NEXT: r=40 acc=0x1.2p+6 s=0x1.1bp+9

@.fmt = private unnamed_addr constant [19 x i8] c"r=%ld acc=%a s=%a\0A\00"
@A = internal global [64 x double] zeroinitializer

declare i32 @printf(ptr, ...)

; acc(A, r, c, n): for k < n: A[r] = A[r] + A[c + k]   (load of A[r] inside the loop)
define internal void @acc(ptr %A, i64 %r, i64 %c, i64 %n) noinline {
entry:
  %p = getelementptr inbounds double, ptr %A, i64 %r
  br label %loop

loop:
  %k = phi i64 [ 0, %entry ], [ %k.next, %loop ]
  %i = add nsw i64 %c, %k
  %q = getelementptr inbounds double, ptr %A, i64 %i
  %x = load double, ptr %q, align 8
  %a = load double, ptr %p, align 8
  %s = fadd double %a, %x
  store double %s, ptr %p, align 8
  %k.next = add nuw nsw i64 %k, 1
  %done = icmp eq i64 %k.next, %n
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

define internal void @run(i64 %r) noinline {
entry:
  br label %init

init:
  %i = phi i64 [ 0, %entry ], [ %i.next, %init ]
  %e = getelementptr inbounds [64 x double], ptr @A, i64 0, i64 %i
  %f = sitofp i64 %i to double
  %v = fmul double %f, 2.500000e-01
  store double %v, ptr %e, align 8
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp eq i64 %i.next, 64
  br i1 %c, label %go, label %init

go:
  call void @acc(ptr @A, i64 %r, i64 8, i64 16)
  br label %sum

sum:
  %j = phi i64 [ 0, %go ], [ %j.next, %sum ]
  %t = phi double [ 0.000000e+00, %go ], [ %t.next, %sum ]
  %g = getelementptr inbounds [64 x double], ptr @A, i64 0, i64 %j
  %w = load double, ptr %g, align 8
  %t.next = fadd double %t, %w
  %j.next = add nuw nsw i64 %j, 1
  %d = icmp eq i64 %j.next, 64
  br i1 %d, label %out, label %sum

out:
  %pr = getelementptr inbounds [64 x double], ptr @A, i64 0, i64 %r
  %ar = load double, ptr %pr, align 8
  %z = call i32 (ptr, ...) @printf(ptr @.fmt, i64 %r, double %ar, double %t.next)
  ret void
}

define i32 @main() {
entry:
  call void @run(i64 7)
  call void @run(i64 8)
  call void @run(i64 15)
  call void @run(i64 23)
  call void @run(i64 24)
  call void @run(i64 40)
  ret i32 0
}
