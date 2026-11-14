; Differential test: run the program with and without the repair under lli. Call 1
; does not overlap (fast copy), call 2 accumulates into A[3] while reading A[0..7]
; (the runtime check must send it to the original loop). Expected values come from
; the same C program built with clang -O0 (scratchpad run.c / run_ref).
;
; RUN: lli %s | FileCheck %s
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes='looplens-repair,verify' -S %s -o %t.ll
; RUN: lli %t.ll | FileCheck %s
; RUN: FileCheck --check-prefix=IR %s < %t.ll
; CHECK: t=0 r=-40.500000 sum=3426.000000
; CHECK: t=1 r=-65.562500 sum=4957.750000
; IR: %lr.conflict

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

@.str = private unnamed_addr constant [22 x i8] c"t=%d r=%.6f sum=%.6f\0A\00", align 1

define void @acc(ptr nocapture noundef %A, i32 noundef %n, i32 noundef %r, i32 noundef %c) local_unnamed_addr #0 {
entry:
  %cmp10 = icmp sgt i32 %n, 0
  br i1 %cmp10, label %for.body.lr.ph, label %for.cond.cleanup

for.body.lr.ph:
  %idxprom3 = sext i32 %r to i64
  %arrayidx4 = getelementptr inbounds double, ptr %A, i64 %idxprom3
  %arrayidx4.promoted = load double, ptr %arrayidx4, align 8, !tbaa !0
  %0 = sext i32 %c to i64
  %wide.trip.count = zext nneg i32 %n to i64
  %invariant.gep = getelementptr double, ptr %A, i64 %0
  br label %for.body

for.cond.cleanup.loopexit:
  br label %for.cond.cleanup

for.cond.cleanup:
  ret void

for.body:
  %indvars.iv = phi i64 [ 0, %for.body.lr.ph ], [ %indvars.iv.next, %for.body ]
  %1 = phi double [ %arrayidx4.promoted, %for.body.lr.ph ], [ %4, %for.body ]
  %gep = getelementptr double, ptr %invariant.gep, i64 %indvars.iv
  %2 = load double, ptr %gep, align 8, !tbaa !0
  %arrayidx2 = getelementptr inbounds nuw double, ptr %A, i64 %indvars.iv
  %3 = load double, ptr %arrayidx2, align 8, !tbaa !0
  %neg = fneg double %2
  %4 = tail call double @llvm.fmuladd.f64(double %neg, double %3, double %1)
  store double %4, ptr %arrayidx4, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, %wide.trip.count
  br i1 %exitcond.not, label %for.cond.cleanup.loopexit, label %for.body
}

declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #1

declare double @llvm.fmuladd.f64(double, double, double) #2

declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #1

define noundef i32 @main() local_unnamed_addr #3 {
entry:
  %A = alloca [64 x double], align 16
  call void @llvm.lifetime.start.p0(i64 512, ptr nonnull %A) #5
  %arrayidx22 = getelementptr inbounds nuw i8, ptr %A, i64 320
  br label %for.body4

for.body4:
  %indvars.iv = phi i64 [ 0, %entry ], [ %indvars.iv.next, %for.body4 ]
  %rem.lhs.trunc = trunc i64 %indvars.iv to i8
  %rem38 = urem i8 %rem.lhs.trunc, 7
  %conv = uitofp nneg i8 %rem38 to double
  %0 = tail call double @llvm.fmuladd.f64(double %conv, double 5.000000e-01, double 1.000000e+00)
  %arrayidx = getelementptr inbounds nuw [64 x double], ptr %A, i64 0, i64 %indvars.iv
  store double %0, ptr %arrayidx, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, 64
  br i1 %exitcond.not, label %if.end, label %for.body4

if.end:
  call void @acc(ptr noundef nonnull %A, i32 noundef 8, i32 noundef 40, i32 noundef 16)
  br label %for.body13

