/// Levenshtein 距离 + 智能纠错建议。
///
/// Phase 4 search 增强(HANDOFF §6.2):用户输入无结果时,基于 Levenshtein
/// 距离从候选词池找最接近的一个,提示"你是不是想搜:X"。
///
/// 本文件只提供纯函数,不耦合 repository / context — search_results_screen
/// 接入时从 searchRepository.searchTopics('') + searchUsers('') 等取候选词池,
/// 调用 [suggestClosest] 拿推荐结果。
///
/// 算法:经典两行 DP(滚动数组),空间 O(min(m,n))。
/// 距离定义:替换/插入/删除各计 1 步。

/// 计算 [a] 与 [b] 的 Levenshtein 编辑距离。
///
/// 例:levenshtein('kitten', 'sitting') == 3
///     levenshtein('flutter', 'fluter') == 1
///     levenshtein('', 'abc') == 3
int levenshtein(String a, String b) {
  // 把短串放前面,空间 O(min(m,n))
  if (a.length > b.length) {
    final t = a;
    a = b;
    b = t;
  }
  final m = a.length;
  final n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;

  // 前一行(prev) + 当前行(curr),长度 m + 1
  final prev = List<int>.generate(m + 1, (i) => i);
  final curr = List<int>.filled(m + 1, 0);

  for (var j = 1; j <= n; j++) {
    curr[0] = j;
    final bj = b.codeUnitAt(j - 1);
    for (var i = 1; i <= m; i++) {
      final cost = a.codeUnitAt(i - 1) == bj ? 0 : 1;
      final del = prev[i] + 1; // 删除 a[i-1]
      final ins = curr[i - 1] + 1; // 插入 b[j-1]
      final sub = prev[i - 1] + cost; // 替换
      var v = del < ins ? del : ins;
      if (sub < v) v = sub;
      curr[i] = v;
    }
    // 滚动:prev ↔ curr
    // 用 setRange 比 = List.from 快(复用 buffer)
    prev.setRange(0, m + 1, curr);
  }
  return prev[m];
}

/// 从 [candidates] 中找出与 [input] 编辑距离最小且 ≤ [maxDistance] 的词。
///
/// 找到 → 返回该候选词;找不到(都超过 maxDistance,或候选池空)→ 返回 null。
///
/// 平局处理:取候选池中第一个达到最小距离的(保持候选池原顺序,通常
/// 是按 heat 排序的 — 让高热度的同等距离候选优先)。
///
/// 例:suggestClosest('fluter', ['flutter', 'flux', 'react']) == 'flutter'
///     suggestClosest('xyz', ['abc', 'def'], maxDistance: 2) == null
String? suggestClosest(
  String input,
  List<String> candidates, {
  int maxDistance = 2,
}) {
  if (candidates.isEmpty) return null;
  final s = input.trim();
  if (s.isEmpty) return null;

  var bestDist = maxDistance + 1; // 哨兵:大于阈值
  String? best;
  for (final c in candidates) {
    final cs = c.trim();
    if (cs.isEmpty) continue;
    final d = levenshtein(s.toLowerCase(), cs.toLowerCase());
    if (d < bestDist) {
      bestDist = d;
      best = c; // 返回原候选词(保留大小写)
      if (d == 0) break; // 完全匹配,直接定
    }
  }
  return bestDist <= maxDistance ? best : null;
}
