target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

@buf = internal global [4160 x double] zeroinitializer, align 16
@.str = private unnamed_addr constant [15 x i8] c"checksum=%.1f\0A\00", align 1

define void @colsum(ptr nocapture noundef %A, ptr nocapture noundef readonly %B) local_unnamed_addr #0 {
entry:
  br label %for.cond1.preheader

for.cond1.preheader:
  %indvars.iv30 = phi i64 [ 0, %entry ], [ %indvars.iv.next31, %for.cond.cleanup3 ]
  br label %for.body4

for.cond.cleanup:
  ret void

for.cond.cleanup3:
  %indvars.iv.next31 = add nuw nsw i64 %indvars.iv30, 1
  %exitcond33.not = icmp eq i64 %indvars.iv.next31, 64
  br i1 %exitcond33.not, label %for.cond.cleanup, label %for.cond1.preheader

for.body4:
  %indvars.iv = phi i64 [ 0, %for.cond1.preheader ], [ %indvars.iv.next, %for.body4 ]
  %arrayidx6 = getelementptr inbounds nuw [64 x double], ptr %A, i64 %indvars.iv, i64 %indvars.iv30
  %0 = load double, ptr %arrayidx6, align 8, !tbaa !0
  %arrayidx10 = getelementptr inbounds nuw [64 x double], ptr %B, i64 %indvars.iv, i64 %indvars.iv30
  %1 = load double, ptr %arrayidx10, align 8, !tbaa !0
  %add = fadd double %0, %1
  store double %add, ptr %arrayidx6, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, 64
  br i1 %exitcond.not, label %for.cond.cleanup3, label %for.body4
}

define noundef i32 @main() local_unnamed_addr #1 {
entry:
  br label %for.body

for.cond.cleanup:
  tail call void @colsum(ptr noundef nonnull @buf, ptr noundef nonnull getelementptr inbounds nuw (i8, ptr @buf, i64 504))
  br label %for.body6

for.body:
  %indvars.iv = phi i64 [ 0, %entry ], [ %indvars.iv.next, %for.body ]
  %rem.lhs.trunc = trunc i64 %indvars.iv to i16
  %rem21 = urem i16 %rem.lhs.trunc, 7
  %conv = uitofp nneg i16 %rem21 to double
  %arrayidx = getelementptr inbounds nuw [4160 x double], ptr @buf, i64 0, i64 %indvars.iv
  store double %conv, ptr %arrayidx, align 8, !tbaa !0
  %indvars.iv.next = add nuw nsw i64 %indvars.iv, 1
  %exitcond.not = icmp eq i64 %indvars.iv.next, 4160
  br i1 %exitcond.not, label %for.cond.cleanup, label %for.body

for.cond.cleanup5:
  %call = tail call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str, double noundef %1)
  ret i32 0

for.body6:
  %indvars.iv27 = phi i64 [ 0, %for.cond.cleanup ], [ %indvars.iv.next28, %for.body6 ]
  %s.024 = phi double [ 0.000000e+00, %for.cond.cleanup ], [ %1, %for.body6 ]
  %arrayidx8 = getelementptr inbounds nuw [4160 x double], ptr @buf, i64 0, i64 %indvars.iv27
  %0 = load double, ptr %arrayidx8, align 8, !tbaa !0
  %rem9.lhs.trunc = trunc i64 %indvars.iv27 to i16
  %rem922 = urem i16 %rem9.lhs.trunc, 13
  %narrow = add nuw nsw i16 %rem922, 1
  %conv10 = uitofp nneg i16 %narrow to double
  %1 = tail call double @llvm.fmuladd.f64(double %0, double %conv10, double %s.024)
  %indvars.iv.next28 = add nuw nsw i64 %indvars.iv27, 1
  %exitcond30.not = icmp eq i64 %indvars.iv.next28, 4096
  br i1 %exitcond30.not, label %for.cond.cleanup5, label %for.body6
}

declare double @llvm.fmuladd.f64(double, double, double) #2

declare noundef i32 @printf(ptr nocapture noundef readonly, ...) local_unnamed_addr #3

attributes #0 = { nofree noinline norecurse nosync nounwind memory(argmem: readwrite) uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nofree nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #3 = { nofree nounwind "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!0 = !{!1, !1, i64 0}
!1 = !{!"double", !2, i64 0}
!2 = !{!"omnipotent char", !3, i64 0}
!3 = !{!"Simple C/C++ TBAA"}
