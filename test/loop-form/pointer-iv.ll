; Pointer IV: InductionDescriptor reports the step in BYTES (float* ++p -> 4).
; Source: for (float *p = a; p != e; ++p) *p = 0;
; Generated with the fixture recipe in DECISIONS.md (-g0), reduced.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'ptriv'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=<none>{{$}}
; CHECK-NEXT:  trip 
; CHECK-NEXT:  iv phi=%p.04 kind=ptr start=%a step=4 scev=[{%a,+,4}<nuw><%for.body>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @ptriv(ptr noundef %a, ptr noundef %e) {
entry:
  %cmp3 = icmp ne ptr %a, %e
  br i1 %cmp3, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  br label %for.body

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup

for.cond.cleanup:
  br label %for.end

for.body:
  %p.04 = phi ptr [ %a, %for.body.lr.ph ], [ %incdec.ptr, %for.inc ]
  store float 0.000000e+00, ptr %p.04, align 4
  br label %for.inc

for.inc:
  %incdec.ptr = getelementptr inbounds nuw float, ptr %p.04, i32 1
  %cmp = icmp ne ptr %incdec.ptr, %e
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge

for.end:
  ret void
}
