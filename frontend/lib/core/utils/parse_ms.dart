// ISO8601 字符串 → 毫秒时间戳。空/非法时回退到 now（供 API/DTO 映射统一调用）。
int parseMs(dynamic iso) {
  if (iso is String && iso.isNotEmpty) {
    final dt = DateTime.tryParse(iso);
    if (dt != null) return dt.millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}
