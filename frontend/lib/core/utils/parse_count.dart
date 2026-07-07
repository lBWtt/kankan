/// 数字解析/格式化工具。
///
/// Web 版 src/lib 里的 parseCount 直译。Phase 2 起各屏统计用。
/// HANDOFF §6.10:禁止 ×200、×8+30 之类编造公式——所有计数取真实来源,
/// 这个 helper 只做字符串↔数字的机械转换,不做任何放大。

/// "1.2k" → 1200,"3.5w" → 35000,"200" → 200,"1,234" → 1234,null/空 → 0
int parseCount(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  var s = value.toString().trim().toLowerCase().replaceAll(',', '');
  if (s.isEmpty) return 0;
  var mult = 1;
  if (s.endsWith('k')) {
    mult = 1000;
    s = s.substring(0, s.length - 1);
  } else if (s.endsWith('w')) {
    mult = 10000;
    s = s.substring(0, s.length - 1);
  }
  final n = double.tryParse(s);
  return n == null ? 0 : (n * mult).round();
}

/// 1200 → "1.2k",35000 → "3.5w",200 → "200",0 → "0"
String formatCount(int n) {
  if (n < 0) return '0';
  if (n < 1000) return n.toString();
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 10000).toStringAsFixed(1)}w';
}
