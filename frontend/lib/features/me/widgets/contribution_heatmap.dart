import 'package:flutter/material.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/seed/mock_seed.dart';

/// 贡献热力图 — 任务⑯升级到 web 原型信息量。
///
/// 升级点(对齐原型 #13):
///   - 3 统计盒(总贡献 / 活跃天 / 最长连续),真实算自 cells,禁编造 ×N。
///   - 26 周(182 天)横向可滚动网格。
///   - 顶部月份标签(每月第一列上方标「N月」)+ 左侧星期标签(一/三/五)。
///   - 底部「少 ▢▢▣▣ 多」图例保留。
///
/// 向后兼容:`bare`/`showStats`/`showLegend` 参数语义不变(activity 屏依赖)。
///
/// 零旁白(HANDOFF §3):只标真实统计,不写"继续加油"之类引导。
/// 计数铁律(HANDOFF §6.10):总贡献/活跃天/最长连续全从 cells 真算。
class ContributionHeatmap extends StatelessWidget {
  /// 单元格列表(从 mock 或 Drift 读)
  final List<HeatmapCell> cells;

  /// 是否显示图例
  final bool showLegend;

  /// 是否显示统计行(任务⑯:升级为 3 统计盒)
  final bool showStats;

  /// 任务③:无外层 Container(无 bgCard/边框/padding),把内容直接嵌入
  /// 调用方自己的卡片里(me_screen 贡献卡)。默认 false 保持向后兼容
  /// (activity_screen 仍用自带容器的老用法)。
  final bool bare;

