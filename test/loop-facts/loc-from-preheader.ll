; No LoopID: Loop::getStartLoc() falls back to the preheader terminator's
; location (7:5), not the header terminator's (9:1). Checked against the
; location LoopVectorize prints in its remark for the same IR.
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-NOT:   warning:
; CHECK-LABEL: looplens: function 'f'
; CHECK-NEXT:  loop header=loop depth=1 loc=fallback.c:7:5{{$}}
; CHECK-NOT:   loop header=

define void @f(ptr %a, i64 %n) !dbg !4 {
entry:
  br label %ph, !dbg !8

ph:
  br label %loop, !dbg !9

loop:
  %i = phi i64 [ 0, %ph ], [ %i.next, %loop ]
  %p = getelementptr inbounds float, ptr %a, i64 %i
  store float 0.0, ptr %p, align 4
  %i.next = add nuw nsw i64 %i, 1
  %c = icmp slt i64 %i.next, %n
  br i1 %c, label %loop, label %exit, !dbg !10

exit:
  ret void
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!3}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "hand-written", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "fallback.c", directory: ".")
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = distinct !DISubprogram(name: "f", scope: !1, file: !1, line: 1, type: !5, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!5 = !DISubroutineType(types: !6)
!6 = !{null}
!8 = !DILocation(line: 6, column: 1, scope: !4)
!9 = !DILocation(line: 7, column: 5, scope: !4)
!10 = !DILocation(line: 9, column: 1, scope: !4)
