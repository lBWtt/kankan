// 相对时间格式化(中文)单测。
//
// 覆盖 lib/core/utils/time_ago.dart 的 timeAgo:
//   - diff < 0(未来)→ '刚刚'
//   - sec < 60 → '刚刚'
//   - min < 60 → '$min分钟前'
//   - hr  < 24 → '$hr小时前'
//   - day == 1 → '昨天'
//   - day < 7  → '$day天前'
//   - day < 30 → '${day ~/ 7}周前'
//   - day < 365 → '${day ~/ 30}个月前'
//   - else → 'YYYY-MM-DD'
//
// nowMs 可注入,所有用例都用固定 nowMs 保证可重复(不依赖 wall clock)。
// mock_seed.dart 里 _baseMs = 1833012000000(2025-12-01 02:00 UTC),这里复用。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/core/utils/time_ago.dart';

void main() {
  // 与 mock_seed._baseMs 对齐,便于跨测试互相印证。
  const nowMs = 1833012000000; // 2025-12-01 02:00 UTC
  const second = 1000;
  const minute = 60 * second;
  const hour = 60 * minute;
  const day = 24 * hour;

  group('timeAgo · 刚刚', () {
    test('diff = 0(现在)→ "刚刚"', () {
      expect(timeAgo(nowMs, nowMs: nowMs), '刚刚');
    });

    test('30s 前 → "刚刚"(sec < 60)', () {
      expect(timeAgo(nowMs - 30 * second, nowMs: nowMs), '刚刚');
    });

    test('59s 前 → "刚刚"(边界 sec=59)', () {
      expect(timeAgo(nowMs - 59 * second, nowMs: nowMs), '刚刚');
    });

    test('未来时间(diff < 0)→ "刚刚"', () {
      expect(timeAgo(nowMs + minute, nowMs: nowMs), '刚刚');
      expect(timeAgo(nowMs + day, nowMs: nowMs), '刚刚');
    });
  });

  group('timeAgo · 分钟前', () {
    test('60s 前 → "1分钟前"(边界 sec=60, min=1)', () {
      expect(timeAgo(nowMs - 60 * second, nowMs: nowMs), '1分钟前');
    });

    test('119s 前 → "1分钟前"(min=1,因 119 ~/ 60 = 1)', () {
      expect(timeAgo(nowMs - 119 * second, nowMs: nowMs), '1分钟前');
    });

    test('120s 前 → "2分钟前"', () {
      expect(timeAgo(nowMs - 120 * second, nowMs: nowMs), '2分钟前');
    });

    test('30min 前 → "30分钟前"', () {
      expect(timeAgo(nowMs - 30 * minute, nowMs: nowMs), '30分钟前');
    });

    test('59min 前 → "59分钟前"(边界 min=59)', () {
      expect(timeAgo(nowMs - 59 * minute, nowMs: nowMs), '59分钟前');
    });
  });

  group('timeAgo · 小时前', () {
    test('60min 前 → "1小时前"(边界 min=60, hr=1)', () {
      expect(timeAgo(nowMs - 60 * minute, nowMs: nowMs), '1小时前');
    });

    test('2h 前 → "2小时前"', () {
      expect(timeAgo(nowMs - 2 * hour, nowMs: nowMs), '2小时前');
    });

    test('23h 前 → "23小时前"(边界 hr=23)', () {
      expect(timeAgo(nowMs - 23 * hour, nowMs: nowMs), '23小时前');
    });

    test('1439min 前 → "23小时前"(hr=23,因 1439 ~/ 60 = 23)', () {
      expect(timeAgo(nowMs - 1439 * minute, nowMs: nowMs), '23小时前');
    });
  });

  group('timeAgo · 天/昨天/周/月', () {
    test('24h 前 → "昨天"(边界 hr=24, day=1)', () {
      expect(timeAgo(nowMs - 24 * hour, nowMs: nowMs), '昨天');
    });

    test('48h 前 → "2天前"(day=2)', () {
      expect(timeAgo(nowMs - 48 * hour, nowMs: nowMs), '2天前');
    });

    test('6 天前 → "6天前"(边界 day=6,仍 < 7)', () {
      expect(timeAgo(nowMs - 6 * day, nowMs: nowMs), '6天前');
    });

    test('7 天前 → "1周前"(边界 day=7,7 ~/ 7 = 1)', () {
      expect(timeAgo(nowMs - 7 * day, nowMs: nowMs), '1周前');
    });

    test('13 天前 → "1周前"(13 ~/ 7 = 1)', () {
      expect(timeAgo(nowMs - 13 * day, nowMs: nowMs), '1周前');
    });

    test('14 天前 → "2周前"(14 ~/ 7 = 2)', () {
      expect(timeAgo(nowMs - 14 * day, nowMs: nowMs), '2周前');
    });

    test('29 天前 → "4周前"(边界 day=29, 29 ~/ 7 = 4)', () {
      expect(timeAgo(nowMs - 29 * day, nowMs: nowMs), '4周前');
    });

    test('30 天前 → "1个月前"(边界 day=30, 30 ~/ 30 = 1)', () {
      expect(timeAgo(nowMs - 30 * day, nowMs: nowMs), '1个月前');
    });

    test('60 天前 → "2个月前"(60 ~/ 30 = 2)', () {
      expect(timeAgo(nowMs - 60 * day, nowMs: nowMs), '2个月前');
    });

    test('364 天前 → "12个月前"(边界 day=364, 364 ~/ 30 = 12)', () {
      expect(timeAgo(nowMs - 364 * day, nowMs: nowMs), '12个月前');
    });
  });

  group('timeAgo · 日期串(≥ 365 天)', () {
    test('365 天前 → "YYYY-MM-DD" 格式(不再走相对时间)', () {
      final ms = nowMs - 365 * day;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final expected =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      expect(timeAgo(ms, nowMs: nowMs), expected);
    });

    test('730 天前 → 同样是日期串格式', () {
      final ms = nowMs - 730 * day;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final expected =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      expect(timeAgo(ms, nowMs: nowMs), expected);
    });

    test('日期串格式形如 YYYY-MM-DD(正则校验)', () {
      final ms = nowMs - 400 * day;
      final out = timeAgo(ms, nowMs: nowMs);
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(out), isTrue,
          reason: '实际输出: $out');
    });
  });

  group('timeAgo · 默认 nowMs(不注入,用 wall clock)', () {
    test('now → "刚刚"(diff=0,允许 ±1s 误差)', () {
      final t = DateTime.now().millisecondsSinceEpoch;
      // 不注入 nowMs,函数内部用 DateTime.now()。t 与函数内取的 now 极近,
      // diff 落在 0..几毫秒,sec < 60,返回 "刚刚"。
      expect(timeAgo(t), '刚刚');
    });
  });
}