for.cond.cleanup12:
  %1 = load double, ptr %arrayidx22, align 16
  %call = tail call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str, i32 noundef 0, double noundef %1, double noundef %9)
  br label %for.body4.1

for.body4.1:
  %indvars.iv.1 = phi i64 [ 0, %for.cond.cleanup12 ], [ %indvars.iv.next.1, %for.body4.1 ]
  %rem.lhs.trunc.1 = trunc i64 %indvars.iv.1 to i8
  %rem38.1 = urem i8 %rem.lhs.trunc.1, 7
  %conv.1 = uitofp nneg i8 %rem38.1 to double
  %2 = tail call double @llvm.fmuladd.f64(double %conv.1, double 5.000000e-01, double 1.000000e+00)
  %arrayidx.1 = getelementptr inbounds nuw [64 x double], ptr %A, i64 0, i64 %indvars.iv.1
  store double %2, ptr %arrayidx.1, align 8, !tbaa !0
  %indvars.iv.next.1 = add nuw nsw i64 %indvars.iv.1, 1
  %exitcond.1.not = icmp eq i64 %indvars.iv.next.1, 64
  br i1 %exitcond.1.not, label %if.end.1, label %for.body4.1

if.end.1:
  call void @acc(ptr noundef nonnull %A, i32 noundef 8, i32 noundef 3, i32 noundef 0)
  br label %for.body13.1

for.body13.1:
  %indvars.iv44.1 = phi i64 [ 0, %if.end.1 ], [ %indvars.iv.next45.1, %for.body13.1 ]
  %s.040.1 = phi double [ 0.000000e+00, %if.end.1 ], [ %5, %for.body13.1 ]
  %arrayidx15.1 = getelementptr inbounds nuw [64 x double], ptr %A, i64 0, i64 %indvars.iv44.1
  %3 = load double, ptr %arrayidx15.1, align 8, !tbaa !0
  %indvars.iv.next45.1 = add nuw nsw i64 %indvars.iv44.1, 1
  %4 = trunc nuw nsw i64 %indvars.iv.next45.1 to i32
  %conv16.1 = uitofp nneg i32 %4 to double
  %5 = tail call double @llvm.fmuladd.f64(double %3, double %conv16.1, double %s.040.1)
  %exitcond47.1.not = icmp eq i64 %indvars.iv.next45.1, 64
  br i1 %exitcond47.1.not, label %for.cond.cleanup12.1, label %for.body13.1

for.cond.cleanup12.1:
  %arrayidx23 = getelementptr inbounds nuw i8, ptr %A, i64 24
  %6 = load double, ptr %arrayidx23, align 8
  %call.1 = tail call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str, i32 noundef 1, double noundef %6, double noundef %5)
  call void @llvm.lifetime.end.p0(i64 512, ptr nonnull %A) #5
  ret i32 0

for.body13:
  %indvars.iv44 = phi i64 [ 0, %if.end ], [ %indvars.iv.next45, %for.body13 ]
  %s.040 = phi double [ 0.000000e+00, %if.end ], [ %9, %for.body13 ]
  %arrayidx15 = getelementptr inbounds nuw [64 x double], ptr %A, i64 0, i64 %indvars.iv44
  %7 = load double, ptr %arrayidx15, align 8, !tbaa !0
  %indvars.iv.next45 = add nuw nsw i64 %indvars.iv44, 1
  %8 = trunc nuw nsw i64 %indvars.iv.next45 to i32
  %conv16 = uitofp nneg i32 %8 to double
  %9 = tail call double @llvm.fmuladd.f64(double %7, double %conv16, double %s.040)
  %exitcond47.not = icmp eq i64 %indvars.iv.next45, 64
  br i1 %exitcond47.not, label %for.cond.cleanup12, label %for.body13
}

declare noundef i32 @printf(ptr nocapture noundef readonly, ...) local_unnamed_addr #4

attributes #0 = { nofree noinline norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #2 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #3 = { nofree nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #4 = { nofree nounwind "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #5 = { nounwind }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
