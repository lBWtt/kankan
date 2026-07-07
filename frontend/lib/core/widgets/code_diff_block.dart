import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';

import '../theme/kk_colors.dart';
import '../theme/tokens.dart';

/// HowAction 工作流展示组件 — HANDOFF §2.2 how 动作的渲染。
///
/// 用途:HowAction 跳转工作流详情页时,渲染 before/after 代码对比。
///
/// 设计:
///   - Phase 5 接 flutter_highlight 真语法高亮（只给 after 无 diff 时启用）
///   - before+after 都给时,用 O(n*m) LCS 算法按行精确匹配算 diff
///     （diff 行的 +/- 着色优先于语法高亮，保留 diff 语义）
///   - 只给 after 时,用 HighlightView 按语言真语法高亮（keyword/string/...）
///   - 顶部 bar:标题(KkType.body 加粗)+ 语言标签(KkType.mono t3,
///     圆角 sm,bgSubtle 底)
///   - 代码区:JetBrainsMono,size 12,行高 1.5
///   - added 行:[KkColors.mint] 背景 + 左侧 3px [KkColors.teal] 边
///   - removed 行:[KkColors.coralMint] 背景 + 左侧 3px [KkColors.coral] 边
///     (HANDOFF §5 允许 coral 表「删除」语义)
///   - unchanged / context 行:无背景
///   - 整体圆角 [KkRadius.md],边框 [KkColors.bd],背景 [KkColors.bgCard]
///   - 内边距 [KkSpacing.md]
///   - 行号 [KkType.mono] t4 灰,size 10,右侧 [KkSpacing.md] 间距
class CodeDiffBlock extends StatelessWidget {
  /// 工作流标题(顶部 bar 左侧)
  final String title;

  /// 改造前代码(可选,仅展示 after 时不显示)
  final String? before;

  /// 改造后代码
  final String after;

  /// 语言标签(`'dart'` / `'ts'` / `'bash'` 等)
  final String? language;

  /// 可选:精确 diff 行(给定时优先,忽略 before/after 的 LCS 计算)
  final List<DiffLine>? lines;

  const CodeDiffBlock({
    super.key,
    required this.title,
    this.before,
    required this.after,
    this.language,
    this.lines,
  });

