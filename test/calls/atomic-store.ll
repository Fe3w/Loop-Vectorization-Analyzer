; A relaxed atomic store is still an atomic access.
; Source: void atom(int *a, int n) { for (int i = 0; i < n; i++) __atomic_store_n(&a[i], 0, __ATOMIC_RELAXED); }
; Fixture: scripts/make_fixture.sh --o3 -- the IR LoopVectorize sees at -O3.
; LLVM 20 on this IR: CantVectorizeInstruction
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-LABEL: looplens: function 'atom'
; CHECK:       loop header=%for.body depth=1 
; CHECK:       nonsimple store:%arrayidx why=atomic{{$}}
; CHECK-NEXT:  blocker primary=call-or-unsafe-memop rule=mem-non-simple secondary=none{{$}}
; CHECK-NOT:   {{loop header=|call callee=|nonsimple }}

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @atom(ptr nocapture noundef writeonly %a, i32 noundef %n) local_unnamed_addr #0 {
entry:
  %cmp3 = icmp sgt i32 %n, 0
  br i1 %cmp3, label %for.body.preheader, label %for.cond.cleanup

for.body.preheader:
  %wide.trip.count = zext nneg i32 %n to i64
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.preheader ], [ %indvars.iv.next, %for.body ]
  %arrayidx = getelementptr inbounds nuw i32, ptr %a, i64 %indvars.iv
  store atomic i32 0, ptr %arrayidx monotonic, align 4
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

attributes #0 = { nofree norecurse nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
