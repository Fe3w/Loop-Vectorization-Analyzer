; Nested clang loops: each loop gets its own LoopID location (outer 2:3,
; inner 3:5), printed in preorder.
;
; Source (nest.c):
;   1 void nest(int *a, int n) {
;   2   for (int i = 0; i < n; i++)
;   3     for (int j = 0; j < n; j++)
;   4       a[i*n+j] = 0;
;   5 }
; Generated with the fixture recipe in DECISIONS.md, then reduced by hand.
; Inner header name taken from `opt -passes='print<loops>'` on this IR.
;
; RUN: opt -load-pass-plugin=%shlibdir/LoopLens%shlibext \
; RUN:   -passes=looplens-analyze -disable-output %s 2>&1 | FileCheck %s

; CHECK-NOT:   warning:
; CHECK-LABEL: looplens: function 'nest'
; CHECK-NEXT:  loop header=%for.body depth=1 loc=nest.c:2:3{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + %n)] max-btc=[2147483646] symbolic-max-btc=[(-1 + %n)]{{$}}
; CHECK-NEXT:  iv phi=%i.010 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=no guarded=yes{{$}}
; CHECK-NEXT:  mem <not-innermost>{{$}}
; CHECK-NEXT:  blocker <not-innermost>{{$}}
; CHECK-NEXT:  loop header=%for.body4 depth=2 loc=nest.c:3:5{{$}}
; CHECK-NEXT:  trip kind=symbolic count=none btc=[(-1 + %n)] max-btc=[2147483646] symbolic-max-btc=[(-1 + %n)]{{$}}
; CHECK-NEXT:  iv phi=%j.08 kind=int start=0 step=1 scev=[{0,+,1}<nuw><nsw><%for.body4>] controls-exit=yes{{$}}
; CHECK-NEXT:  form simplify=yes rotated=yes lcssa=yes exiting=single innermost=yes guarded=yes{{$}}
; CHECK-NEXT:  cfg blocks=2 predicated=0 switches=0 exits=1 early-exit=none{{$}}
; CHECK-NEXT:  mem status=safe checks=0 max-safe-width=any report=none{{$}}
; CHECK-NEXT:  dep <none>{{$}}
; CHECK-NEXT:  access store ptr=%arrayidx kind=unit stride=1{{$}}
; CHECK-NEXT:  blocker primary=none rule=none secondary=none{{$}}
; CHECK-NOT:   loop header=

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

define void @nest(ptr noundef %a, i32 noundef %n) !dbg !9 {
entry:
  %cmp9 = icmp slt i32 0, %n, !dbg !24
  br i1 %cmp9, label %for.body.lr.ph, label %for.cond.cleanup, !dbg !25

for.body.lr.ph:
  br label %for.body, !dbg !25

for.cond.for.cond.cleanup_crit_edge:
  br label %for.cond.cleanup, !dbg !25

for.cond.cleanup:
  br label %for.end7

for.body:
  %i.010 = phi i32 [ 0, %for.body.lr.ph ], [ %inc6, %for.inc5 ]
  %cmp27 = icmp slt i32 0, %n, !dbg !27
  br i1 %cmp27, label %for.body4.lr.ph, label %for.cond.cleanup3, !dbg !29

for.body4.lr.ph:
  br label %for.body4, !dbg !29

for.cond1.for.cond.cleanup3_crit_edge:
  br label %for.cond.cleanup3, !dbg !29

for.cond.cleanup3:
  br label %for.end

for.body4:
  %j.08 = phi i32 [ 0, %for.body4.lr.ph ], [ %inc, %for.inc ]
  %mul = mul nsw i32 %i.010, %n, !dbg !30
  %add = add nsw i32 %mul, %j.08, !dbg !31
  %idxprom = sext i32 %add to i64, !dbg !32
  %arrayidx = getelementptr inbounds i32, ptr %a, i64 %idxprom, !dbg !32
  store i32 0, ptr %arrayidx, align 4, !dbg !33
  br label %for.inc, !dbg !32

for.inc:
  %inc = add nsw i32 %j.08, 1, !dbg !38
  %cmp2 = icmp slt i32 %inc, %n, !dbg !27
  br i1 %cmp2, label %for.body4, label %for.cond1.for.cond.cleanup3_crit_edge, !dbg !29, !llvm.loop !39

for.end:
  br label %for.inc5, !dbg !40

for.inc5:
  %inc6 = add nsw i32 %i.010, 1, !dbg !43
  %cmp = icmp slt i32 %inc6, %n, !dbg !24
  br i1 %cmp, label %for.body, label %for.cond.for.cond.cleanup_crit_edge, !dbg !25, !llvm.loop !44

for.end7:
  ret void, !dbg !46
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "clang version 20.1.2", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "nest.c", directory: ".")
!2 = !{i32 7, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!9 = distinct !DISubprogram(name: "nest", scope: !1, file: !1, line: 1, type: !10, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!10 = !DISubroutineType(types: !11)
!11 = !{null}
!18 = distinct !DILexicalBlock(scope: !9, file: !1, line: 2, column: 3)
!20 = distinct !DILexicalBlock(scope: !21, file: !1, line: 3, column: 5)
!21 = distinct !DILexicalBlock(scope: !18, file: !1, line: 2, column: 3)
!24 = !DILocation(line: 2, column: 21, scope: !21)
!25 = !DILocation(line: 2, column: 3, scope: !18)
!27 = !DILocation(line: 3, column: 23, scope: !28)
!28 = distinct !DILexicalBlock(scope: !20, file: !1, line: 3, column: 5)
!29 = !DILocation(line: 3, column: 5, scope: !20)
!30 = !DILocation(line: 4, column: 10, scope: !28)
!31 = !DILocation(line: 4, column: 12, scope: !28)
!32 = !DILocation(line: 4, column: 7, scope: !28)
!33 = !DILocation(line: 4, column: 16, scope: !28)
!38 = !DILocation(line: 3, column: 29, scope: !28)
!39 = distinct !{!39, !29, !40, !41, !42}
!40 = !DILocation(line: 4, column: 18, scope: !20)
!41 = !{!"llvm.loop.mustprogress"}
!42 = !{!"llvm.loop.unroll.disable"}
!43 = !DILocation(line: 2, column: 27, scope: !21)
!44 = distinct !{!44, !25, !45, !41, !42}
!45 = !DILocation(line: 4, column: 18, scope: !18)
!46 = !DILocation(line: 5, column: 1, scope: !9)
