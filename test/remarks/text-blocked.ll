; LoopLens classification as an LLVM Analysis remark (pass 'looplens'), text form.
; Source (unsafe1.c):
;   void unsafe1(float *a, int n) { 
;     for (int i = 1; i < n; i++) 
;       a[i] = a[i - 1] + 1.0f; 
;   }
; Fixture: scripts/make_fixture.sh --g (debug info kept).
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -pass-remarks-analysis=looplens -disable-output %s 2>&1 \
; RUN:   | FileCheck %s

; CHECK: remark: unsafe1.c:2:3: Category: loop-carried-dependence; Rule: mem-unsafe-dep; Secondary: none; Evidence: Backward dependence load:%arrayidx -> store:%arrayidx2, distance 4 bytes; Fix: the loop carries a value between iterations; restructure it (e.g. a separate scan), or make the dependence distance at least the vector length{{$}}
; CHECK-NOT: remark:

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @unsafe1(ptr noundef %a, i32 noundef %n) #0 !dbg !9 {
entry:
    #dbg_value(ptr %a, !16, !DIExpression(), !20)
    #dbg_value(i32 %n, !17, !DIExpression(), !20)
    #dbg_value(i32 1, !18, !DIExpression(), !21)
  %cmp5 = icmp slt i32 1, %n, !dbg !22
  br i1 %cmp5, label %for.body.lr.ph, label %for.cond.cleanup, !dbg !24

for.body.lr.ph:
  br label %for.body, !dbg !24

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup, !dbg !24

for.cond.cleanup:
  br label %for.end

for.body:
  %i.06 = phi i32 [ 1, %for.body.lr.ph ], [ %inc, %for.inc ]
    #dbg_value(i32 %i.06, !18, !DIExpression(), !21)
  %sub = sub nsw i32 %i.06, 1, !dbg !25
  %idxprom = sext i32 %sub to i64, !dbg !26
  %arrayidx = getelementptr inbounds float, ptr %a, i64 %idxprom, !dbg !26
  %0 = load float, ptr %arrayidx, align 4, !dbg !26, !tbaa !27
  %add = fadd float %0, 1.000000e+00, !dbg !31
  %idxprom1 = sext i32 %i.06 to i64, !dbg !32
  %arrayidx2 = getelementptr inbounds float, ptr %a, i64 %idxprom1, !dbg !32
  store float %add, ptr %arrayidx2, align 4, !dbg !33, !tbaa !27
  br label %for.inc, !dbg !32

for.inc:
  %inc = add nsw i32 %i.06, 1, !dbg !34
    #dbg_value(i32 %inc, !18, !DIExpression(), !21)
  %cmp = icmp slt i32 %inc, %n, !dbg !22
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge, !dbg !24, !llvm.loop !35

for.end:
  ret void, !dbg !39
}

declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #1

declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #1

attributes #0 = { nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3, !4, !5, !6, !7}
!llvm.ident = !{!8}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, splitDebugInlining: false, nameTableKind: None)
!1 = !DIFile(filename: "unsafe1.c", directory: "/tmp/claude-0/-home-user-looplens-dev/24d7c459-5db6-50ad-8f3d-743755ee18b0/scratchpad/s14", checksumkind: CSK_MD5, checksum: "5b55e43af0765ec38c1739def628f9e5")
!2 = !{i32 7, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !{i32 1, !"wchar_size", i32 4}
!5 = !{i32 8, !"PIC Level", i32 2}
!6 = !{i32 7, !"PIE Level", i32 2}
!7 = !{i32 7, !"uwtable", i32 2}
!8 = !{!"Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)"}
!9 = distinct !DISubprogram(name: "unsafe1", scope: !1, file: !1, line: 1, type: !10, scopeLine: 1, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !15)
!10 = !DISubroutineType(types: !11)
!11 = !{null, !12, !14}
!12 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !13, size: 64)
!13 = !DIBasicType(name: "float", size: 32, encoding: DW_ATE_float)
!14 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!15 = !{!16, !17, !18}
!16 = !DILocalVariable(name: "a", arg: 1, scope: !9, file: !1, line: 1, type: !12)
!17 = !DILocalVariable(name: "n", arg: 2, scope: !9, file: !1, line: 1, type: !14)
!18 = !DILocalVariable(name: "i", scope: !19, file: !1, line: 2, type: !14)
!19 = distinct !DILexicalBlock(scope: !9, file: !1, line: 2, column: 3)
!20 = !DILocation(line: 0, scope: !9)
!21 = !DILocation(line: 0, scope: !19)
!22 = !DILocation(line: 2, column: 21, scope: !23)
!23 = distinct !DILexicalBlock(scope: !19, file: !1, line: 2, column: 3)
!24 = !DILocation(line: 2, column: 3, scope: !19)
!25 = !DILocation(line: 3, column: 16, scope: !23)
!26 = !DILocation(line: 3, column: 12, scope: !23)
!27 = !{!28, !28, i64 0}
!28 = !{!"float", !29, i64 0}
!29 = !{!"omnipotent char", !30, i64 0}
!30 = !{!"Simple C/C++ TBAA"}
!31 = !DILocation(line: 3, column: 21, scope: !23)
!32 = !DILocation(line: 3, column: 5, scope: !23)
!33 = !DILocation(line: 3, column: 10, scope: !23)
!34 = !DILocation(line: 2, column: 27, scope: !23)
!35 = distinct !{!35, !24, !36, !37, !38}
!36 = !DILocation(line: 3, column: 23, scope: !19)
!37 = !{!"llvm.loop.mustprogress"}
!38 = !{!"llvm.loop.unroll.disable"}
!39 = !DILocation(line: 4, column: 1, scope: !9)
