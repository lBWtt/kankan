// Levenshtein 编辑距离 + 智能纠错建议单测。
//
// 覆盖 lib/core/utils/levenshtein.dart:
//   - levenshtein(a, b):两串编辑距离(替换/插入/删除各计 1)。
//   - suggestClosest(input, candidates, {maxDistance}):候选池中最近的一个,≤ maxDistance 才返回。
//
// 经典用例(注释里也写了):kitten→sitting=3、fluter→flutter=1、""→abc=3。
// 对称性是编辑距离的不变量,本测试也覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:kankan_flutter/core/utils/levenshtein.dart';

void main() {
  group('levenshtein', () {
    group('相同串 / 空串', () {
      test('完全相同 → 0', () {
        expect(levenshtein('flutter', 'flutter'), 0);
        expect(levenshtein('abc', 'abc'), 0);
        expect(levenshtein('', ''), 0);
      });

      test('空 a → b 的长度', () {
        expect(levenshtein('', 'abc'), 3);
        expect(levenshtein('', 'a'), 1);
      });

      test('空 b → a 的长度', () {
        expect(levenshtein('abc', ''), 3);
        expect(levenshtein('a', ''), 1);
      });
    });

    group('经典用例', () {
      test('kitten → sitting == 3(替换 k→s, e→i, 末尾插入 g)', () {
        expect(levenshtein('kitten', 'sitting'), 3);
      });

      test('flutter → fluter == 1(删一个 t)', () {
        expect(levenshtein('flutter', 'fluter'), 1);
      });

      test('Sunday → Saturday == 3(经典 DP 用例)', () {
        expect(levenshtein('Sunday', 'Saturday'), 3);
      });
    });

    group('单字符操作', () {
      test('单字符插入(cat → cats) == 1', () {
        expect(levenshtein('cat', 'cats'), 1);
      });

      test('单字符删除(cats → cat) == 1', () {
        expect(levenshtein('cats', 'cat'), 1);
      });

      test('单字符替换(cat → bat) == 1', () {
        expect(levenshtein('cat', 'bat'), 1);
      });

      test('两字符替换(cat → dog) == 3', () {
        expect(levenshtein('cat', 'dog'), 3);
      });
    });

    group('大小写敏感', () {
      test('Flutter vs flutter == 1(F vs f 替换)', () {
        expect(levenshtein('Flutter', 'flutter'), 1);
      });

      test('ABC vs abc == 3', () {
        expect(levenshtein('ABC', 'abc'), 3);
      });
    });

    group('对称性:levenshtein(a, b) == levenshtein(b, a)', () {
      test('kitten / sitting 对称', () {
        expect(levenshtein('kitten', 'sitting'),
            levenshtein('sitting', 'kitten'));
      });

      test('flutter / fluter 对称', () {
        expect(levenshtein('flutter', 'fluter'),
            levenshtein('fluter', 'flutter'));
      });

      test('空串与非空串对称', () {
        expect(levenshtein('', 'abc'), levenshtein('abc', ''));
      });
    });

    group('参数顺序不影响结果(实现里把短串放前面优化空间)', () {
      test('长在前 vs 短在前 结果一致', () {
        expect(levenshtein('a-b-c-d', 'a'), 6);
        expect(levenshtein('a', 'a-b-c-d'), 6);
      });
    });
  });

  group('suggestClosest', () {
    group('基本命中', () {
      test('fluter → flutter(距离 1)在候选池中返回 flutter', () {
        expect(
          suggestClosest('fluter', ['flutter', 'flux', 'react']),
          'flutter',
        );
      });

      test('完全匹配(距离 0)优先返回', () {
        expect(
          suggestClosest('flutter', ['react', 'flutter', 'flux']),
          'flutter',
        );
      });

      test('保留候选词原大小写(返回原词而非小写化版本)', () {
        expect(
          suggestClosest('fluter', ['Flutter', 'flux', 'react']),
          'Flutter',
        );
      });
    });

    group('大小写不敏感匹配', () {
      test('输入 FLUTER 仍能命中 Flutter(距离 1)', () {
        expect(suggestClosest('FLUTER', ['Flutter']), 'Flutter');
      });

      test('输入 flutter 命中 FLUTTER', () {
        expect(suggestClosest('flutter', ['FLUTTER']), 'FLUTTER');
      });
    });

    group('超出阈值 / 空集 → null', () {
      test('所有候选距离 > maxDistance → null', () {
        expect(
          suggestClosest('xyz', ['abc', 'def'], maxDistance: 2),
          isNull,
        );
      });

      test('候选池空 → null', () {
        expect(suggestClosest('flutter', []), isNull);
      });

      test('输入空串 → null', () {
        expect(suggestClosest('', ['flutter']), isNull);
      });

      test('输入纯空白 → null(trim 后空)', () {
        expect(suggestClosest('   ', ['flutter']), isNull);
      });

      test('候选词为空白串被跳过,若无其它可命中 → null', () {
        expect(suggestClosest('flutter', ['   ', '   ']), isNull);
      });
    });

    group('平局取候选池中第一个达到最小距离的', () {
      test('两个等距候选,返回靠前的', () {
        // 'flux' 与 'fluk' 对 'flut' 距离都为 1,但 flux 在前。
        final r = suggestClosest('flut', ['flux', 'fluk']);
        expect(r, 'flux');
      });
    });

    group('自定义 maxDistance', () {
      test('maxDistance=0 仅允许完全匹配', () {
        expect(
          suggestClosest('fluter', ['flutter'], maxDistance: 0),
          isNull,
        );
        expect(
          suggestClosest('flutter', ['flutter'], maxDistance: 0),
          'flutter',
        );
      });

      test('maxDistance=3 允许更大编辑距离', () {
        // kitten → sitting 距离 3,maxDistance 默认 2 不命中,3 命中。
        expect(
          suggestClosest('kitten', ['sitting'], maxDistance: 2),
          isNull,
        );
        expect(
          suggestClosest('kitten', ['sitting'], maxDistance: 3),
          'sitting',
        );
      });
    });

    group('trim 输入与候选', () {
      test('输入带空白仍能命中', () {
        expect(suggestClosest('  fluter  ', ['flutter']), 'flutter');
      });

      test('候选带空白也参与比较(trim 后)', () {
        expect(suggestClosest('fluter', ['  flutter  ']), '  flutter  ');
      });
    });
  });
}
