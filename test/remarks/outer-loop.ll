; A loop nest: only the innermost loop gets a remark (LoopVectorize remarks only
; innermost loops too). Here the inner loop is vectorizable: Name Vectorizable.
; Source (nest.c):
;   void nest(float *a, int n) { 
;     for (int j = 0; j < n; j++) 
;       for (int i = 0; i < n; i++) 
;         a[j * n + i] = a[j * n + i + 1]; 
;   }
; Fixture: scripts/make_fixture.sh --g.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -pass-remarks-analysis=looplens -disable-output %s 2>&1 \
; RUN:   | FileCheck %s

; CHECK-NOT: remark: nest.c:2:
; CHECK: remark: nest.c:3:5: Category: none; Rule: none; Secondary: none{{$}}
; CHECK-NOT: remark:

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @nest(ptr noundef %a, i32 noundef %n) #0 !dbg !9 {
entry:
    #dbg_value(ptr %a, !16, !DIExpression(), !23)
    #dbg_value(i32 %n, !17, !DIExpression(), !23)
    #dbg_value(i32 0, !18, !DIExpression(), !24)
  %cmp13 = icmp slt i32 0, %n, !dbg !25
  br i1 %cmp13, label %for.body.lr.ph, label %for.cond.cleanup, !dbg !26

for.body.lr.ph:
  br label %for.body, !dbg !26

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup, !dbg !26

for.cond.cleanup:
  br label %for.end12

for.body:
  %j.014 = phi i32 [ 0, %for.body.lr.ph ], [ %inc11, %for.inc10 ]
    #dbg_value(i32 %j.014, !18, !DIExpression(), !24)
    #dbg_value(i32 0, !20, !DIExpression(), !27)
  %cmp211 = icmp slt i32 0, %n, !dbg !28
  br i1 %cmp211, label %for.body4.lr.ph, label %for.cond.cleanup3, !dbg !30

for.body4.lr.ph:
  br label %for.body4, !dbg !30

for.cond1.for.cond.cleanup3_crit_edge:
  br label %for.cond.cleanup3, !dbg !30

for.cond.cleanup3:
  br label %for.end

for.body4:
  %i.012 = phi i32 [ 0, %for.body4.lr.ph ], [ %inc, %for.inc ]
    #dbg_value(i32 %i.012, !20, !DIExpression(), !27)
  %mul = mul nsw i32 %j.014, %n, !dbg !31
  %add = add nsw i32 %mul, %i.012, !dbg !32
  %add5 = add nsw i32 %add, 1, !dbg !33
  %idxprom = sext i32 %add5 to i64, !dbg !34
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom, !dbg !34
  %0 = load float, ptr %arrayidx, align 4, !dbg !34, !tbaa !35
  %mul6 = mul nsw i32 %j.014, %n, !dbg !39
  %add7 = add nsw i32 %mul6, %i.012, !dbg !40
  %idxprom8 = sext i32 %add7 to i64, !dbg !41
  %arrayidx9 = getelementptr inbounds float, ptr %a, i64 %idxprom8, !dbg !41
  store float %0, ptr %arrayidx9, align 4, !dbg !42, !tbaa !35
  br label %for.inc, !dbg !41

for.inc:
  %inc = add nsw i32 %i.012, 1, !dbg !43
    #dbg_value(i32 %inc, !20, !DIExpression(), !27)
  %cmp2 = icmp slt i32 %inc, %n, !dbg !28
  br i1 %cmp2, label %for.body4, label %for.cond1.for.cond.cleanup3_crit_edge, !dbg !30, !llvm.loop !44

for.end:
  br label %for.inc10, !dbg !45

for.inc10:
  %inc11 = add nsw i32 %j.014, 1, !dbg !48
    #dbg_value(i32 %inc11, !18, !DIExpression(), !24)
  %cmp = icmp slt i32 %inc11, %n, !dbg !25
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge, !dbg !26, !llvm.loop !49

