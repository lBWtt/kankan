/// 相对时间格式化(中文)。
///
/// Web 版 src/lib 里的 timeAgo 直译。Phase 2 起动态/项目卡片时间戳用。

/// 毫秒时间戳 → "刚刚" / "3分钟前" / "2小时前" / "昨天" / "3天前" / "2025-01-15"
///
/// [nowMs] 可注入(测试用),默认 DateTime.now().millisecondsSinceEpoch。
String timeAgo(int ms, {int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final diff = now - ms;
  if (diff < 0) return '刚刚';
  final sec = diff ~/ 1000;
  if (sec < 60) return '刚刚';
  final min = sec ~/ 60;
  if (min < 60) return '$min分钟前';
  final hr = min ~/ 60;
  if (hr < 24) return '$hr小时前';
  final day = hr ~/ 24;
  if (day == 1) return '昨天';
  if (day < 7) return '$day天前';
  if (day < 30) return '${day ~/ 7}周前';
  if (day < 365) return '${day ~/ 30}个月前';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${dt.year}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