  @override
  Widget build(BuildContext context) {
    final renderedLines = _resolveLines();
    return Container(
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _topBar(),
          _codeArea(renderedLines),
        ],
      ),
    );
  }

  // ── 顶部 bar ──
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: KkColors.bgSubtle,
        border: Border(bottom: BorderSide(color: KkColors.bd)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: KkType.body.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (language != null) ...[
            const SizedBox(width: KkSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: KkColors.bgCard,
                borderRadius: BorderRadius.circular(KkRadius.sm),
                border: Border.all(color: KkColors.bd),
              ),
              child: Text(
                language!,
                style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 代码区 ──
  Widget _codeArea(List<DiffLine> rendered) {
    if (rendered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(KkSpacing.md),
        child: Text(
          '(空)',
          style: KkType.mono.copyWith(fontSize: 12, color: KkColors.t4),
        ),
      );
    }
    // Phase 5：无 diff（只给 after，无 before）→ flutter_highlight 真语法高亮。
    final hasDiff = before != null && before!.isNotEmpty;
    if (!hasDiff) {
      return Padding(
        padding: const EdgeInsets.all(KkSpacing.md),
        child: HighlightView(
          after,
          language: language ?? 'dart',
          theme: _kkCodeTheme,
          textStyle: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 12,
            height: 1.5,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(KkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rendered.length; i++)
            _DiffLineRow(lineNumber: i + 1, line: rendered[i]),
        ],
      ),
    );
  }

  // ── 解析最终 diff 行 ──
  List<DiffLine> _resolveLines() {
    // 1. 显式 lines 优先
    if (lines != null) return lines!;
    // 2. before + after → LCS diff
    if (before != null && before!.isNotEmpty) {
      return _computeDiff(before!, after);
    }
    // 3. 只给 after → 全 unchanged
    return after
        .split('\n')
        .map((t) => DiffLine(text: t, type: DiffLineType.unchanged))
        .toList(growable: false);
  }

  /// O(n*m) LCS 按行精确匹配,回溯生成 added/removed/unchanged 序列。
  ///
  /// 简化版:仅当两行字符串完全相等才算 unchanged。
  /// 大文件场景可换 Myers 算法,这里满足 HowAction 工作流的小代码片段。
  static List<DiffLine> _computeDiff(String before, String after) {
    final a = before.split('\n');
    final b = after.split('\n');
    final m = a.length;
    final n = b.length;

    // dp[i][j] = a[i:] 与 b[j:] 的 LCS 长度
    final List<List<int>> dp = List.generate(
      m + 1,
      (_) => List<int>.filled(n + 1, 0),
      growable: false,
    );
    for (var i = m - 1; i >= 0; i--) {
      for (var j = n - 1; j >= 0; j--) {
        if (a[i] == b[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
    }

    final result = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < m && j < n) {
      if (a[i] == b[j]) {
        result.add(DiffLine(text: a[i], type: DiffLineType.unchanged));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        result.add(DiffLine(text: a[i], type: DiffLineType.removed));
        i++;
      } else {
        result.add(DiffLine(text: b[j], type: DiffLineType.added));
        j++;
      }
    }
    while (i < m) {
      result.add(DiffLine(text: a[i], type: DiffLineType.removed));
      i++;
    }
    while (j < n) {
      result.add(DiffLine(text: b[j], type: DiffLineType.added));
      j++;
    }
    return result;
  }
}

/// diff 行类型。
///
/// - [added]:after 新增行(mint 背景 + teal 左边)
/// - [removed]:before 删除行(coralMint 背景 + coral 左边)
/// - [unchanged]:before/after 共有行(无背景)
/// - [context]:非 diff 区的上下文行(视觉同 unchanged,供调用方语义区分)
enum DiffLineType { added, removed, unchanged, context }

/// 一行 diff。
class DiffLine {
  final String text;
  final DiffLineType type;

  const DiffLine({required this.text, required this.type});
}

// ──────────────────────────────────────────────────────────────────
// 单行渲染:行号 + 前缀符号 + 代码,背景/左边按 type 区分
// ──────────────────────────────────────────────────────────────────
class _DiffLineRow extends StatelessWidget {
  final int lineNumber;
  final DiffLine line;

  const _DiffLineRow({required this.lineNumber, required this.line});

  @override
  Widget build(BuildContext context) {
    final (bg, borderColor, textColor, prefix) = _styleFor(line.type);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        border: borderColor == null
            ? null
            : Border(
                left: BorderSide(color: borderColor, width: 3),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.sm,
          vertical: 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$lineNumber',
                style: KkType.mono.copyWith(
                  fontSize: 10,
                  color: KkColors.t4,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Text(
                '$prefix ${line.text}',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  height: 1.5,
                  color: textColor,
                ),
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// (背景色, 左边色, 文字色, 前缀符号)
  (Color?, Color?, Color, String) _styleFor(DiffLineType t) {
    return switch (t) {
      DiffLineType.added =>
        (KkColors.mint, KkColors.teal, KkColors.tealDark, '+'),
      DiffLineType.removed =>
        (KkColors.coralMint, KkColors.coral, KkColors.coralDark, '-'),
      DiffLineType.unchanged || DiffLineType.context =>
        (null, null, KkColors.t1, ' '),
    };
  }
}

/// Phase 5：flutter_highlight 自定义浅色主题（与项目配色协调）。
/// key 对应 highlight.js CSS class（keyword/string/comment/number/...）。
/// 用自定义 map 而非 import 主题文件，避免主题文件名不确定性。
const _kkCodeTheme = {
  'root': TextStyle(color: KkColors.t1, backgroundColor: Color(0x00000000)),
  'keyword': TextStyle(color: KkColors.tealDark, fontWeight: FontWeight.w600),
  'built_in': TextStyle(color: KkColors.tealDark),
  'string': TextStyle(color: KkColors.coralDark),
  'attr': TextStyle(color: KkColors.coralDark),
  'comment': TextStyle(color: KkColors.t4, fontStyle: FontStyle.italic),
  'number': TextStyle(color: KkColors.tealDark),
  'literal': TextStyle(color: KkColors.tealDark),
  'function': TextStyle(color: KkColors.tealDark, fontWeight: FontWeight.w600),
  'title': TextStyle(color: KkColors.tealDark, fontWeight: FontWeight.w600),
  'class': TextStyle(color: KkColors.tealDark, fontWeight: FontWeight.w600),
  'type': TextStyle(color: KkColors.tealDark),
  'params': TextStyle(color: KkColors.t1),
  'variable': TextStyle(color: KkColors.t1),
  'meta': TextStyle(color: KkColors.t3),
  'tag': TextStyle(color: KkColors.tealDark),
  'symbol': TextStyle(color: KkColors.coralDark),
  'regexp': TextStyle(color: KkColors.coralDark),
};
