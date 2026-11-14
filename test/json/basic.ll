; One loop with a source location: the whole JSON line, exact.
; IR copied from test/loop-facts/loc-from-loopid.ll.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext -passes=looplens-analyze \
; RUN:   -looplens-json=%t.jsonl -disable-output %s 2>/dev/null
; RUN: FileCheck %s < %t.jsonl

; CHECK: {{^}}{"function":"saxpy","header":"%for.body","depth":1,"file":"saxpy.c","line":2,"col":3,"innermost":true,"primary":"none","rule":"none","secondary":[],"evidence":"","fix":"","trip":{"kind":"symbolic","count":null,"btc":"(-1 + %n)"},"mem":{"status":"needs-checks","checks":1,"report":"none"}}{{$}}
; CHECK-NOT: "function":

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @saxpy(ptr noundef %a, ptr noundef %b, float noundef %s, i32 noundef %n) !dbg !9 {
entry:
  %cmp4 = icmp slt i32 0, %n, !dbg !24
  br i1 %cmp4, label %for.body.lr.ph, label %for.cond.cleanup, !dbg !26

for.body.lr.ph:
  br label %for.body, !dbg !26

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup, !dbg !26

for.cond.cleanup:
  br label %for.end

for.body:
  %i.05 = phi i32 [ 0, %for.body.lr.ph ], [ %inc, %for.inc ]
  %idxprom = sext i32 %i.05 to i64, !dbg !27
  %arrayidx = getelementptr inbounds float, ptr %b, i64 %idxprom, !dbg !27
  %0 = load float, ptr %arrayidx, align 4, !dbg !27
  %idxprom1 = sext i32 %i.05 to i64, !dbg !32
  %arrayidx2 = getelementptr inbounds float, ptr %a, i64 %idxprom1, !dbg !32
  %1 = load float, ptr %arrayidx2, align 4, !dbg !33
  %2 = call float @llvm.fmuladd.f32(float %s, float %0, float %1), !dbg !33
  store float %2, ptr %arrayidx2, align 4, !dbg !33
  br label %for.inc, !dbg !32

for.inc:
  %inc = add nsw i32 %i.05, 1, !dbg !34
  %cmp = icmp slt i32 %inc, %n, !dbg !24
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge, !dbg !26, !llvm.loop !35

for.end:
  ret void, !dbg !39
}

declare float @llvm.fmuladd.f32(float, float, float)

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "clang version 20.1.2", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "saxpy.c", directory: ".")
!2 = !{i32 7, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!9 = distinct !DISubprogram(name: "saxpy", scope: !1, file: !1, line: 1, type: !10, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!10 = !DISubroutineType(types: !11)
!11 = !{null}
!21 = distinct !DILexicalBlock(scope: !9, file: !1, line: 2, column: 3)
!24 = !DILocation(line: 2, column: 21, scope: !25)
!25 = distinct !DILexicalBlock(scope: !21, file: !1, line: 2, column: 3)
!26 = !DILocation(line: 2, column: 3, scope: !21)
!27 = !DILocation(line: 3, column: 17, scope: !25)
!32 = !DILocation(line: 3, column: 5, scope: !25)
!33 = !DILocation(line: 3, column: 10, scope: !25)
!34 = !DILocation(line: 2, column: 27, scope: !25)
!35 = distinct !{!35, !26, !36, !37, !38}
!36 = !DILocation(line: 3, column: 20, scope: !21)
!37 = !{!"llvm.loop.mustprogress"}
!38 = !{!"llvm.loop.unroll.disable"}
!39 = !DILocation(line: 4, column: 1, scope: !9)
