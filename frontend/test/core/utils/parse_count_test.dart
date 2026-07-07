// 数字解析/格式化工具单测。
//
// 覆盖 lib/core/utils/parse_count.dart 的两个公开函数:
//   - parseCount:动态值(可能 null / int / double / String)→ int。
//     支持 'k'(×1000)与 'w'(×10000)后缀,英文逗号千分位,trim,大小写不敏感。
//   - formatCount:int → 人类可读短串('<1000 原样 / <10000 'x.yk' / ≥10000 'x.yw')。
//
// 注意:本代码只支持 'k' / 'w' 后缀,**不支持** 中文 '万' 后缀
// (toLowerCase 不会把 '万' 转成 'w')。本测试显式覆盖这一行为,以便未来若
// 增加 '万' 支持时能被发现/更新。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/core/utils/parse_count.dart';

void main() {
  group('parseCount', () {
    group('null / 空 / 非数字', () {
      test('null → 0', () {
        expect(parseCount(null), 0);
      });

      test('空串 → 0', () {
        expect(parseCount(''), 0);
      });

      test('纯空白 → 0(先 trim)', () {
        expect(parseCount('   '), 0);
        expect(parseCount('\t\n'), 0);
      });

      test('非数字串 → 0(double.tryParse 失败)', () {
        expect(parseCount('abc'), 0);
        expect(parseCount('hello world'), 0);
      });

      test('中文「万」后缀不被支持 → 0(known limitation)', () {
        // '万' 与 'w' 是不同字符;toLowerCase 不转换。double.tryParse('1.2万') 失败 → 0。
        // 这是当前实现的实际行为(若未来支持「万」需更新本测试)。
        expect(parseCount('1.2万'), 0);
        expect(parseCount('1万'), 0);
        expect(parseCount('2.3万'), 0);
      });
    });

    group('纯整数字符串', () {
      test('"0" → 0', () {
        expect(parseCount('0'), 0);
      });

      test('"200" → 200', () {
        expect(parseCount('200'), 200);
      });

      test('"8300" → 8300', () {
        expect(parseCount('8300'), 8300);
      });

      test('"1234567" → 1234567(大整数不丢精度)', () {
        expect(parseCount('1234567'), 1234567);
      });
    });

    group('已是数字类型(直通分支)', () {
      test('int 直接返回', () {
        expect(parseCount(5), 5);
        expect(parseCount(0), 0);
        expect(parseCount(8300), 8300);
      });

      test('double 走 toInt 截断(非四舍五入)', () {
        expect(parseCount(5.7), 5);
        expect(parseCount(5.9), 5);
        expect(parseCount(-1.5), -1);
      });
    });

    group('k 后缀(×1000)', () {
      test('"1.2k" → 1200', () {
        expect(parseCount('1.2k'), 1200);
      });

      test('"1.5K" → 1500(大小写不敏感)', () {
        expect(parseCount('1.5K'), 1500);
      });

      test('"3k" → 3000(整数前缀)', () {
        expect(parseCount('3k'), 3000);
      });

      test('"0.5k" → 500', () {
        expect(parseCount('0.5k'), 500);
      });
    });

    group('w 后缀(×10000)', () {
      test('"1w" → 10000', () {
        expect(parseCount('1w'), 10000);
      });

      test('"1.2w" → 12000', () {
        expect(parseCount('1.2w'), 12000);
      });

      test('"2.3w" → 23000', () {
        expect(parseCount('2.3w'), 23000);
      });

      test('"3.5w" → 35000', () {
        expect(parseCount('3.5w'), 35000);
      });

      test('"3.5W" → 35000(大小写不敏感)', () {
        expect(parseCount('3.5W'), 35000);
      });
    });

    group('逗号千分位 + 空白', () {
      test('"1,234" → 1234(去逗号)', () {
        expect(parseCount('1,234'), 1234);
      });

      test('"12,345" → 12345', () {
        expect(parseCount('12,345'), 12345);
      });

      test('"  200  " → 200(先 trim)', () {
        expect(parseCount('  200  '), 200);
      });

      test('" 1.2k " → 1200(trim + 后缀)', () {
        expect(parseCount(' 1.2k '), 1200);
      });
    });

    group('边界:负数 / 混合脏数据', () {
      test('"-100" → -100(double.tryParse 支持,无符号分支)', () {
        // 注:parseCount 不做符号守卫,formatCount 才守负数。
        expect(parseCount('-100'), -100);
      });

      test('"12abc" → 0(混合串 tryParse 失败)', () {
        expect(parseCount('12abc'), 0);
      });

      test('"k" 单独后缀 → 0(空数字 + 后缀,double.tryParse("") 失败)', () {
        expect(parseCount('k'), 0);
      });
    });
  });

  group('formatCount', () {
    group('负数守卫', () {
      test('负数 → "0"', () {
        expect(formatCount(-1), '0');
        expect(formatCount(-100), '0');
      });
    });

    group('< 1000 原样', () {
      test('0 → "0"', () {
        expect(formatCount(0), '0');
      });

      test('999 → "999"', () {
        expect(formatCount(999), '999');
      });

      test('500 → "500"', () {
        expect(formatCount(500), '500');
      });
    });

    group('1000..9999 → x.yk', () {
      test('1000 → "1.0k"', () {
        expect(formatCount(1000), '1.0k');
      });

      test('1200 → "1.2k"', () {
        expect(formatCount(1200), '1.2k');
      });

      test('1500 → "1.5k"', () {
        expect(formatCount(1500), '1.5k');
      });

      test('9999 → "10.0k"(toStringAsFixed(1) 进位)', () {
        // 9999/1000 = 9.999 → toStringAsFixed(1) → "10.0"。
        // 当前实现的已知行为(若要修需在 formatCount 加四舍五入守卫)。
        expect(formatCount(9999), '10.0k');
      });
    });

    group('≥ 10000 → x.yw', () {
      test('10000 → "1.0w"', () {
        expect(formatCount(10000), '1.0w');
      });

      test('35000 → "3.5w"', () {
        expect(formatCount(35000), '3.5w');
      });

      test('23000 → "2.3w"', () {
        expect(formatCount(23000), '2.3w');
      });

      test('120000 → "12.0w"', () {
        expect(formatCount(120000), '12.0w');
      });
    });
  });

  group('parseCount ↔ formatCount 双向一致性(已支持的范围内)', () {
    test('parseCount("1.2k") → 1200 → formatCount → "1.2k"', () {
      expect(formatCount(parseCount('1.2k')), '1.2k');
    });

    test('parseCount("3.5w") → 35000 → formatCount → "3.5w"', () {
      expect(formatCount(parseCount('3.5w')), '3.5w');
    });

    test('parseCount("200") → 200 → formatCount → "200"', () {
      expect(formatCount(parseCount('200')), '200');
    });
  });
}