for.end12:
  ret void, !dbg !51
}

declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #1

declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #1

attributes #0 = { nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3, !4, !5, !6, !7}
!llvm.ident = !{!8}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, splitDebugInlining: false, nameTableKind: None)
!1 = !DIFile(filename: "nest.c", directory: "/tmp/claude-0/-home-user-looplens-dev/24d7c459-5db6-50ad-8f3d-743755ee18b0/scratchpad/s14", checksumkind: CSK_MD5, checksum: "508c0ec550252276bb0081bb09c71ff7")
!2 = !{i32 7, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !{i32 1, !"wchar_size", i32 4}
!5 = !{i32 8, !"PIC Level", i32 2}
!6 = !{i32 7, !"PIE Level", i32 2}
!7 = !{i32 7, !"uwtable", i32 2}
!8 = !{!"Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)"}
!9 = distinct !DISubprogram(name: "nest", scope: !1, file: !1, line: 1, type: !10, scopeLine: 1, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !15)
!10 = !DISubroutineType(types: !11)
!11 = !{null, !12, !14}
!12 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !13, size: 64)
!13 = !DIBasicType(name: "float", size: 32, encoding: DW_ATE_float)
!14 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!15 = !{!16, !17, !18, !20}
!16 = !DILocalVariable(name: "a", arg: 1, scope: !9, file: !1, line: 1, type: !12)
!17 = !DILocalVariable(name: "n", arg: 2, scope: !9, file: !1, line: 1, type: !14)
!18 = !DILocalVariable(name: "j", scope: !19, file: !1, line: 2, type: !14)
!19 = distinct !DILexicalBlock(scope: !9, file: !1, line: 2, column: 3)
!20 = !DILocalVariable(name: "i", scope: !21, file: !1, line: 3, type: !14)
!21 = distinct !DILexicalBlock(scope: !22, file: !1, line: 3, column: 5)
!22 = distinct !DILexicalBlock(scope: !19, file: !1, line: 2, column: 3)
!23 = !DILocation(line: 0, scope: !9)
!24 = !DILocation(line: 0, scope: !19)
!25 = !DILocation(line: 2, column: 21, scope: !22)
!26 = !DILocation(line: 2, column: 3, scope: !19)
!27 = !DILocation(line: 0, scope: !21)
!28 = !DILocation(line: 3, column: 23, scope: !29)
!29 = distinct !DILexicalBlock(scope: !21, file: !1, line: 3, column: 5)
!30 = !DILocation(line: 3, column: 5, scope: !21)
!31 = !DILocation(line: 4, column: 26, scope: !29)
!32 = !DILocation(line: 4, column: 30, scope: !29)
!33 = !DILocation(line: 4, column: 34, scope: !29)
!34 = !DILocation(line: 4, column: 22, scope: !29)
!35 = !{!36, !36, i64 0}
!36 = !{!"float", !37, i64 0}
!37 = !{!"omnipotent char", !38, i64 0}
!38 = !{!"Simple C/C++ TBAA"}
!39 = !DILocation(line: 4, column: 11, scope: !29)
!40 = !DILocation(line: 4, column: 15, scope: !29)
!41 = !DILocation(line: 4, column: 7, scope: !29)
!42 = !DILocation(line: 4, column: 20, scope: !29)
!43 = !DILocation(line: 3, column: 29, scope: !29)
!44 = distinct !{!44, !30, !45, !46, !47}
!45 = !DILocation(line: 4, column: 37, scope: !21)
!46 = !{!"llvm.loop.mustprogress"}
!47 = !{!"llvm.loop.unroll.disable"}
!48 = !DILocation(line: 2, column: 27, scope: !22)
!49 = distinct !{!49, !26, !50, !46, !47}
!50 = !DILocation(line: 4, column: 37, scope: !19)
!51 = !DILocation(line: 5, column: 1, scope: !9)