  const ContributionHeatmap({
    super.key,
    required this.cells,
    this.showLegend = true,
    this.showStats = true,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    // 排序:旧 → 新(先 .toList() 再 sort,铁律 5)
    final sorted = [...cells]
      ..sort((a, b) => a.dateMs.compareTo(b.dateMs));

    // 真实统计(HANDOFF §6.10,禁 ×200)
    final totalContributions = sorted.fold<int>(0, (s, c) => s + c.level);
    final activeDays = sorted.where((c) => c.level > 0).length;
    final longestStreak = _longestStreak(sorted);

    // 列数:按 7 天分组
    final weeks = (sorted.length / 7).ceil();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showStats) ...[
          _statsRow(totalContributions, activeDays, longestStreak),
          const SizedBox(height: KkSpacing.md),
        ],
        // 热力图主体:横向滚动(26 周宽,小屏溢出)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gridWithMonthLabels(sorted, weeks),
              if (showLegend) ...[
                const SizedBox(height: KkSpacing.sm),
                _legend(),
              ],
            ],
          ),
        ),
      ],
    );

    // 任务③:bare 模式直接返回内容,不带外层容器(嵌入调用方卡片)
    if (bare) return content;

    return Container(
      padding: const EdgeInsets.all(KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: content,
    );
  }

  /// 任务⑯B:3 统计盒并排(总贡献 / 活跃天 / 最长连续)。
  /// 真实算自 cells,禁编造。每盒:大数字 + 小标签,浅底 bgSubtle + 圆角 md,Expanded 等宽。
  Widget _statsRow(int total, int active, int streak) {
    return Row(
      children: [
        Expanded(child: _StatBox(value: '$total', label: '总贡献')),
        const SizedBox(width: KkSpacing.sm),
        Expanded(child: _StatBox(value: '$active', label: '活跃天')),
        const SizedBox(width: KkSpacing.sm),
        Expanded(child: _StatBox(value: '$streak', label: '最长连续')),
      ],
    );
  }

  /// 最长连续(任务⑯B 新算):遍历按日期排序的 cells,
  /// 累计连续 level>0,遇 0 重置,记最大值。
  int _longestStreak(List<HeatmapCell> sorted) {
    var best = 0;
    var cur = 0;
    for (final c in sorted) {
      if (c.level > 0) {
        cur++;
        if (cur > best) best = cur;
      } else {
        cur = 0;
      }
    }
    return best;
  }

  /// 任务⑯C:顶部月份标签 + 左侧星期标签 + 网格主体。
  Widget _gridWithMonthLabels(List<HeatmapCell> sorted, int weeks) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧星期标签列(占位对齐月份标签高度 + 一/三/五)
        _weekdayLabels(),
        const SizedBox(width: KkSpacing.xs),
        // 右侧:月份标签行 + 周列网格
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _monthLabels(sorted, weeks),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var w = 0; w < weeks; w++) ...[
                  _weekColumn(sorted, w),
                  if (w < weeks - 1) const SizedBox(width: 3),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// 任务⑯C:顶部月份标签 — 每月第一列上方标「N月」。
  /// 算法:遍历每列首日 cell,若该 cell 的月份 != 上一标过的月份,标「N月」。
  Widget _monthLabels(List<HeatmapCell> sorted, int weeks) {
    final labels = <Widget>[];
    var lastMonth = -1;
    for (var w = 0; w < weeks; w++) {
      final idx = w * 7;
      final dt = idx < sorted.length
          ? DateTime.fromMillisecondsSinceEpoch(sorted[idx].dateMs)
          : null;
      final hasLabel = dt != null && dt.month != lastMonth;
      if (hasLabel) lastMonth = dt!.month;
      // 列宽 11 + 间距 3(最后一列无间距),用 SizedBox 占位对齐
      labels.add(SizedBox(
        width: 11,
        child: hasLabel
            ? Text(
                '${dt!.month}月',
                style: TextStyle(
                  fontSize: 8,
                  color: KkColors.t3,
                  fontFamily: 'JetBrainsMono',
                ),
              )
            : const SizedBox(height: 10),
      ));
      if (w < weeks - 1) labels.add(const SizedBox(width: 3));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: labels,
    );
  }

  /// 星期标签(只标 一/三/五,参考 GitHub;原型用中文)。
  /// 高度对齐:每个 cell 11px + 间距 3px,7 行。
  Widget _weekdayLabels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 顶部留一行的月份标签高度(对齐月份行)
        const SizedBox(height: 10),
        const SizedBox(height: 2),
        _zhLabel('一'),
        const SizedBox(height: 3),
        const SizedBox(height: 11),
        const SizedBox(height: 3),
        _zhLabel('三'),
        const SizedBox(height: 3),
        const SizedBox(height: 11),
        const SizedBox(height: 3),
        _zhLabel('五'),
        const SizedBox(height: 3),
        const SizedBox(height: 11),
        const SizedBox(height: 3),
      ],
    );
  }

  Widget _zhLabel(String t) {
    return SizedBox(
      width: 12,
      height: 11,
      child: Text(
        t,
        style: TextStyle(
          fontSize: 8,
          color: KkColors.t4,
          fontFamily: 'NotoSerifSC',
        ),
      ),
    );
  }

  Widget _weekColumn(List<HeatmapCell> sorted, int weekIdx) {
    return Column(
      children: [
        for (var d = 0; d < 7; d++) ...[
          _cell(sorted, weekIdx * 7 + d),
          if (d < 6) const SizedBox(height: 3),
        ],
      ],
    );
  }

  Widget _cell(List<HeatmapCell> sorted, int idx) {
    if (idx < 0 || idx >= sorted.length) {
      return const SizedBox(width: 11, height: 11);
    }
    final level = sorted[idx].level;
    return Tooltip(
      message: _tooltip(sorted[idx]),
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: _colorForLevel(level),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  String _tooltip(HeatmapCell c) {
    final dt = DateTime.fromMillisecondsSinceEpoch(c.dateMs);
    final dateStr = '${dt.month}-${dt.day}';
    return c.level > 0 ? '$dateStr · $c.level 次贡献' : '$dateStr · 无贡献';
  }

  /// 5 档色阶:HANDOFF §5 不用蓝/紫。用 mint → teal 渐进。
  Color _colorForLevel(int level) {
    switch (level) {
      case 0:
        return KkColors.bgSubtle;
      case 1:
        return const Color(0xFFD4ECDD); // 浅 mint
      case 2:
        return const Color(0xFFA8D9BC);
      case 3:
        return const Color(0xFF6BBE8E);
      case 4:
      default:
        return KkColors.teal;
    }
  }

  Widget _legend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '少',
          style: TextStyle(
            fontSize: 9,
            color: KkColors.t4,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(width: 4),
        for (var lv = 0; lv <= 4; lv++) ...[
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _colorForLevel(lv),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
        const SizedBox(width: 4),
        Text(
          '多',
          style: TextStyle(
            fontSize: 9,
            color: KkColors.t4,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ],
    );
  }
}

/// 任务⑯B:统计盒(大数字 + 小标签,浅底 bgSubtle + 圆角 md)。
class _StatBox extends StatelessWidget {
  final String value;
  final String label;

  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: KkType.monoLg.copyWith(color: KkColors.teal),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: KkColors.t3,
              fontFamily: 'NotoSerifSC',
            ),
          ),
        ],
      ),
    );
  }
}
